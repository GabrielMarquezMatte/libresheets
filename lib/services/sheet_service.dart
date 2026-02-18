import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/sheet.dart';

class SheetService {
  static Future<List<Sheet>> getAllSheets(Database db) async {
    final maps = await db.query(
      'sheets',
      orderBy: 'last_opened DESC',
    );
    return maps.map(Sheet.fromMap).toList();
  }

  static Future<Sheet?> getSheetByPath(Database db, String path) async {
    final maps = await db.query(
      'sheets',
      where: 'path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Sheet.fromMap(maps.first);
  }

  static Future<Sheet> upsertSheet(Database db, Sheet sheet) async {
    final existing = await getSheetByPath(db, sheet.path);
    if (existing == null) {
      final id = await db.insert(
        'sheets',
        sheet.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return sheet.copyWith(id: id);
    }
    // Update last_opened and keep existing metadata
    final updated = existing.copyWith(
      name: sheet.name,
      lastOpened: sheet.lastOpened,
      // Only overwrite metadata if the new sheet has it set
      composer: sheet.composer ?? existing.composer,
      arranger: sheet.arranger ?? existing.arranger,
      genre: sheet.genre ?? existing.genre,
      period: sheet.period ?? existing.period,
      key: sheet.key ?? existing.key,
      difficulty: sheet.difficulty ?? existing.difficulty,
      notes: sheet.notes ?? existing.notes,
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

  static Future<void> deleteSheet(Database db, int id) {
    return db.delete('sheets', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Sheet>> searchSheets(Database db, String query) async {
    final like = '%$query%';
    final maps = await db.query(
      'sheets',
      where: 'name LIKE ? OR composer LIKE ? OR arranger LIKE ? '
          'OR genre LIKE ? OR period LIKE ? OR notes LIKE ?',
      whereArgs: [like, like, like, like, like, like],
      orderBy: 'last_opened DESC',
    );
    return maps.map(Sheet.fromMap).toList();
  }
}
