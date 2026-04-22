import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/services/pdf_import_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPathProvider;
  late Directory testDirectory;
  late Directory docsDirectory;
  late Directory supportDirectory;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    testDirectory = await createTestDirectory('pdf_import_service');
    docsDirectory = Directory(p.join(testDirectory.path, 'docs'));
    supportDirectory = Directory(p.join(testDirectory.path, 'support'));
    await docsDirectory.create(recursive: true);
    await supportDirectory.create(recursive: true);
    PathProviderPlatform.instance = TestPathProviderPlatform(
      testDirectory.path,
      applicationDocumentsPath: docsDirectory.path,
      applicationSupportPath: supportDirectory.path,
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('importPdf stores managed keys instead of absolute paths', () async {
    final sourceFile = File(p.join(testDirectory.path, 'source.pdf'));
    await sourceFile.writeAsBytes(const [1, 2, 3, 4]);

    final storedPath = await importPdf(sourceFile.path);
    final resolvedPath = await resolvePdfPath(storedPath);

    expect(storedPath, startsWith('managed:'));
    expect(await File(resolvedPath).exists(), isTrue);
    expect(p.isWithin(supportDirectory.path, resolvedPath), isTrue);
  });

  test(
    'resolvePdfPath migrates legacy documents storage into support storage',
    () async {
      const fileName = '0123456789abcdef0123456789abcdef01234567.pdf';
      final legacyDir = Directory(p.join(docsDirectory.path, 'sheets'));
      await legacyDir.create(recursive: true);
      final legacyFile = File(p.join(legacyDir.path, fileName));
      await legacyFile.writeAsBytes(const [5, 6, 7, 8]);

      final resolvedPath = await resolvePdfPath('managed:$fileName');

      expect(p.isWithin(supportDirectory.path, resolvedPath), isTrue);
      expect(await File(resolvedPath).exists(), isTrue);
      expect(await legacyFile.exists(), isTrue);
    },
  );
}
