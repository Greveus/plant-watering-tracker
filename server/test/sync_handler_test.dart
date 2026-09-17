// Verifiziert den Kernpfad des Sync-Servers gegen einen echt gestarteten
// Server: Last-Write-Wins für Räume und Pflanzen, die additive Dedup-Semantik
// für Gieß-Events, Tombstones – und vor allem den Delta-Filter über
// received_at (Server-Uhr) statt über die client-generierten Zeitstempel.
//
// Der received_at-Test ist der wichtigste der Datei: Er prüft genau die
// Eigenschaft, für die das gesamte received_at-Konzept eingeführt wurde
// (siehe Kommentar in server_database.dart) – ein Client mit nachgehender
// Uhr darf keine Änderung verpassen.

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
  const token = 'test-token-sync';
  late Directory tempDir;
  late ServerDatabase db;
  late HttpServer httpServer;
  late String baseUrl;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sync_handler_test');
    db = ServerDatabase.open('${tempDir.path}/sync.db');

    final router = Router()..post('/sync', SyncHandler(db).call);
    final pipeline = const Pipeline()
        .addMiddleware(authMiddleware(expectedToken: token))
        .addHandler(router.call);
    httpServer = await shelf_io.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${httpServer.address.host}:${httpServer.port}';
  });

  tearDown(() async {
    await httpServer.close(force: true);
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<http.Response> post(Map<String, dynamic> body) {
    return http.post(
      Uri.parse('$baseUrl/sync'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
  }

  Future<Map<String, dynamic>> sync(Map<String, dynamic> body) async {
    final response = await post(body);
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> request({
    String deviceId = 'device-a',
    required DateTime lastSyncedAt,
    List<Map<String, dynamic>> rooms = const [],
    List<Map<String, dynamic>> plants = const [],
    List<Map<String, dynamic>> wateringEvents = const [],
  }) =>
      {
        'deviceId': deviceId,
        'lastSyncedAt': lastSyncedAt.toUtc().toIso8601String(),
        'rooms': rooms,
        'plants': plants,
        'wateringEvents': wateringEvents,
        'absences': <Map<String, dynamic>>[],
      };

  Map<String, dynamic> room({
    String id = 'room-1',
    String name = 'Wohnzimmer',
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      {
        'id': id,
        'name': name,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> plant({
    String id = 'plant-1',
    String nickname = 'Monstera',
    String roomId = 'room-1',
    String? photoVersion,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      {
        'id': id,
        'nickname': nickname,
        'presetId': null,
        'speciesFreeText': null,
        'roomId': roomId,
        'photoPath': null,
        'photoVersion': photoVersion,
        'createdAt': DateTime.utc(2025, 1, 1).toIso8601String(),
        'sizeCategory': 'mittel',
        'manualIntervalDays': null,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> event({
    String id = 'event-1',
    String plantId = 'plant-1',
    required DateTime timestamp,
    String? feedbackTag,
  }) =>
      {
        'id': id,
        'plantId': plantId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'feedbackTag': feedbackTag,
        'note': null,
        'receivedAt': null,
      };

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  group('Last-Write-Wins', () {
    test('ein neuerer Stand überschreibt den älteren', () async {
      await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(name: 'Alt', updatedAt: DateTime.utc(2025, 6, 1))],
      ));
      await sync(request(
        deviceId: 'device-b',
        lastSyncedAt: epoch,
        rooms: [room(name: 'Neu', updatedAt: DateTime.utc(2025, 6, 2))],
      ));

      final response = await sync(request(deviceId: 'device-c', lastSyncedAt: epoch));
      final rooms = response['rooms'] as List;
      expect(rooms, hasLength(1));
      expect((rooms.first as Map)['name'], 'Neu');
    });

    test('ein älterer Stand überschreibt den neueren nicht', () async {
      await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(name: 'Neu', updatedAt: DateTime.utc(2025, 6, 2))],
      ));
      await sync(request(
        deviceId: 'device-b',
        lastSyncedAt: epoch,
        rooms: [room(name: 'Alt', updatedAt: DateTime.utc(2025, 6, 1))],
      ));

      final response = await sync(request(deviceId: 'device-c', lastSyncedAt: epoch));
      expect(((response['rooms'] as List).first as Map)['name'], 'Neu');
    });

    test('bei identischem updatedAt gewinnt der bestehende Server-Stand', () async {
      final sameMoment = DateTime.utc(2025, 6, 1, 12);
      await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(name: 'Zuerst', updatedAt: sameMoment)],
      ));
      await sync(request(
        deviceId: 'device-b',
        lastSyncedAt: epoch,
        rooms: [room(name: 'Danach', updatedAt: sameMoment)],
      ));

      final response = await sync(request(deviceId: 'device-c', lastSyncedAt: epoch));
      expect(((response['rooms'] as List).first as Map)['name'], 'Zuerst',
          reason: 'Der Vergleich ist striktes >, nicht >=');
    });

    test('ein abgelehnter Push fasst received_at nicht an', () async {
      // Sonst bekäme jedes Gerät bei jedem Sync alle jemals abgelehnten
      // Datensätze erneut zugestellt, obwohl sich am Serverstand nichts
      // geändert hat.
      await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(name: 'Neu', updatedAt: DateTime.utc(2025, 6, 2))],
      ));
      final afterFirst = await sync(request(deviceId: 'device-b', lastSyncedAt: epoch));
      final serverTimeAfterFirst = DateTime.parse(afterFirst['serverTime'] as String);

      // Veralteter Push von Gerät B – wird verworfen.
      await sync(request(
        deviceId: 'device-b',
        lastSyncedAt: serverTimeAfterFirst,
        rooms: [room(name: 'Alt', updatedAt: DateTime.utc(2025, 6, 1))],
      ));

      final delta = await sync(
        request(deviceId: 'device-c', lastSyncedAt: serverTimeAfterFirst),
      );
      expect(delta['rooms'], isEmpty,
          reason: 'Der abgelehnte Push darf den Datensatz nicht erneut ins Delta heben');
    });
  });

  group('Delta-Filter über received_at', () {
    test('eine nachgehende Client-Uhr lässt keine Änderung verpassen', () async {
      // Kern des received_at-Konzepts: Gerät A hat eine um Stunden
      // NACHGEHENDE Uhr. Liefe der Delta-Filter über das client-generierte
      // updatedAt, läge dieser Wert vor dem lastSyncedAt des zweiten Geräts
      // und die Änderung würde übersprungen.
      final clientClockBehind = DateTime.utc(2020, 1, 1);
      await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(name: 'Von der nachgehenden Uhr', updatedAt: clientClockBehind)],
      ));

      // Gerät B hat zuletzt "gestern" synchronisiert – also lange nach dem
      // updatedAt des hochgeladenen Raums, aber vor dessen Empfang am Server.
      final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final response = await sync(request(deviceId: 'device-b', lastSyncedAt: yesterday));

      expect((response['rooms'] as List), hasLength(1),
          reason: 'Der Filter muss über die Server-Uhr laufen, nicht über updatedAt');
    });

    test('bereits abgeholte Änderungen kommen nicht erneut', () async {
      final first = await sync(request(
        lastSyncedAt: epoch,
        rooms: [room(updatedAt: DateTime.utc(2025, 6, 1))],
        plants: [plant(updatedAt: DateTime.utc(2025, 6, 1))],
      ));
      final serverTime = DateTime.parse(first['serverTime'] as String);

      final second = await sync(request(deviceId: 'device-b', lastSyncedAt: serverTime));
      expect(second['rooms'], isEmpty);
      expect(second['plants'], isEmpty);
      expect(second['wateringEvents'], isEmpty);
    });
  });

  group('Gieß-Events sind rein additiv', () {
    test('dasselbe Event zweimal geschickt wird nur einmal gespeichert', () async {
      final e = event(timestamp: DateTime.utc(2025, 6, 1, 10));
      await sync(request(lastSyncedAt: epoch, wateringEvents: [e]));
      await sync(request(deviceId: 'device-b', lastSyncedAt: epoch, wateringEvents: [e]));

      final response = await sync(request(deviceId: 'device-c', lastSyncedAt: epoch));
      expect(response['wateringEvents'], hasLength(1));
    });

    test('ein erneut geschicktes Event überschreibt den Serverstand nicht', () async {
      await sync(request(
        lastSyncedAt: epoch,
        wateringEvents: [event(timestamp: DateTime.utc(2025, 6, 1, 10), feedbackTag: 'passend')],
      ));
      // Gleiche ID, abweichender Inhalt – INSERT OR IGNORE muss ihn verwerfen.
      await sync(request(
        deviceId: 'device-b',
        lastSyncedAt: epoch,
        wateringEvents: [event(timestamp: DateTime.utc(2025, 6, 5, 10), feedbackTag: 'zuSpaet')],
      ));

      final response = await sync(request(deviceId: 'device-c', lastSyncedAt: epoch));
      final events = response['wateringEvents'] as List;
      expect(events, hasLength(1));
      expect((events.first as Map)['feedbackTag'], 'passend');
    });

    test('ein rückwirkend eingetragenes Event erreicht das zweite Gerät', () async {
      // Der Gieß-Zeitpunkt liegt weit VOR dem letzten Sync des Partnergeräts.
      // Genau dafür läuft der Delta-Filter über received_at: über timestamp
      // gefiltert wäre dieses Event für Gerät B unsichtbar.
      final firstSync = await sync(request(lastSyncedAt: epoch));
      final serverTime = DateTime.parse(firstSync['serverTime'] as String);

      await sync(request(
        lastSyncedAt: serverTime,
        wateringEvents: [event(timestamp: DateTime.utc(2020, 1, 1))],
      ));

      final response = await sync(request(deviceId: 'device-b', lastSyncedAt: serverTime));
      expect(response['wateringEvents'], hasLength(1),
          reason: 'Rückwirkend erfasste Gieß-Events müssen zuverlässig ankommen');
    });
  });

  group('Tombstones', () {
    test('eine Löschung reist als Tombstone, nicht als verschwundener Datensatz', () async {
      await sync(request(
        lastSyncedAt: epoch,
        plants: [plant(updatedAt: DateTime.utc(2025, 6, 1))],
      ));
      await sync(request(
        lastSyncedAt: epoch,
        plants: [
          plant(updatedAt: DateTime.utc(2025, 6, 2), deletedAt: DateTime.utc(2025, 6, 2)),
        ],
      ));

      final response = await sync(request(deviceId: 'device-b', lastSyncedAt: epoch));
      final plants = response['plants'] as List;
      expect(plants, hasLength(1));
      expect((plants.first as Map)['deletedAt'], isNotNull);
    });
  });

  group('Fehlerhafte Anfragen', () {
    test('ungültiges JSON liefert 400', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/sync'),
        headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
        body: '{nicht wirklich json',
      );
      expect(response.statusCode, 400);
      expect(jsonDecode(response.body), containsPair('error', 'invalid_json'));
    });

    test('ein fehlendes Pflichtfeld liefert 400 statt 500', () async {
      // Regressionstest: Zuvor lief die DTO-Deserialisierung außerhalb jeder
      // Fehlerbehandlung. Ein einziger unlesbarer Datensatz erzeugte damit
      // einen 500, den der Client als "Server nicht erreichbar" liest – und
      // da er denselben Datensatz beim nächsten Versuch erneut schickt,
      // synchronisierte das Gerät nie wieder.
      // name und updatedAt fehlen – die generierte fromJson-Factory wirft.
      final body = request(lastSyncedAt: epoch, rooms: [
        {'id': 'room-1'},
      ]);

      final response = await post(body);
      expect(response.statusCode, 400);
      expect(jsonDecode(response.body), containsPair('error', 'invalid_payload'));
    });

    test('ein Sync ohne Token wird abgelehnt', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/sync'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(request(lastSyncedAt: epoch)),
      );
      expect(response.statusCode, 403);
    });
  });
}
