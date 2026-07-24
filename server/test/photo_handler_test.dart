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

  test('Upload aktualisiert received_at, damit sich ein reiner Foto-Wechsel '
      'im Metadaten-Sync propagiert', () async {
    final before =
        db.raw.select('SELECT received_at FROM plants WHERE id = ?', ['p1']).first['received_at']
            as int;

    // Kleine, aber sichere Wartezeit, damit der neue Zeitstempel garantiert
    // größer ist als der Insert-Zeitstempel aus setUp.
    await Future.delayed(const Duration(milliseconds: 5));

    final bytes = Uint8List.fromList([1, 2, 3]);
    final uploadRequest = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'));
    final response = await http.Response.fromStream(await uploadRequest.send());
    expect(response.statusCode, 200);

    final after =
        db.raw.select('SELECT received_at FROM plants WHERE id = ?', ['p1']).first['received_at']
            as int;
    expect(after, greaterThan(before));
  });

  test('Upload mit veraltetem erwarteten Vorgänger-Stand liefert 409 und '
      'überschreibt das bereits hochgeladene Foto nicht', () async {
    final firstBytes = Uint8List.fromList([1, 2, 3]);
    final firstUpload = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', firstBytes, filename: 'photo.jpg'));
    final firstResponse = await http.Response.fromStream(await firstUpload.send());
    expect(firstResponse.statusCode, 200);

    // Zweites Gerät kennt noch den Stand VOR firstUpload (leer) und versucht,
    // ein eigenes Foto hochzuladen – der Server muss das ablehnen, da sich
    // der Stand zwischenzeitlich geändert hat.
    final secondBytes = Uint8List.fromList([4, 5, 6]);
    final conflictingUpload = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v2'
      ..headers['x-expected-photo-version'] = 'hash-v0-nie-existiert'
      ..files.add(http.MultipartFile.fromBytes('file', secondBytes, filename: 'photo.jpg'));
    final conflictingResponse = await http.Response.fromStream(await conflictingUpload.send());
    expect(conflictingResponse.statusCode, 409);

    final downloadResponse = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(downloadResponse.bodyBytes, equals(firstBytes));
  });

  test('Upload mit passendem erwarteten Vorgänger-Stand wird angenommen', () async {
    final firstBytes = Uint8List.fromList([1, 2, 3]);
    final firstUpload = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', firstBytes, filename: 'photo.jpg'));
    await http.Response.fromStream(await firstUpload.send());

    final secondBytes = Uint8List.fromList([4, 5, 6]);
    final secondUpload = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-v2'
      ..headers['x-expected-photo-version'] = 'hash-v1'
      ..files.add(http.MultipartFile.fromBytes('file', secondBytes, filename: 'photo.jpg'));
    final secondResponse = await http.Response.fromStream(await secondUpload.send());
    expect(secondResponse.statusCode, 200);

    final downloadResponse = await http.get(
      Uri.parse('$baseUrl/plants/p1/photo'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(downloadResponse.bodyBytes, equals(secondBytes));
  });

  test('Upload eines zu großen Fotos liefert 413, ohne den kompletten Body '
      'zu puffern', () async {
    // Größer als _maxPhotoBytes (10 MB) – falls das Streaming-Limit nicht
    // greifen würde, würde dieser Test durch Speicherverbrauch/Timeout statt
    // durch eine saubere 413-Assertion auffallen.
    final oversized = Uint8List(10 * 1024 * 1024 + 1);
    final uploadRequest = http.MultipartRequest('PUT', Uri.parse('$baseUrl/plants/p1/photo'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['x-photo-version'] = 'hash-oversized'
      ..files.add(http.MultipartFile.fromBytes('file', oversized, filename: 'photo.jpg'));

    final response = await http.Response.fromStream(await uploadRequest.send());
    expect(response.statusCode, 413);
  });
}
