// Verifiziert den Sync der Abwesenheitszeiträume ("Urlaubsmodus") gegen einen
// echten, lokal gestarteten Server: Upload, Delta-Rückgabe über received_at,
// Last-Write-Wins, Tombstone-Löschung und - besonders wichtig für den
// Rollout - die Abwärtskompatibilität zu Clients, die das Feld noch nicht
// kennen.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'package:plant_watering_sync_server/auth_middleware.dart';
import 'package:plant_watering_sync_server/db/server_database.dart';
import 'package:plant_watering_sync_server/handlers/sync_handler.dart';

void main() {
  const token = 'test-token-absence';
  late Directory tempDir;
  late ServerDatabase db;
  late HttpServer httpServer;
  late String baseUrl;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('absence_sync_test');
    db = ServerDatabase.open('${tempDir.path}/sync.db');

    final router = Router()..post('/sync', SyncHandler(db).call);
    final pipeline =
        const Pipeline().addMiddleware(authMiddleware(expectedToken: token)).addHandler(router.call);
    httpServer = await shelf_io.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${httpServer.address.host}:${httpServer.port}';
  });

  tearDown(() async {
    await httpServer.close(force: true);
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> sync(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sync'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> request({
    required String deviceId,
    required DateTime lastSyncedAt,
    List<Map<String, dynamic>> absences = const [],
  }) =>
      {
        'deviceId': deviceId,
        'lastSyncedAt': lastSyncedAt.toUtc().toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
        'plants': <Map<String, dynamic>>[],
        'wateringEvents': <Map<String, dynamic>>[],
        'absences': absences,
      };

  Map<String, dynamic> absence({
    String id = 'abs-1',
    required DateTime start,
    required DateTime end,
    String? note,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      {
        'id': id,
        'startDate': start.toUtc().toIso8601String(),
        'endDate': end.toUtc().toIso8601String(),
        'note': note,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  test('ein hochgeladener Zeitraum erreicht das zweite Gerät', () async {
    final start = DateTime.utc(2025, 7, 10);
    final end = DateTime.utc(2025, 7, 24);

    await sync(request(
      deviceId: 'phone',
      lastSyncedAt: epoch,
      absences: [
        absence(start: start, end: end, note: 'Sommerurlaub', updatedAt: DateTime.utc(2025, 7, 1)),
      ],
    ));

    final second = await sync(request(deviceId: 'tablet', lastSyncedAt: epoch));
    final absences = second['absences'] as List<dynamic>;

    expect(absences, hasLength(1));
    final received = absences.single as Map<String, dynamic>;
    expect(received['id'], 'abs-1');
    expect(DateTime.parse(received['startDate'] as String), start);
    expect(DateTime.parse(received['endDate'] as String), end);
    expect(received['note'], 'Sommerurlaub');
    expect(received['deletedAt'], isNull);
  });

  test('Last-Write-Wins: ein älteres Update überschreibt ein neueres nicht', () async {
    await sync(request(
      deviceId: 'phone',
      lastSyncedAt: epoch,
      absences: [
        absence(
          start: DateTime.utc(2025, 7, 10),
          end: DateTime.utc(2025, 7, 24),
          updatedAt: DateTime.utc(2025, 7, 5),
        ),
      ],
    ));

    // Älterer Stand vom zweiten Gerät - muss verworfen werden.
    await sync(request(
      deviceId: 'tablet',
      lastSyncedAt: epoch,
      absences: [
        absence(
          start: DateTime.utc(2025, 1, 1),
          end: DateTime.utc(2025, 1, 2),
          updatedAt: DateTime.utc(2025, 7, 1),
        ),
      ],
    ));

    final result = await sync(request(deviceId: 'phone2', lastSyncedAt: epoch));
    final received = (result['absences'] as List<dynamic>).single as Map<String, dynamic>;
    expect(DateTime.parse(received['startDate'] as String), DateTime.utc(2025, 7, 10));
  });

  test('eine Löschung reist als Tombstone, nicht als verschwundener Datensatz', () async {
    await sync(request(
      deviceId: 'phone',
      lastSyncedAt: epoch,
      absences: [
        absence(
          start: DateTime.utc(2025, 7, 10),
          end: DateTime.utc(2025, 7, 24),
          updatedAt: DateTime.utc(2025, 7, 1),
        ),
      ],
    ));

    await sync(request(
      deviceId: 'phone',
      lastSyncedAt: epoch,
      absences: [
        absence(
          start: DateTime.utc(2025, 7, 10),
          end: DateTime.utc(2025, 7, 24),
          updatedAt: DateTime.utc(2025, 8, 1),
          deletedAt: DateTime.utc(2025, 8, 1),
        ),
      ],
    ));

    final result = await sync(request(deviceId: 'tablet', lastSyncedAt: epoch));
    final received = (result['absences'] as List<dynamic>).single as Map<String, dynamic>;
    expect(received['deletedAt'], isNotNull,
        reason: 'Ohne Tombstone ließe ein lange offline gewesenes Gerät den '
            'Zeitraum wieder auferstehen');
  });

  test('ein Client ohne absences-Feld wird weiterhin bedient', () async {
    // Genau der Rollout-Fall: ein noch nicht aktualisiertes Gerät schickt das
    // Feld nicht mit. Ohne Default im DTO würde sein kompletter Sync mit 400
    // scheitern - inklusive Räume, Pflanzen und Gieß-Events.
    final response = await http.post(
      Uri.parse('$baseUrl/sync'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
      body: jsonEncode({
        'deviceId': 'altes-handy',
        'lastSyncedAt': epoch.toIso8601String(),
        'rooms': <Map<String, dynamic>>[],
        'plants': <Map<String, dynamic>>[],
        'wateringEvents': <Map<String, dynamic>>[],
      }),
    );

    expect(response.statusCode, 200, reason: response.body);
    expect((jsonDecode(response.body) as Map<String, dynamic>)['absences'], isEmpty);
  });
}
