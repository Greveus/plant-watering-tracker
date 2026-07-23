import 'package:sqlite3/sqlite3.dart';

class ServerDatabase {
  final Database _db;

  ServerDatabase._(this._db);

  factory ServerDatabase.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = OFF;');
    _createSchema(db);
    return ServerDatabase._(db);
  }

  static void _createSchema(Database db) {
    // received_at (Server-Empfangszeitpunkt) ist auf jeder Tabelle die
    // Referenz für den Delta-Sync-Filter, NICHT das client-generierte
    // updated_at/timestamp: bei Uhrzeit-Drift zwischen zwei Client-Geräten
    // und dem Server würde ein Filter über den client-generierten Zeitstempel
    // sonst eine tatsächlich neuere Änderung fälschlich überspringen, weil
    // client- und server-seitige Uhren nicht im selben Referenzrahmen
    // liegen. Das Last-Write-Wins zwischen zwei Versionen desselben
    // Datensatzes vergleicht weiterhin updated_at (das ist korrekt so, da
    // beide Versionen von Clients stammen und Client-Zeit dort einheitlich
    // als Vergleichsbasis dient) – nur der "was ist neu seit dem letzten
    // Sync"-Filter läuft über die Server-Uhr.
    db.execute('''
      CREATE TABLE IF NOT EXISTS rooms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        received_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS plants (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        preset_id TEXT,
        species_free_text TEXT,
        room_id TEXT NOT NULL,
        photo_path TEXT,
        created_at INTEGER NOT NULL,
        size_category TEXT NOT NULL,
        manual_interval_days INTEGER,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        received_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS watering_events (
        id TEXT PRIMARY KEY,
        plant_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        feedback_tag TEXT,
        note TEXT,
        received_at INTEGER NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_plants_received_at ON plants(received_at);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_rooms_received_at ON rooms(received_at);');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_events_received_at ON watering_events(received_at);',
    );
  }

  Database get raw => _db;

  T transaction<T>(T Function() action) {
    _db.execute('BEGIN;');
    try {
      final result = action();
      _db.execute('COMMIT;');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void close() => _db.close();
}
