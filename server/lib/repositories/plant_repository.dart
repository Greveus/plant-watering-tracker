import 'package:sqlite3/sqlite3.dart';

import '../db/server_database.dart';
import '../dtos/plant_dto.dart';

class PlantRepository {
  final ServerDatabase _db;
  PlantRepository(this._db);

  /// Überschreibt den Datensatz nur, wenn [plant] neuer ist als der
  /// bestehende Stand (striktes Größer — bei Gleichstand gewinnt der
  /// Server). [receivedAt] wird nur gesetzt, wenn der Datensatz tatsächlich
  /// neu geschrieben wird (neu oder Update) – nicht bei abgelehnten Pushes.
  void upsertIfNewer(PlantDto plant, DateTime receivedAt) {
    final existing = _db.raw.select('SELECT updated_at FROM plants WHERE id = ?', [plant.id]);
    final incomingMillis = plant.updatedAt.toUtc().millisecondsSinceEpoch;
    final receivedMillis = receivedAt.toUtc().millisecondsSinceEpoch;

    if (existing.isEmpty) {
      _db.raw.execute(
        '''
        INSERT INTO plants (
          id, nickname, preset_id, species_free_text, room_id, photo_path,
          photo_version, created_at, size_category, manual_interval_days,
          updated_at, deleted_at, received_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          plant.id,
          plant.nickname,
          plant.presetId,
          plant.speciesFreeText,
          plant.roomId,
          plant.photoPath,
          plant.photoVersion,
          plant.createdAt.toUtc().millisecondsSinceEpoch,
          plant.sizeCategory,
          plant.manualIntervalDays,
          incomingMillis,
          plant.deletedAt?.toUtc().millisecondsSinceEpoch,
          receivedMillis,
        ],
      );
      return;
    }

    final existingMillis = existing.first['updated_at'] as int;
    if (incomingMillis > existingMillis) {
      _db.raw.execute(
        '''
        UPDATE plants SET
          nickname = ?, preset_id = ?, species_free_text = ?, room_id = ?,
          photo_path = ?, photo_version = ?, size_category = ?, manual_interval_days = ?,
          updated_at = ?, deleted_at = ?, received_at = ?
        WHERE id = ?
        ''',
        [
          plant.nickname,
          plant.presetId,
          plant.speciesFreeText,
          plant.roomId,
          plant.photoPath,
          plant.photoVersion,
          plant.sizeCategory,
          plant.manualIntervalDays,
          incomingMillis,
          plant.deletedAt?.toUtc().millisecondsSinceEpoch,
          receivedMillis,
          plant.id,
        ],
      );
    }
  }

  /// Änderungen seit dem letzten Sync – gefiltert über den Server-eigenen
  /// Empfangszeitpunkt, nicht über das client-generierte updated_at (siehe
  /// Kommentar in server_database.dart zur Begründung).
  List<PlantDto> updatedSince(DateTime lastSyncedAt) {
    final rows = _db.raw.select(
      'SELECT * FROM plants WHERE received_at > ?',
      [lastSyncedAt.toUtc().millisecondsSinceEpoch],
    );
    return rows.map(_rowToDto).toList();
  }

  PlantDto _rowToDto(Row row) {
    return PlantDto(
      id: row['id'] as String,
      nickname: row['nickname'] as String,
      presetId: row['preset_id'] as String?,
      speciesFreeText: row['species_free_text'] as String?,
      roomId: row['room_id'] as String,
      photoPath: row['photo_path'] as String?,
      photoVersion: row['photo_version'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int, isUtc: true),
      sizeCategory: row['size_category'] as String,
      manualIntervalDays: row['manual_interval_days'] as int?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int, isUtc: true),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int, isUtc: true),
    );
  }
}
