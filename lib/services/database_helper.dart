import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pdf_import_service.dart';

class DatabaseHelper {
  static Database? _database;
  static const _schemaVersion = 5;

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
        last_viewed_page INTEGER NOT NULL DEFAULT 1,
        last_opened TEXT NOT NULL,
        created_at  TEXT NOT NULL
      )
    ''');
    await _createDynamicAnnotationsTable(db);
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
    3: _migrateToV3,
    4: _migrateToV4,
    5: _migrateToV5,
  };

  static Future<void> _migrateToV2(Database db) async {
    await _normalizeSheetPaths(db, p.canonicalize);
  }

  static Future<void> _migrateToV3(Database db) {
    return db.execute(
      'ALTER TABLE sheets ADD COLUMN last_viewed_page INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> _migrateToV4(Database db) async {
    await _normalizeSheetPaths(db, normalizeStoredPdfPath);
  }

  static Future<void> _migrateToV5(Database db) async {
    await _createDynamicAnnotationsTable(db);
  }

  static Future<void> _createDynamicAnnotationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE dynamic_annotations (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_id    INTEGER NOT NULL,
        page_number INTEGER NOT NULL,
        type        TEXT    NOT NULL,
        x           REAL    NOT NULL,
        y           REAL    NOT NULL,
        created_at  TEXT    NOT NULL,
        FOREIGN KEY(sheet_id) REFERENCES sheets(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX dynamic_annotations_sheet_page_idx '
      'ON dynamic_annotations(sheet_id, page_number)',
    );
  }

  static Future<void> _normalizeSheetPaths(
    Database db,
    String Function(String path) normalizePath,
  ) async {
    final rows = await db.query('sheets', orderBy: 'last_opened DESC');
    final normalizedRows = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final normalizedPath = normalizePath(row['path'] as String);
      final winner = normalizedRows[normalizedPath];
      if (winner == null) {
        normalizedRows[normalizedPath] = {...row, 'path': normalizedPath};
        continue;
      }
      normalizedRows[normalizedPath] = _mergeSheetRows(winner, row);
    }
    await db.transaction((txn) async {
      await txn.delete('sheets');
      for (final row in normalizedRows.values) {
        await txn.insert('sheets', row);
      }
    });
  }

  static Map<String, Object?> _mergeSheetRows(
    Map<String, Object?> winner,
    Map<String, Object?> row,
  ) => {
    ...winner,
    for (final column in _mergedMetadataColumns)
      column: winner[column] ?? row[column],
  };

  static const _mergedMetadataColumns = [
    'composer',
    'arranger',
    'genre',
    'period',
    'key',
    'difficulty',
    'notes',
  ];

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
