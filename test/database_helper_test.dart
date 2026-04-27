import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/services/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.init();

  late PathProviderPlatform originalPathProvider;
  late Directory testDirectory;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    testDirectory = await createTestDirectory('database_helper');
    PathProviderPlatform.instance = TestPathProviderPlatform(
      testDirectory.path,
    );
    await DatabaseHelper.close();
  });

  tearDown(() async {
    await DatabaseHelper.close();
    PathProviderPlatform.instance = originalPathProvider;
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('migrates v2 databases to add last_viewed_page', () async {
    final dbPath = p.join(testDirectory.path, 'libresheets.db');
    final legacyDb = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sheets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            composer TEXT,
            arranger TEXT,
            genre TEXT,
            period TEXT,
            key TEXT,
            difficulty TEXT,
            notes TEXT,
            last_opened TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.insert('sheets', {
          'name': 'Waltz',
          'path': 'C:/scores/waltz.pdf',
          'last_opened': DateTime(2026, 4, 1).toIso8601String(),
          'created_at': DateTime(2026, 4, 1).toIso8601String(),
        });
      },
    );
    await legacyDb.close();

    final db = await DatabaseHelper.database;
    final rows = await db.query('sheets');

    expect(rows, hasLength(1));
    expect(rows.single['last_viewed_page'], 1);
  });

  test('dedupes canonical paths while preserving metadata', () async {
    final dbPath = p.join(testDirectory.path, 'libresheets.db');
    final legacyDb = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sheets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            composer TEXT,
            arranger TEXT,
            genre TEXT,
            period TEXT,
            key TEXT,
            difficulty TEXT,
            notes TEXT,
            last_opened TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.insert('sheets', {
          'name': 'Fugue Latest',
          'path': 'C:/scores/fugue.pdf',
          'last_opened': DateTime(2026, 4, 2).toIso8601String(),
          'created_at': DateTime(2026, 4, 1).toIso8601String(),
        });
        await db.insert('sheets', {
          'name': 'Fugue Older',
          'path': 'C:/scores/../scores/fugue.pdf',
          'composer': 'Bach',
          'last_opened': DateTime(2026, 4, 1).toIso8601String(),
          'created_at': DateTime(2026, 4, 1).toIso8601String(),
        });
      },
    );
    await legacyDb.close();

    final db = await DatabaseHelper.database;
    final rows = await db.query('sheets');

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Fugue Latest');
    expect(rows.single['path'], p.canonicalize('C:/scores/fugue.pdf'));
    expect(rows.single['composer'], 'Bach');
    expect(rows.single['last_viewed_page'], 1);
  });

  test(
    'migrates legacy managed absolute paths to stable managed keys',
    () async {
      final dbPath = p.join(testDirectory.path, 'libresheets.db');
      const legacyFileName = '0123456789abcdef0123456789abcdef01234567.pdf';
      final legacyDb = await openDatabase(
        dbPath,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE sheets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            composer TEXT,
            arranger TEXT,
            genre TEXT,
            period TEXT,
            key TEXT,
            difficulty TEXT,
            notes TEXT,
            last_viewed_page INTEGER NOT NULL DEFAULT 1,
            last_opened TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
          await db.insert('sheets', {
            'name': 'Fugue',
            'path': 'C:/old/libresheets/sheets/$legacyFileName',
            'last_viewed_page': 3,
            'last_opened': DateTime(2026, 4, 1).toIso8601String(),
            'created_at': DateTime(2026, 4, 1).toIso8601String(),
          });
        },
      );
      await legacyDb.close();

      final db = await DatabaseHelper.database;
      final rows = await db.query('sheets');

      expect(rows, hasLength(1));
      expect(rows.single['path'], 'managed:$legacyFileName');
      expect(rows.single['last_viewed_page'], 3);
    },
  );

  test('dedupes managed paths while preserving metadata', () async {
    final dbPath = p.join(testDirectory.path, 'libresheets.db');
    const legacyFileName = '0123456789abcdef0123456789abcdef01234567.pdf';
    final legacyDb = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sheets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            composer TEXT,
            arranger TEXT,
            genre TEXT,
            period TEXT,
            key TEXT,
            difficulty TEXT,
            notes TEXT,
            last_viewed_page INTEGER NOT NULL DEFAULT 1,
            last_opened TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.insert('sheets', {
          'name': 'Fugue Latest',
          'path': 'managed:$legacyFileName',
          'last_viewed_page': 5,
          'last_opened': DateTime(2026, 4, 2).toIso8601String(),
          'created_at': DateTime(2026, 4, 1).toIso8601String(),
        });
        await db.insert('sheets', {
          'name': 'Fugue Older',
          'path': 'C:/old/libresheets/sheets/$legacyFileName',
          'composer': 'Bach',
          'last_viewed_page': 3,
          'last_opened': DateTime(2026, 4, 1).toIso8601String(),
          'created_at': DateTime(2026, 4, 1).toIso8601String(),
        });
      },
    );
    await legacyDb.close();

    final db = await DatabaseHelper.database;
    final rows = await db.query('sheets');

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Fugue Latest');
    expect(rows.single['path'], 'managed:$legacyFileName');
    expect(rows.single['composer'], 'Bach');
    expect(rows.single['last_viewed_page'], 5);
  });
}
