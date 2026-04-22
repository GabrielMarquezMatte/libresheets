import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/sheet.dart';
import 'pdf_import_service.dart';

class SheetService {
  static Future<List<Sheet>> getAllSheets(Database db) async {
    final maps = await db.query('sheets', orderBy: 'last_opened DESC');
    return maps.map(Sheet.fromMap).toList();
  }

  static Future<Sheet?> getSheetByPath(Database db, String path) async {
    final maps = await db.query(
      'sheets',
      where: 'path = ?',
      whereArgs: [normalizeStoredPdfPath(path)],
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }
    return Sheet.fromMap(maps.first);
  }

  static Future<Sheet> upsertSheet(Database db, Sheet sheet) async {
    final normalized = sheet.copyWith(path: normalizeStoredPdfPath(sheet.path));
    final existing = await getSheetByPath(db, normalized.path);
    if (existing == null) {
      final id = await db.insert(
        'sheets',
        normalized.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return normalized.copyWith(id: id);
    }
    final updated = existing.copyWith(
      name: normalized.name,
      path: normalized.path,
      lastOpened: normalized.lastOpened,
      composer: normalized.composer ?? existing.composer,
      arranger: normalized.arranger ?? existing.arranger,
      genre: normalized.genre ?? existing.genre,
      period: normalized.period ?? existing.period,
      key: normalized.key ?? existing.key,
      difficulty: normalized.difficulty ?? existing.difficulty,
      notes: normalized.notes ?? existing.notes,
      lastViewedPage: existing.lastViewedPage,
    );
    await db.update(
      'sheets',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return updated;
  }

  static Future<void> updateSheet(Database db, Sheet sheet) {
    return db.update(
      'sheets',
      sheet.toMap(),
      where: 'id = ?',
      whereArgs: [sheet.id],
    );
  }

  static Future<void> saveViewerProgress(
    Database db,
    int sheetId,
    int lastViewedPage,
  ) {
    return db.update(
      'sheets',
      {
        'last_viewed_page': lastViewedPage,
        'last_opened': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sheetId],
    );
  }

  static Future<void> deleteSheet(Database db, int id) {
    return db.delete('sheets', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Sheet>> searchSheets(Database db, String query) async {
    final like = '%$query%';
    final maps = await db.query(
      'sheets',
      where:
          'name LIKE ? OR composer LIKE ? OR arranger LIKE ? '
          'OR genre LIKE ? OR period LIKE ? OR notes LIKE ?',
      whereArgs: [like, like, like, like, like, like],
      orderBy: 'last_opened DESC',
    );
    return maps.map(Sheet.fromMap).toList();
  }
}
