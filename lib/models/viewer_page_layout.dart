final class VisiblePages {
  final int leadingPage;
  final int? trailingPage;

  const VisiblePages(this.leadingPage, [this.trailingPage]);
}

int clampViewerPage(int page, int pageCount) {
  if (pageCount < 1) {
    return 1;
  }
  if (page < 1) {
    return 1;
  }
  if (page > pageCount) {
    return pageCount;
  }
  return page;
}

List<int> buildViewerAnchors(int pageCount, bool isLandscape) {
  if (pageCount < 1) {
    return const [];
  }
  if (!isLandscape) {
    return List<int>.generate(pageCount, (index) => index + 1);
  }
  final anchors = <int>[1];
  for (int page = 2; page <= pageCount; page += 2) {
    anchors.add(page);
  }
  return anchors;
}

int normalizeViewerPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  final clampedPage = clampViewerPage(page, pageCount);
  if (!isLandscape || clampedPage == 1) {
    return clampedPage;
  }
  return clampedPage.isOdd ? clampedPage - 1 : clampedPage;
}

VisiblePages buildVisiblePages({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  if (!isLandscape || normalizedPage == 1) {
    return VisiblePages(normalizedPage);
  }
  final trailingPage = normalizedPage < pageCount ? normalizedPage + 1 : null;
  return VisiblePages(normalizedPage, trailingPage);
}

int nextViewerPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  final anchors = buildViewerAnchors(pageCount, isLandscape);
  if (anchors.isEmpty) {
    return 1;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  final currentIndex = anchors.indexOf(normalizedPage);
  if (currentIndex == -1 || currentIndex >= anchors.length - 1) {
    return normalizedPage;
  }
  return anchors[currentIndex + 1];
}

int previousViewerPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  final anchors = buildViewerAnchors(pageCount, isLandscape);
  if (anchors.isEmpty) {
    return 1;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  final currentIndex = anchors.indexOf(normalizedPage);
  if (currentIndex <= 0) {
    return anchors.first;
  }
  return anchors[currentIndex - 1];
}

int sliderIndexForPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  final anchors = buildViewerAnchors(pageCount, isLandscape);
  if (anchors.isEmpty) {
    return 0;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  final index = anchors.indexOf(normalizedPage);
  if (index < 0) {
    return 0;
  }
  if (index >= anchors.length) {
    return anchors.length - 1;
  }
  return index;
}

int pageForSliderIndex({
  required int index,
  required int pageCount,
  required bool isLandscape,
}) {
  final anchors = buildViewerAnchors(pageCount, isLandscape);
  if (anchors.isEmpty) {
    return 1;
  }
  if (index < 0) {
    return anchors.first;
  }
  if (index >= anchors.length) {
    return anchors.last;
  }
  return anchors[index];
}

String formatVisiblePageLabel(VisiblePages visiblePages, int pageCount) {
  if (visiblePages.trailingPage == null) {
    return '${visiblePages.leadingPage} / $pageCount';
  }
  return '${visiblePages.leadingPage}-${visiblePages.trailingPage} / $pageCount';
}
