import 'package:sqlite3/sqlite3.dart';

import '../db/server_database.dart';
import '../dtos/absence_dto.dart';

class AbsenceRepository {
  final ServerDatabase _db;
  AbsenceRepository(this._db);

  /// Last-Write-Wins wie bei Rooms/Plants: überschreibt nur, wenn [absence]
  /// echt neuer ist als der bestehende Stand (bei Gleichstand gewinnt der
  /// Server). Löschungen laufen als Tombstone über deleted_at, nicht als
  /// DELETE – sonst ließe ein länger offline gewesenes Gerät einen entfernten
  /// Zeitraum wieder auferstehen.
  void upsertIfNewer(AbsenceDto absence, DateTime receivedAt) {
    final existing = _db.raw.select('SELECT updated_at FROM absences WHERE id = ?', [absence.id]);
    final incomingMillis = absence.updatedAt.toUtc().millisecondsSinceEpoch;
    final receivedMillis = receivedAt.toUtc().millisecondsSinceEpoch;

    final values = [
      absence.startDate.toUtc().millisecondsSinceEpoch,
      absence.endDate.toUtc().millisecondsSinceEpoch,
      absence.note,
      incomingMillis,
      absence.deletedAt?.toUtc().millisecondsSinceEpoch,
      receivedMillis,
    ];

    if (existing.isEmpty) {
      _db.raw.execute(
        'INSERT INTO absences (start_date, end_date, note, updated_at, deleted_at, '
        'received_at, id) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [...values, absence.id],
      );
      return;
    }

    final existingMillis = existing.first['updated_at'] as int;
    if (incomingMillis > existingMillis) {
      _db.raw.execute(
        'UPDATE absences SET start_date = ?, end_date = ?, note = ?, updated_at = ?, '
        'deleted_at = ?, received_at = ? WHERE id = ?',
        [...values, absence.id],
      );
    }
  }

  /// Änderungen seit dem letzten Sync – gefiltert über den Server-eigenen
  /// Empfangszeitpunkt, nicht über das client-generierte updated_at (siehe
  /// Kommentar in server_database.dart zur Begründung).
  List<AbsenceDto> updatedSince(DateTime lastSyncedAt) {
    final rows = _db.raw.select(
      'SELECT * FROM absences WHERE received_at > ?',
      [lastSyncedAt.toUtc().millisecondsSinceEpoch],
    );
    return rows.map(_rowToDto).toList();
  }

  AbsenceDto _rowToDto(Row row) {
    return AbsenceDto(
      id: row['id'] as String,
      startDate: DateTime.fromMillisecondsSinceEpoch(row['start_date'] as int, isUtc: true),
      endDate: DateTime.fromMillisecondsSinceEpoch(row['end_date'] as int, isUtc: true),
      note: row['note'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int, isUtc: true),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int, isUtc: true),
    );
  }
}
