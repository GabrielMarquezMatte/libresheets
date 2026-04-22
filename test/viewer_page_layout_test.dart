import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/models/viewer_page_layout.dart';

void main() {
  test('builds cover-solo landscape anchors', () {
    expect(buildViewerAnchors(1, true), [1]);
    expect(buildViewerAnchors(5, true), [1, 2, 4]);
    expect(buildViewerAnchors(6, true), [1, 2, 4, 6]);
  });

  test('normalizes portrait pages into landscape anchors', () {
    expect(normalizeViewerPage(page: 3, pageCount: 5, isLandscape: true), 2);
    expect(normalizeViewerPage(page: 5, pageCount: 5, isLandscape: true), 4);
    expect(normalizeViewerPage(page: 3, pageCount: 5, isLandscape: false), 3);
  });

  test('navigates through landscape spreads and portrait pages', () {
    expect(nextViewerPage(page: 1, pageCount: 5, isLandscape: true), 2);
    expect(nextViewerPage(page: 2, pageCount: 5, isLandscape: true), 4);
    expect(previousViewerPage(page: 4, pageCount: 5, isLandscape: true), 2);
    expect(previousViewerPage(page: 2, pageCount: 5, isLandscape: true), 1);
    expect(nextViewerPage(page: 3, pageCount: 5, isLandscape: false), 4);
  });

  test('builds visible spreads and labels', () {
    final cover = buildVisiblePages(page: 1, pageCount: 5, isLandscape: true);
    final spread = buildVisiblePages(page: 3, pageCount: 5, isLandscape: true);
    final tail = buildVisiblePages(page: 6, pageCount: 6, isLandscape: true);

    expect(cover.leadingPage, 1);
    expect(cover.trailingPage, isNull);
    expect(formatVisiblePageLabel(cover, 5), '1 / 5');

    expect(spread.leadingPage, 2);
    expect(spread.trailingPage, 3);
    expect(formatVisiblePageLabel(spread, 5), '2-3 / 5');

    expect(tail.leadingPage, 6);
    expect(tail.trailingPage, isNull);
    expect(formatVisiblePageLabel(tail, 6), '6 / 6');
  });

  test('maps slider indexes to spread anchors', () {
    expect(sliderIndexForPage(page: 4, pageCount: 6, isLandscape: true), 2);
    expect(pageForSliderIndex(index: 2, pageCount: 6, isLandscape: true), 4);
    expect(pageForSliderIndex(index: 99, pageCount: 6, isLandscape: true), 6);
  });
}
