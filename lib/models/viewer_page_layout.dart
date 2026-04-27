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
  if (pageCount < 1) {
    return 1;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  if (!isLandscape) {
    return clampViewerPage(normalizedPage + 1, pageCount);
  }
  if (normalizedPage == 1) {
    return pageCount > 1 ? 2 : 1;
  }
  final nextPage = normalizedPage + 2;
  return nextPage <= pageCount ? nextPage : normalizedPage;
}

int previousViewerPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  if (pageCount < 1) {
    return 1;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  if (!isLandscape) {
    return clampViewerPage(normalizedPage - 1, pageCount);
  }
  return normalizedPage <= 2 ? 1 : normalizedPage - 2;
}

int sliderIndexForPage({
  required int page,
  required int pageCount,
  required bool isLandscape,
}) {
  if (pageCount < 1) {
    return 0;
  }
  final normalizedPage = normalizeViewerPage(
    page: page,
    pageCount: pageCount,
    isLandscape: isLandscape,
  );
  if (!isLandscape) {
    return normalizedPage - 1;
  }
  return normalizedPage == 1 ? 0 : normalizedPage ~/ 2;
}

int pageForSliderIndex({
  required int index,
  required int pageCount,
  required bool isLandscape,
}) {
  if (pageCount < 1) {
    return 1;
  }
  if (!isLandscape) {
    return clampViewerPage(index + 1, pageCount);
  }
  if (index < 0) {
    return 1;
  }
  final page = index == 0 ? 1 : index * 2;
  if (page <= pageCount) {
    return page;
  }
  return _lastLandscapeAnchor(pageCount);
}

String formatVisiblePageLabel(VisiblePages visiblePages, int pageCount) {
  if (visiblePages.trailingPage == null) {
    return '${visiblePages.leadingPage} / $pageCount';
  }
  return '${visiblePages.leadingPage}-${visiblePages.trailingPage} / $pageCount';
}

int _lastLandscapeAnchor(int pageCount) {
  if (pageCount <= 1) {
    return 1;
  }
  return pageCount.isEven ? pageCount : pageCount - 1;
}
