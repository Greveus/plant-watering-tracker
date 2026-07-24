import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
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
    if (!_isValidPlantId(plantId)) {
      return Response(400, body: jsonEncode({'error': 'invalid_plant_id'}));
    }

    final exists = _db.raw.select('SELECT 1 FROM plants WHERE id = ?', [plantId]);
    if (exists.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'plant_not_found'}));
    }

    int? contentLength;
    try {
      contentLength = request.contentLength;
    } on FormatException {
      // request.contentLength parst den Content-Length-Header intern via
      // int.parse und wirft bei einem nicht-numerischen Wert – ohne diesen
      // Fang würde ein fehlerhafter Client hier einen unkontrollierten 500
      // statt einer sauberen 400-Antwort auslösen.
      return Response(400, body: jsonEncode({'error': 'invalid_content_length'}));
    }
    // Ein negativer Wert bestünde die reine ">"-Prüfung fälschlich immer;
    // die eigentliche Verteidigungslinie gegen zu große Uploads bleibt
    // ohnehin _readBoundedBytes (siehe dort), dieser Check ist nur ein
    // Fast-Path für den Normalfall.
    if (contentLength != null && (contentLength < 0 || contentLength > _maxPhotoBytes)) {
      return Response(413, body: jsonEncode({'error': 'photo_too_large'}));
    }

    final multipart = request.multipart();
    if (multipart == null) {
      return Response(400, body: jsonEncode({'error': 'expected_multipart'}));
    }

    Uint8List? bytes;
    try {
      await for (final part in multipart.parts) {
        // Nur das erste Part wird als Foto interpretiert; der Client schickt
        // laut Protokoll genau eine Datei pro Upload (siehe
        // HttpPhotoTransferGateway.upload). shelf_io konsumiert und verwirft
        // den Rest des Request-Bodies beim Antworten selbstständig (siehe
        // dart:io HttpRequest-Doku: nicht gelesene Body-Daten werden beim
        // Schließen der Response automatisch verworfen) – ein zweites Part
        // würde also weder hängen noch fälschlich als verarbeitet gelten.
        bytes = await _readBoundedBytes(part);
        break;
      }
    } on _PhotoTooLargeException {
      // ignore: avoid_print
      print('photo upload rejected: too large, plant=$plantId');
      return Response(413, body: jsonEncode({'error': 'photo_too_large'}));
    }
    if (bytes == null) {
      return Response(400, body: jsonEncode({'error': 'missing_file_part'}));
    }

    final version = request.headers['x-photo-version'];
    if (version == null || version.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'missing_photo_version'}));
    }

    // Optimistic Locking als atomares Compare-and-Swap: Prüfung und
    // Schreiben laufen in EINEM UPDATE-Statement, nicht als separates SELECT
    // gefolgt von einem späteren UPDATE. Ein separates SELECT davor wäre
    // durch die await-Punkte beim Lesen des Multipart-Bodies (oben) einem
    // TOCTOU-Fenster ausgesetzt: zwei nahezu gleichzeitige Uploads könnten
    // beide denselben alten Stand lesen, beide die Prüfung bestehen und sich
    // gegenseitig überschreiben, ohne dass einer der beiden einen 409 sieht.
    // Die WHERE-Klausel selbst ist der Lock: das UPDATE betrifft nur dann
    // eine Zeile, wenn photo_version zum Ausführungszeitpunkt noch exakt dem
    // erwarteten Vorgänger-Stand entspricht (inkl. NULL-Fall beim Erst-Upload
    // ohne bekannten Vorgänger).
    //
    // Datei wird ERST NACH dem erfolgreichen DB-Update geschrieben: schlägt
    // das Update fehl (Versionskonflikt), bleibt der bisherige Dateiinhalt
    // unverändert – bei umgekehrter Reihenfolge (Datei zuerst) könnte ein
    // abgelehnter Upload trotzdem die Datei überschrieben haben, während die
    // DB-Metadaten weiterhin auf den alten (jetzt falschen) Stand zeigen.
    final expectedPriorVersion = request.headers['x-expected-photo-version'];
    final receivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    _db.raw.execute(
      '''
      UPDATE plants SET photo_version = ?, received_at = ?
      WHERE id = ? AND (
        (? IS NULL) OR
        (photo_version IS NULL AND ? IS NULL) OR
        (photo_version = ?)
      )
      ''',
      [
        version,
        receivedAt,
        plantId,
        expectedPriorVersion,
        expectedPriorVersion,
        expectedPriorVersion,
      ],
    );
    if (_db.raw.updatedRows == 0) {
      return Response(409, body: jsonEncode({'error': 'version_mismatch'}));
    }

    await _store.write(plantId, bytes);

    return Response.ok(
      jsonEncode({'version': version}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Plant-IDs werden client-seitig immer als UUID v4 generiert (siehe
  /// `const Uuid().v4()` im Flutter-Client). Eine Validierung hier verhindert,
  /// dass eine über den regulären /sync-Endpunkt eingeschleuste, nicht-UUID-
  /// förmige ID (z. B. mit `../`-Sequenzen) über [ServerPhotoStore] in einen
  /// Dateipfad außerhalb des Foto-Verzeichnisses interpoliert wird.
  bool _isValidPlantId(String plantId) {
    return RegExp(r'^[0-9a-fA-F-]{1,64}$').hasMatch(plantId) &&
        !plantId.contains('..') &&
        !plantId.contains('/') &&
        !plantId.contains(r'\');
  }

  /// Liest einen Multipart-Teil in Chunks statt über `readBytes()` in einem
  /// Rutsch: bricht ab, sobald [_maxPhotoBytes] überschritten wird, statt
  /// zuerst den kompletten (potenziell sehr großen) Body in den Speicher zu
  /// puffern und die Größe erst danach zu prüfen.
  @visibleForTesting
  Future<Uint8List> readBoundedBytesForTesting(Stream<List<int>> part) => _readBoundedBytes(part);

  Future<Uint8List> _readBoundedBytes(Stream<List<int>> part) async {
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
    if (!_isValidPlantId(plantId)) {
      return Response(400, body: jsonEncode({'error': 'invalid_plant_id'}));
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
