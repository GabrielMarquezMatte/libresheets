import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static Database? _database;
  static const _schemaVersion = 2;

  static void init() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _open();
    return _database!;
  }

  static Future<Database> _open() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'libresheets.db');

    await Directory(dir.path).create(recursive: true);

    return await openDatabase(
      dbPath,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sheets (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        path       TEXT    NOT NULL UNIQUE,
        composer   TEXT,
        arranger   TEXT,
        genre      TEXT,
        period     TEXT,
        key        TEXT,
        difficulty TEXT,
        notes      TEXT,
        last_opened TEXT NOT NULL,
        created_at  TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        throw StateError('No migration defined for schema version $v');
      }
      await migration(db);
    }
  }

  static final Map<int, Future<void> Function(Database)> _migrations = {
    2: _migrateToV2,
  };

  static Future<void> _migrateToV2(Database db) async {
    final rows = await db.query('sheets', orderBy: 'last_opened DESC');
    final merged = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final canonical = p.canonicalize(row['path'] as String);
      final winner = merged[canonical];
      if (winner == null) {
        merged[canonical] = {...row, 'path': canonical};
        continue;
      }
      merged[canonical] = {
        ...winner,
        'composer': winner['composer'] ?? row['composer'],
        'arranger': winner['arranger'] ?? row['arranger'],
        'genre': winner['genre'] ?? row['genre'],
        'period': winner['period'] ?? row['period'],
        'key': winner['key'] ?? row['key'],
        'difficulty': winner['difficulty'] ?? row['difficulty'],
        'notes': winner['notes'] ?? row['notes'],
      };
    }
    await db.transaction((txn) async {
      await txn.delete('sheets');
      for (final row in merged.values) {
        await txn.insert('sheets', row);
      }
    });
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
