import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/screens/pdf_viewer_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'test_support/fakes.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic originalWakelockPlatform;

  setUp(() {
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = TestWakelockPlatform();
  });

  tearDown(() {
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });

  testWidgets('viewer resumes spread pages and handles HID navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPages = <int>[];
    final pdfService = await createFakePdfPageSource(5);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(
          pdfService: pdfService,
          initialPage: 3,
          onSaveProgress: (page) async {
            savedPages.add(page);
          },
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('2-3 / 5').evaluate().isNotEmpty);
    await pumpUntil(tester, () => find.byType(RawImage).evaluate().length == 2);

    expect(find.text('2-3 / 5'), findsOneWidget);
    expect(find.byType(RawImage), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pumpUntil(tester, () => find.text('4-5 / 5').evaluate().isNotEmpty);

    expect(find.text('4-5 / 5'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(savedPages, contains(4));
  });

  testWidgets('viewer saves progress through PopScope back handling', (
    tester,
  ) async {
    final savedPages = <int>[];
    final pdfService = await createFakePdfPageSource(2);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(
          pdfService: pdfService,
          initialPage: 2,
          onSaveProgress: (page) async {
            savedPages.add(page);
          },
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('2 / 2').evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(savedPages, contains(2));
  });
}
