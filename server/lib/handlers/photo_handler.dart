import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/server_database.dart';
import '../photo_store.dart';

/// Maximale Upload-Größe für ein einzelnes Foto. shelf begrenzt Request-
/// Bodies standardmäßig nicht – ohne dieses Limit könnte ein fehlerhafter
/// oder böswilliger Client unbegrenzt Speicher auf dem Homeserver füllen.
const int _maxPhotoBytes = 10 * 1024 * 1024;

/// Nimmt Fotos für Pflanzen entgegen und liefert sie aus. Rein Rohdaten-
/// Transport – keine serverseitige Bildverarbeitung (Resizing, Thumbnails),
/// analog zum Architektur-Grundsatz "Server speichert nur Rohdaten, rechnet
/// nichts" (siehe PHOTO_SYNC_DESIGN.md).
class PhotoHandler {
  final ServerDatabase _db;
  final ServerPhotoStore _store;

  PhotoHandler(this._db, this._store);

  Future<Response> upload(Request request) async {
    final plantId = request.params['id'];
    if (plantId == null) {
      return Response(400, body: jsonEncode({'error': 'missing_plant_id'}));
    }

    final exists = _db.raw.select('SELECT 1 FROM plants WHERE id = ?', [plantId]);
    if (exists.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'plant_not_found'}));
    }

    final contentLength = request.contentLength;
    if (contentLength != null && contentLength > _maxPhotoBytes) {
      return Response(413, body: jsonEncode({'error': 'photo_too_large'}));
    }

    final multipart = request.multipart();
    if (multipart == null) {
      return Response(400, body: jsonEncode({'error': 'expected_multipart'}));
    }

    Uint8List? bytes;
    await for (final part in multipart.parts) {
      bytes = await part.readBytes();
      break;
    }
    if (bytes == null) {
      return Response(400, body: jsonEncode({'error': 'missing_file_part'}));
    }
    if (bytes.length > _maxPhotoBytes) {
      return Response(413, body: jsonEncode({'error': 'photo_too_large'}));
    }

    final version = request.headers['x-photo-version'];
    if (version == null || version.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'missing_photo_version'}));
    }

    await _store.write(plantId, bytes);
    _db.raw.execute('UPDATE plants SET photo_version = ? WHERE id = ?', [version, plantId]);

    return Response.ok(
      jsonEncode({'version': version}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> download(Request request) async {
    final plantId = request.params['id'];
    if (plantId == null) {
      return Response(400, body: jsonEncode({'error': 'missing_plant_id'}));
    }

    final rows = _db.raw.select('SELECT photo_version FROM plants WHERE id = ?', [plantId]);
    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'plant_not_found'}));
    }
    final currentVersion = rows.first['photo_version'] as String?;

    final expectedVersion = request.url.queryParameters['version'];
    if (expectedVersion != null && expectedVersion != currentVersion) {
      // Client fragt eine Version an, die der Server nicht (mehr) hat – z. B.
      // weil zwischen zwei Sync-Aufrufen ein drittes Gerät bereits ein neueres
      // Foto hochgeladen hat. Statt eine möglicherweise überholte Datei
      // auszuliefern, meldet der Server den Konflikt zurück; der Client sieht
      // die neue Version ohnehin beim nächsten /sync-Aufruf.
      return Response(409, body: jsonEncode({'error': 'version_mismatch'}));
    }

    final bytes = await _store.read(plantId);
    if (bytes == null) {
      return Response.notFound(jsonEncode({'error': 'photo_not_found'}));
    }

    return Response.ok(bytes, headers: {'content-type': 'image/jpeg'});
  }
}
