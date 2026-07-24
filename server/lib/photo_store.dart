import 'dart:io';
import 'dart:typed_data';

/// Persistiert Pflanzenfotos als einzelne Dateien unter [directory], eine pro
/// Pflanze (Dateiname = Plant-ID, keine Historie). Ein neuer Upload
/// überschreibt die vorhandene Datei – "aktuelles Foto ersetzen" ist damit ein
/// simples Datei-Überschreiben ohne separate Cleanup-Logik für alte Stände.
/// Bewusst kein SQL/BLOB-Storage (siehe PHOTO_SYNC_DESIGN.md, Abschnitt 8):
/// hält die SQLite-Datei schlank, Zugriff ist ein einfacher Dateisystem-Read.
class ServerPhotoStore {
  final Directory directory;

  ServerPhotoStore(this.directory) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  /// Fester `.jpg`-Suffix unabhängig vom tatsächlich hochgeladenen Content-
  /// Type: bewusste Design-Entscheidung, kein übersehener Bug. Der einzige
  /// Client (Flutter-App) schickt laut Protokoll immer JPEG-komprimierte
  /// Bytes (`image_picker` mit `imageQuality: 80`, siehe
  /// `PlantPhotoStore.pickAndStore`) – der Server verlässt sich auf diesen
  /// Vertrag, statt den Content-Type serverseitig zu validieren, da er
  /// laut Architektur-Grundsatz "nur Rohdaten speichern, nicht prüfen/
  /// verarbeiten" bewusst keine Bildverarbeitung betreibt.
  File _fileFor(String plantId) => File('${directory.path}/$plantId.jpg');

  Future<void> write(String plantId, Uint8List bytes) async {
    await _fileFor(plantId).writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> read(String plantId) async {
    final file = _fileFor(plantId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Wird bewusst NICHT beim Soft-Delete einer Pflanze aufgerufen (Tombstone-
  /// Prinzip: Foto bleibt erhalten, bis der Datensatz wiederhergestellt wird
  /// oder ein manuelles Hard-Cleanup erfolgt). Nur als expliziter
  /// Erweiterungspunkt vorgesehen, aktuell von keiner Route genutzt.
  Future<void> delete(String plantId) async {
    final file = _fileFor(plantId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
