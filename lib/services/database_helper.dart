import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static Database? _database;

  static void init() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _open();
    return _database!;
  }

  static Future<Database> _open() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'libresheets.db');

    await Directory(dir.path).create(recursive: true);

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
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

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
