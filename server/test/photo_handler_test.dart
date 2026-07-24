// Verifiziert den Foto-Upload/Download-Roundtrip End-to-End gegen einen
// echten, lokal gestarteten Server (nicht nur den Handler isoliert), da das
// multipart-Parsing und die Header-Behandlung realistischer über einen
// echten HTTP-Roundtrip getestet werden als über direkte Handler-Aufrufe.

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'package:plant_watering_sync_server/auth_middleware.dart';
import 'package:plant_watering_sync_server/db/server_database.dart';
import 'package:plant_watering_sync_server/handlers/photo_handler.dart';
import 'package:plant_watering_sync_server/photo_store.dart';

void main() {
  const token = 'test-token-photo';
  late Directory tempDir;
  late ServerDatabase db;
  late HttpServer httpServer;
  late String baseUrl;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('photo_handler_test');
    db = ServerDatabase.open('${tempDir.path}/sync.db');

    final roomId = 'r1';
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    db.raw.execute(
      'INSERT INTO rooms (id, name, updated_at, received_at) VALUES (?, ?, ?, ?)',
      [roomId, 'Wohnzimmer', now, now],
    );
    db.raw.execute(
      '''
      INSERT INTO plants (
        id, nickname, room_id, created_at, size_category, updated_at, received_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      ['p1', 'Testpflanze', roomId, now, 'mittel', now, now],
    );

    final photoHandler = PhotoHandler(db, ServerPhotoStore(Directory('${tempDir.path}/photos')));
    final router = Router()
      ..put('/plants/<id>/photo', photoHandler.upload)
      ..get('/plants/<id>/photo', photoHandler.download);
    final pipeline = const Pipeline()
        .addMiddleware(authMiddleware(expectedToken: token))
        .addHandler(router.call);

    httpServer = await shelf_io.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${httpServer.port}';
  });

  tearDown(() async {
    await httpServer.close(force: true);
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('Upload und Download liefern identische Bytes zurück', () async {
    final fakeJpegBytes = Uint8List.fromList(List.generate(256, (i) => i % 256));

    final uploadRequest = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', fakeJpegBytes, filename: 'photo.jpg'));

    final uploadResponse = await http.Response.fromStream(await uploadRequest.send());
    expect(uploadResponse.statusCode, 200);
    expect(uploadResponse.body, contains('hash-v1'));

    final downloadResponse = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(downloadResponse.statusCode, 200);
    expect(downloadResponse.bodyBytes, equals(fakeJpegBytes));
  });

  test('Download mit passender erwarteter Version funktioniert', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final uploadRequest = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'));
    await http.Response.fromStream(await uploadRequest.send());

    final response = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo?version=hash-v1'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(response.statusCode, 200);
  });

  test('Download mit veralteter erwarteter Version liefert 409', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final uploadRequest = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'));
    await http.Response.fromStream(await uploadRequest.send());

    final response = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo?version=stale-hash'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(response.statusCode, 409);
  });

  test('Upload ohne gültigen Token wird abgelehnt', () async {
    final response = await http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/plants/p1/photo'),
    ).send();
    expect(response.statusCode, 403);
  });

  test('Upload für unbekannte Pflanze liefert 404', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final uploadRequest = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/plants/unbekannt/photo'),
    )
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'));

    final response = await http.Response.fromStream(await uploadRequest.send());
    expect(response.statusCode, 404);
  });

  test('Download ohne vorhandenes Foto liefert 404', () async {
    final response = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(response.statusCode, 404);
  });
}
