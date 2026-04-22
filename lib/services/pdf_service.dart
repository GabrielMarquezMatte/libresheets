import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:libresheets/models/page_request.dart';
import 'package:pdfx/pdfx.dart';

final class PdfService extends ChangeNotifier {
  final PdfDocument _document;
  final Map<int, ui.Image> _pageCache = {};
  final Set<int> _lowQualityPages = {};
  late final StreamController<PageRequest> _renderChannel;
  static const _cacheAhead = 10;
  static const _cacheBehind = 5;

  /// Pages within this range of the current page render at full resolution.
  static const _fullQualityRange = 1;

  /// Far pages render at this fraction of full scale for faster pre-caching.
  static const _previewScaleFactor = 0.5;
  final double _renderScale = _computeRenderScale();
  int _renderGeneration = 0;
  PdfService(this._document) {
    _renderChannel = StreamController<PageRequest>();
    _startRenderConsumer();
  }
  static double _computeRenderScale() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenPixelWidth = view.physicalSize.width;
    if (screenPixelWidth <= 0) return 1.5;
    final renderScale = (screenPixelWidth * 1.2) / 595;
    return renderScale.clamp(1.0, 2.0);
  }

  bool _isInWindow(PageRequest pageRequest, int pageNumber) =>
      pageNumber >= pageRequest.currentPage - _cacheBehind &&
      pageNumber <= pageRequest.currentPage + _cacheAhead;
  Future<void> _renderPage(PageRequest pageRequest, int pageNumber) async {
    final isClose =
        (pageNumber - pageRequest.currentPage).abs() <= _fullQualityRange;
    final scale = isClose ? _renderScale : _renderScale * _previewScaleFactor;

    final page = await _document.getPage(pageNumber);
    if (pageRequest.generation != _renderGeneration) {
      await page.close();
      return;
    }
    final pageImage = await page.render(
      width: page.width * scale,
      height: page.height * scale,
      format: PdfPageImageFormat.jpeg,
      quality: 80,
      backgroundColor: "#FFFFFF",
    );
    await page.close();
    if (pageRequest.generation != _renderGeneration ||
        pageImage == null ||
        !_isInWindow(pageRequest, pageNumber)) {
      return;
    }
    final codec = await ui.instantiateImageCodec(pageImage.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (pageRequest.generation != _renderGeneration ||
        !_isInWindow(pageRequest, pageNumber)) {
      frame.image.dispose();
      return;
    }
    // Dispose old image when upgrading quality
    _pageCache[pageNumber]?.dispose();
    _pageCache[pageNumber] = frame.image;
    if (isClose) {
      _lowQualityPages.remove(pageNumber);
    } else {
      _lowQualityPages.add(pageNumber);
    }
    notifyListeners();
  }

  /// Whether [pageNumber] still needs rendering (missing or needs upgrade).
  bool _needsRender(PageRequest pageRequest, int pageNumber) {
    if (!_isInWindow(pageRequest, pageNumber)) return false;
    if (!_pageCache.containsKey(pageNumber)) return true;
    // Already cached — only re-render if it's low quality and now close
    return _lowQualityPages.contains(pageNumber) &&
        (pageNumber - pageRequest.currentPage).abs() <= _fullQualityRange;
  }

  void _startRenderConsumer() {
    _renderChannel.stream.listen((pageRequest) async {
      final gen = _renderGeneration;
      final pagesToRender = pageRequest.pagesToRender;
      pagesToRender.sort(
        (a, b) => (a - pageRequest.currentPage).abs().compareTo(
          (b - pageRequest.currentPage).abs(),
        ),
      );
      for (final page in pagesToRender) {
        if (gen != _renderGeneration) return;
        if (!_needsRender(pageRequest, page)) continue;
        await _renderPage(pageRequest, page);
      }
    });
  }

  void requestPages(int currentPage) {
    _renderGeneration++;
    final needed = <int>{};
    for (int i = -_cacheBehind; i <= _cacheAhead; i++) {
      final p = currentPage + i;
      if (p >= 1 && p <= _document.pagesCount) needed.add(p);
    }
    final toEvict = _pageCache.keys.where((p) => !needed.contains(p)).toList();
    for (final p in toEvict) {
      _pageCache.remove(p)?.dispose();
      _lowQualityPages.remove(p);
    }
    if (toEvict.isNotEmpty) notifyListeners();
    // Collect pages that need rendering or a quality upgrade
    final missing = <int>[];
    for (final p in needed) {
      if (!_pageCache.containsKey(p)) {
        missing.add(p);
      } else if (_lowQualityPages.contains(p) &&
          (p - currentPage).abs() <= _fullQualityRange) {
        missing.add(p); // needs full-quality re-render
      }
    }
    if (missing.isNotEmpty) {
      _renderChannel.add(PageRequest(currentPage, _renderGeneration, missing));
    }
  }

  ui.Image? getPage(int pageNumber) => _pageCache[pageNumber];
  Future<void> close() {
    for (final image in _pageCache.values) {
      image.dispose();
    }
    _lowQualityPages.clear();
    return Future.wait([_renderChannel.close(), _document.close()]);
  }

  int get pageCount => _document.pagesCount;

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
