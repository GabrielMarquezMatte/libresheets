import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/models/dynamic_annotation.dart';
import 'package:libresheets/models/sheet.dart';
import 'package:libresheets/services/database_helper.dart';
import 'package:libresheets/services/sheet_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.init();

  late PathProviderPlatform originalPathProvider;
  late Directory testDirectory;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    testDirectory = await createTestDirectory('sheet_service');
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

  test('sheet round-trips last viewed page', () {
    final now = DateTime(2026, 4, 21, 12);
    final sheet = Sheet(
      id: 7,
      name: 'Etude',
      path: 'C:/scores/etude.pdf',
      composer: 'Chopin',
      lastViewedPage: 4,
      lastOpened: now,
      createdAt: now,
    );

    final roundTrip = Sheet.fromMap(sheet.toMap());

    expect(roundTrip.id, 7);
    expect(roundTrip.lastViewedPage, 4);
    expect(roundTrip.path, 'C:/scores/etude.pdf');
  });

  test('upsert preserves last viewed page on re-import', () async {
    final db = await DatabaseHelper.database;
    final original = await SheetService.upsertSheet(
      db,
      Sheet(
        name: 'Prelude',
        path: 'C:/scores/prelude.pdf',
        composer: 'Bach',
        lastViewedPage: 6,
        lastOpened: DateTime(2026, 4, 20),
        createdAt: DateTime(2026, 4, 20),
      ),
    );

    final reimported = await SheetService.upsertSheet(
      db,
      Sheet(
        name: 'Prelude in C',
        path: 'C:/scores/prelude.pdf',
        lastOpened: DateTime(2026, 4, 21),
        createdAt: original.createdAt,
      ),
    );

    expect(reimported.name, 'Prelude in C');
    expect(reimported.composer, 'Bach');
    expect(reimported.lastViewedPage, 6);
  });

  test('saveViewerProgress updates page and timestamp', () async {
    final db = await DatabaseHelper.database;
    final sheet = await SheetService.upsertSheet(
      db,
      Sheet(
        name: 'Sonata',
        path: 'C:/scores/sonata.pdf',
        lastOpened: DateTime(2026, 4, 1),
        createdAt: DateTime(2026, 4, 1),
      ),
    );

    await SheetService.saveViewerProgress(db, sheet.id!, 9);
    final saved = await SheetService.getSheetByPath(db, 'C:/scores/sonata.pdf');

    expect(saved, isNotNull);
    expect(saved!.lastViewedPage, 9);
    expect(saved.lastOpened.isAfter(DateTime(2026, 4, 1)), isTrue);
  });

  test('dynamic annotations round-trip and delete with sheet', () async {
    final db = await DatabaseHelper.database;
    final sheet = await SheetService.upsertSheet(
      db,
      Sheet(
        name: 'Nocturne',
        path: 'C:/scores/nocturne.pdf',
        lastOpened: DateTime(2026, 4, 1),
        createdAt: DateTime(2026, 4, 1),
      ),
    );

    final annotation = await SheetService.addDynamicAnnotation(
      db,
      DynamicAnnotation(
        sheetId: sheet.id!,
        pageNumber: 2,
        type: DynamicAnnotationType.mezzoPiano,
        x: 0.25,
        y: 0.75,
        createdAt: DateTime(2026, 4, 21),
      ),
    );

    final annotations = await SheetService.getDynamicAnnotations(db, sheet.id!);

    expect(annotation.id, isNotNull);
    expect(annotations, hasLength(1));
    expect(annotations.single.type, DynamicAnnotationType.mezzoPiano);
    expect(annotations.single.pageNumber, 2);
    expect(annotations.single.x, 0.25);
    expect(annotations.single.y, 0.75);

    await SheetService.deleteSheet(db, sheet.id!);

    expect(await SheetService.getDynamicAnnotations(db, sheet.id!), isEmpty);
  });
}
