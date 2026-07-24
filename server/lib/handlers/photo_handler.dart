import 'dart:convert';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/server_database.dart';
import '../photo_store.dart';

/// Maximale Upload-Größe für ein einzelnes Foto. shelf begrenzt Request-
/// Bodies standardmäßig nicht – ohne dieses Limit könnte ein fehlerhafter
/// oder böswilliger Client unbegrenzt Speicher auf dem Homeserver füllen.
const int _maxPhotoBytes = 10 * 1024 * 1024;

/// Signalisiert einen Abbruch beim chunk-weisen Einlesen, sobald
/// [_maxPhotoBytes] überschritten wird (siehe `_readBoundedBytes`) – wird nie
/// über die Grenzen dieser Datei hinaus geworfen.
class _PhotoTooLargeException implements Exception {
  const _PhotoTooLargeException();
}

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

    final rows = _db.raw.select('SELECT photo_version FROM plants WHERE id = ?', [plantId]);
    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'plant_not_found'}));
    }
    final currentVersion = rows.first['photo_version'] as String?;

    // Optimistic Locking: der Client schickt die photoVersion, die er vor
    // diesem Upload zuletzt kannte. Weicht sie vom tatsächlichen Serverstand
    // ab, hat zwischenzeitlich ein anderes Gerät ein neueres Foto hochgeladen
    // – dieser Upload würde es sonst stillschweigend überschreiben. Fehlt der
    // Header (Erst-Upload eines neuen Fotos ohne bekannten Vorgänger), wird
    // nicht geprüft.
    final expectedPriorVersion = request.headers['x-expected-photo-version'];
    if (expectedPriorVersion != null && expectedPriorVersion != currentVersion) {
      return Response(409, body: jsonEncode({'error': 'version_mismatch'}));
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
    try {
      await for (final part in multipart.parts) {
        bytes = await _readBoundedBytes(part);
        break;
      }
    } on _PhotoTooLargeException {
      return Response(413, body: jsonEncode({'error': 'photo_too_large'}));
    }
    if (bytes == null) {
      return Response(400, body: jsonEncode({'error': 'missing_file_part'}));
    }

    final version = request.headers['x-photo-version'];
    if (version == null || version.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'missing_photo_version'}));
    }

    await _store.write(plantId, bytes);
    final receivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    // received_at MUSS mitgeschrieben werden: der Metadaten-Sync filtert
    // ausschließlich darüber, "was ist neu" (siehe PlantRepository.updatedSince
    // und der Kommentar in server_database.dart zur Client/Server-Uhrzeit-
    // Drift). Ohne dieses Update würde ein reiner Foto-Wechsel – ohne
    // begleitende Änderung an nickname/roomId/etc. – für andere Geräte nie als
    // Änderung sichtbar und ihr Foto bliebe dauerhaft veraltet.
    _db.raw.execute(
      'UPDATE plants SET photo_version = ?, received_at = ? WHERE id = ?',
      [version, receivedAt, plantId],
    );

    return Response.ok(
      jsonEncode({'version': version}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Liest einen Multipart-Teil in Chunks statt über `readBytes()` in einem
  /// Rutsch: bricht ab, sobald [_maxPhotoBytes] überschritten wird, statt
  /// zuerst den kompletten (potenziell sehr großen) Body in den Speicher zu
  /// puffern und die Größe erst danach zu prüfen.
  Future<Uint8List> _readBoundedBytes(MimeMultipart part) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in part) {
      builder.add(chunk);
      if (builder.length > _maxPhotoBytes) {
        throw const _PhotoTooLargeException();
      }
    }
    return builder.takeBytes();
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
