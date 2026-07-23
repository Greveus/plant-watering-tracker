import 'package:sqlite3/sqlite3.dart';

import '../db/server_database.dart';
import '../dtos/room_dto.dart';

class RoomRepository {
  final ServerDatabase _db;
  RoomRepository(this._db);

  /// Überschreibt den Datensatz nur, wenn [room] neuer ist als der
  /// bestehende Stand (striktes Größer — bei Gleichstand gewinnt der
  /// Server). [receivedAt] wird nur gesetzt, wenn der Datensatz tatsächlich
  /// neu geschrieben wird (neu oder Update) – nicht bei abgelehnten Pushes.
  void upsertIfNewer(RoomDto room, DateTime receivedAt) {
    final existing = _db.raw.select('SELECT updated_at FROM rooms WHERE id = ?', [room.id]);
    final incomingMillis = room.updatedAt.toUtc().millisecondsSinceEpoch;
    final receivedMillis = receivedAt.toUtc().millisecondsSinceEpoch;

    if (existing.isEmpty) {
      _db.raw.execute(
        'INSERT INTO rooms (id, name, updated_at, deleted_at, received_at) VALUES (?, ?, ?, ?, ?)',
        [
          room.id,
          room.name,
          incomingMillis,
          room.deletedAt?.toUtc().millisecondsSinceEpoch,
          receivedMillis,
        ],
      );
      return;
    }

    final existingMillis = existing.first['updated_at'] as int;
    if (incomingMillis > existingMillis) {
      _db.raw.execute(
        'UPDATE rooms SET name = ?, updated_at = ?, deleted_at = ?, received_at = ? WHERE id = ?',
        [
          room.name,
          incomingMillis,
          room.deletedAt?.toUtc().millisecondsSinceEpoch,
          receivedMillis,
          room.id,
        ],
      );
    }
  }

  /// Änderungen seit dem letzten Sync – gefiltert über den Server-eigenen
  /// Empfangszeitpunkt, nicht über das client-generierte updated_at (siehe
  /// Kommentar in server_database.dart zur Begründung).
  List<RoomDto> updatedSince(DateTime lastSyncedAt) {
    final rows = _db.raw.select(
      'SELECT * FROM rooms WHERE received_at > ?',
      [lastSyncedAt.toUtc().millisecondsSinceEpoch],
    );
    return rows.map(_rowToDto).toList();
  }

  RoomDto _rowToDto(Row row) {
    return RoomDto(
      id: row['id'] as String,
      name: row['name'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int, isUtc: true),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int, isUtc: true),
    );
  }
}
