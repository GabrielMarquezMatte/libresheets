import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/models/dynamic_annotation.dart';
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

  testWidgets('viewer changes pages with horizontal swipe gestures', (
    tester,
  ) async {
    final pdfService = await createFakePdfPageSource(3);

    await tester.pumpWidget(
      MaterialApp(home: PdfViewerScreen(pdfService: pdfService)),
    );
    await pumpUntil(tester, () => find.text('1 / 3').evaluate().isNotEmpty);
    final screenCenter = tester.getCenter(find.byType(Scaffold));

    await tester.dragFrom(screenCenter, const Offset(-260, 0));
    await pumpUntil(tester, () => find.text('2 / 3').evaluate().isNotEmpty);

    await tester.dragFrom(screenCenter, const Offset(260, 0));
    await pumpUntil(tester, () => find.text('1 / 3').evaluate().isNotEmpty);
  });

  testWidgets('viewer adds dynamic annotations to the visible page', (
    tester,
  ) async {
    final savedAnnotations = <DynamicAnnotation>[];
    final pdfService = await createFakePdfPageSource(1);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(
          pdfService: pdfService,
          onLoadAnnotations: () async => const [],
          onAddAnnotation: (type, pageNumber, x, y) async {
            final annotation = DynamicAnnotation(
              id: savedAnnotations.length + 1,
              sheetId: 7,
              pageNumber: pageNumber,
              type: type,
              x: x,
              y: y,
              createdAt: DateTime(2026, 4, 27),
            );
            savedAnnotations.add(annotation);
            return annotation;
          },
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('1 / 1').evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('Annotations'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(RawImage)));
    await tester.pump();

    expect(savedAnnotations, hasLength(1));
    expect(savedAnnotations.single.type, DynamicAnnotationType.piano);
    expect(savedAnnotations.single.pageNumber, 1);
    expect(savedAnnotations.single.x, closeTo(0.5, 0.15));
    expect(savedAnnotations.single.y, closeTo(0.5, 0.15));
    expect(find.text('p'), findsWidgets);
  });
}
