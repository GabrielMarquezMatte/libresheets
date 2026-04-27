import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:libresheets/models/page_request.dart';
import 'package:pdfx/pdfx.dart';

abstract interface class PdfPageSource implements Listenable {
  int get pageCount;

  ui.Image? getPage(int pageNumber);

  void requestPages(int currentPage);

  Future<void> close();
}

const _cacheAhead = 10;
const _cacheBehind = 5;
const _fullQualityRange = 1;
const _previewScaleFactor = 0.5;

final class PdfService extends ChangeNotifier implements PdfPageSource {
  final PdfDocument _document;
  final Map<int, _CachedPage> _pageCache = {};
  late final StreamController<PageRequest> _renderChannel;
  final double _renderScale = _computeRenderScale();
  int _renderGeneration = 0;
  Future<void>? _closeFuture;

  PdfService(this._document) {
    _renderChannel = StreamController<PageRequest>();
    _startRenderConsumer();
  }

  static double _computeRenderScale() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenPixelWidth = view.physicalSize.width;
    if (screenPixelWidth <= 0) {
      return 1.5;
    }
    final renderScale = (screenPixelWidth * 1.2) / 595;
    return renderScale.clamp(1.0, 2.0);
  }

  Future<void> _renderPage(PageRequest pageRequest, int pageNumber) async {
    final isFullQuality = _isFullQualityPage(
      pageRequest.currentPage,
      pageNumber,
    );
    final scale = isFullQuality
        ? _renderScale
        : _renderScale * _previewScaleFactor;

    final page = await _document.getPage(pageNumber);
    if (_isStale(pageRequest)) {
      await page.close();
      return;
    }
    final pageImage = await page.render(
      width: page.width * scale,
      height: page.height * scale,
      format: PdfPageImageFormat.jpeg,
      quality: 80,
      backgroundColor: '#FFFFFF',
    );
    await page.close();
    if (_isStale(pageRequest) || pageImage == null) {
      return;
    }
    final codec = await ui.instantiateImageCodec(pageImage.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (_isStale(pageRequest)) {
      frame.image.dispose();
      return;
    }
    _pageCache[pageNumber]?.dispose();
    _pageCache[pageNumber] = _CachedPage(
      frame.image,
      isPreview: !isFullQuality,
    );
    notifyListeners();
  }

  bool _isStale(PageRequest pageRequest) =>
      pageRequest.generation != _renderGeneration || _closeFuture != null;

  bool _needsRender(int currentPage, int pageNumber) {
    if (!_isInRenderWindow(currentPage, pageNumber)) {
      return false;
    }
    final cachedPage = _pageCache[pageNumber];
    if (cachedPage == null) {
      return true;
    }
    return cachedPage.isPreview && _isFullQualityPage(currentPage, pageNumber);
  }

  void _startRenderConsumer() {
    _renderChannel.stream.listen((pageRequest) async {
      final gen = _renderGeneration;
      for (final page in pageRequest.pagesToRender) {
        if (gen != _renderGeneration || _closeFuture != null) {
          return;
        }
        if (!_needsRender(pageRequest.currentPage, page)) {
          continue;
        }
        await _renderPage(pageRequest, page);
      }
    });
  }

  @override
  void requestPages(int currentPage) {
    if (_closeFuture != null) {
      return;
    }
    _renderGeneration++;
    final needed = _renderWindowPages(currentPage, _document.pagesCount);
    final toEvict = _pageCache.keys
        .where((page) => !needed.contains(page))
        .toList();
    for (final page in toEvict) {
      _pageCache.remove(page)?.dispose();
    }
    final missing = <int>[];
    for (final page in needed) {
      if (_needsRender(currentPage, page)) {
        missing.add(page);
      }
    }
    if (missing.isEmpty) {
      return;
    }
    missing.sort(
      (a, b) =>
          (a - currentPage).abs().compareTo((b - currentPage).abs()),
    );
    _renderChannel.add(PageRequest(currentPage, _renderGeneration, missing));
  }

  @override
  ui.Image? getPage(int pageNumber) => _pageCache[pageNumber]?.image;

  @override
  Future<void> close() {
    final closeFuture = _closeFuture;
    if (closeFuture != null) {
      return closeFuture;
    }
    _renderGeneration++;
    for (final cachedPage in _pageCache.values) {
      cachedPage.dispose();
    }
    _pageCache.clear();
    _closeFuture = Future.wait([_renderChannel.close(), _document.close()]);
    return _closeFuture!;
  }

  @override
  int get pageCount => _document.pagesCount;

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

List<int> _renderWindowPages(int currentPage, int pageCount) {
  final pages = <int>[];
  for (int offset = -_cacheBehind; offset <= _cacheAhead; offset++) {
    final page = currentPage + offset;
    if (page >= 1 && page <= pageCount) {
      pages.add(page);
    }
  }
  return pages;
}

bool _isInRenderWindow(int currentPage, int pageNumber) =>
    pageNumber >= currentPage - _cacheBehind &&
    pageNumber <= currentPage + _cacheAhead;

bool _isFullQualityPage(int currentPage, int pageNumber) =>
    (pageNumber - currentPage).abs() <= _fullQualityRange;

final class _CachedPage {
  final ui.Image image;
  final bool isPreview;

  _CachedPage(this.image, {required this.isPreview});

  void dispose() {
    image.dispose();
  }
}
