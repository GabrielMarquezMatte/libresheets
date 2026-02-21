import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:libresheets/models/page_request.dart';
import 'package:pdfx/pdfx.dart';

final class PdfService extends ChangeNotifier {
  final PdfDocument _document;
  final Map<int, ui.Image> _pageCache = {};
  late final StreamController<PageRequest> _renderChannel;
  static const _cacheAhead = 10;
  static const _cacheBehind = 5;
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
    final page = await _document.getPage(pageNumber);
    if (pageRequest.generation != _renderGeneration) {
      await page.close();
      return;
    }
    final format = Platform.isAndroid
        ? PdfPageImageFormat.webp
        : PdfPageImageFormat.jpeg;
    final pageImage = await page.render(
      width: page.width * _renderScale,
      height: page.height * _renderScale,
      format: format,
      quality: Platform.isAndroid ? 1 : 80,
      forPrint: Platform.isAndroid,
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
    _pageCache[pageNumber] = frame.image;
    notifyListeners();
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
        if (_pageCache.containsKey(page) || !_isInWindow(pageRequest, page))
          continue;
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
    }
    if (toEvict.isNotEmpty) notifyListeners();
    final missing = needed.where((p) => !_pageCache.containsKey(p)).toList();
    if (missing.isNotEmpty) {
      _renderChannel.add(
        PageRequest(currentPage, _renderGeneration, missing),
      );
    }
  }

  ui.Image? getPage(int pageNumber) => _pageCache[pageNumber];
  Future<void> close() {
    _pageCache.values.forEach((image) => image.dispose());
    return Future.wait([_renderChannel.close(), _document.close()]);
  }

  int get pageCount => _document.pagesCount;

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
