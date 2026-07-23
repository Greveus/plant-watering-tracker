import 'package:sqlite3/sqlite3.dart';

import '../db/server_database.dart';
import '../dtos/watering_event_dto.dart';

class WateringEventRepository {
  final ServerDatabase _db;
  WateringEventRepository(this._db);

  /// Rein additiv: die UUID ist der Dedup-Schlüssel. Bereits bekannte Events
  /// werden per INSERT OR IGNORE übersprungen, nie überschrieben.
  /// `received_at` wird ausschließlich beim ERSTEN Empfang gesetzt.
  void insertIfAbsent(WateringEventDto event, DateTime receivedAt) {
    _db.raw.execute(
      '''
      INSERT OR IGNORE INTO watering_events (
        id, plant_id, timestamp, feedback_tag, note, received_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        event.id,
        event.plantId,
        event.timestamp.toUtc().millisecondsSinceEpoch,
        event.feedbackTag,
        event.note,
        receivedAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  List<WateringEventDto> receivedSince(DateTime lastSyncedAt) {
    final rows = _db.raw.select(
      'SELECT * FROM watering_events WHERE received_at > ?',
      [lastSyncedAt.toUtc().millisecondsSinceEpoch],
    );
    return rows.map(_rowToDto).toList();
  }

  WateringEventDto _rowToDto(Row row) {
    return WateringEventDto(
      id: row['id'] as String,
      plantId: row['plant_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int, isUtc: true),
      feedbackTag: row['feedback_tag'] as String?,
      note: row['note'] as String?,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(row['received_at'] as int, isUtc: true),
    );
  }
}
