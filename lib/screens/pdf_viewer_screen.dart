import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

class PdfViewerScreen extends StatefulWidget {
  final PdfDocument document;

  const PdfViewerScreen({super.key, required this.document});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _currentPage = 1;
  double _pageIndicatorOpacity = 0.0;
  Timer? _fadeTimer;

  /// Decoded GPU-ready images, keyed by page number.
  final Map<int, ui.Image> _pageCache = {};

  late final StreamController<List<int>> _renderChannel;
  static const _cacheAhead = 2;
  static const _cacheBehind = 1;

  /// Render scale computed from screen physical size.
  double _renderScale = 1.5;

  /// Incremented on every navigation; lets the consumer skip stale renders.
  int _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _computeRenderScale();
    _renderChannel = StreamController<List<int>>();
    _startRenderConsumer();
    _showPageIndicator();
    _requestPages();
  }

  /// Derives render scale from the screen's physical pixel width so the
  /// very first render already uses the correct resolution.
  void _computeRenderScale() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenPixelWidth = view.physicalSize.width;
    if (screenPixelWidth > 0) {
      _renderScale = (screenPixelWidth * 1.2) / 595; // 595pt ≈ A4 width
      _renderScale = _renderScale.clamp(1.0, 4.0);
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _renderChannel.close();
    // Dispose GPU images
    for (final img in _pageCache.values) {
      img.dispose();
    }
    widget.document.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Render consumer (runs for the lifetime of the screen) ─────────

  /// Listens on [_renderChannel] and renders pages sequentially,
  /// always prioritising the page closest to [_currentPage].
  void _startRenderConsumer() {
    _renderChannel.stream.listen((requestedPages) async {
      final gen = _renderGeneration;
      // Sort by proximity to the current page
      requestedPages.sort(
        (a, b) => (a - _currentPage).abs().compareTo((b - _currentPage).abs()),
      );

      for (final pageNum in requestedPages) {
        if (gen != _renderGeneration || !mounted) return;
        if (_pageCache.containsKey(pageNum) || !_isInWindow(pageNum)) continue;
        await _renderPage(pageNum, gen);
      }
    });
  }

  // ── Page request producer ─────────────────────────────────────────

  /// Calculates which pages are needed, evicts stale entries, and sends
  /// the missing page numbers through the render channel.
  void _requestPages() {
    _renderGeneration++;
    final needed = <int>{};
    for (int i = -_cacheBehind; i <= _cacheAhead; i++) {
      final p = _currentPage + i;
      if (p >= 1 && p <= widget.document.pagesCount) needed.add(p);
    }
    // Evict pages outside the window and dispose their GPU textures
    final toEvict = _pageCache.keys.where((p) => !needed.contains(p)).toList();
    for (final p in toEvict) {
      _pageCache.remove(p)?.dispose();
    }

    // Send only the pages that still need rendering
    final missing = needed.where((p) => !_pageCache.containsKey(p)).toList();
    if (missing.isNotEmpty) {
      _renderChannel.add(missing);
    }
  }

  // ── Rendering ─────────────────────────────────────────────────────

  bool _isInWindow(int pageNum) =>
      pageNum >= _currentPage - _cacheBehind &&
      pageNum <= _currentPage + _cacheAhead;

  Future<void> _renderPage(int pageNum, int gen) async {
    final page = await widget.document.getPage(pageNum);
    if (gen != _renderGeneration) { await page.close(); return; }

    final pageImage = await page.render(
      width: page.width * _renderScale,
      height: page.height * _renderScale,
      format: PdfPageImageFormat.jpeg,
    );
    await page.close();
    if (gen != _renderGeneration || !mounted || pageImage == null) return;
    if (!_isInWindow(pageNum)) return;

    // Decode bytes into a GPU-resident ui.Image once
    final codec = await ui.instantiateImageCodec(pageImage.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();

    if (gen != _renderGeneration || !mounted || !_isInWindow(pageNum)) {
      frame.image.dispose();
      return;
    }
    setState(() => _pageCache[pageNum] = frame.image);
  }

  // ── Page indicator ────────────────────────────────────────────────

  void _showPageIndicator() {
    setState(() => _pageIndicatorOpacity = 1.0);
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _pageIndicatorOpacity = 0.0);
    });
  }

  // ── Navigation ────────────────────────────────────────────────────

  void _goToPreviousPage() {
    if (_currentPage == 1) return;
    setState(() => _currentPage--);
    _showPageIndicator();
    _requestPages();
  }

  void _goToNextPage() {
    if (_currentPage >= widget.document.pagesCount) return;
    setState(() => _currentPage++);
    _showPageIndicator();
    _requestPages();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cachedImage = _pageCache[_currentPage];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Rendered page — RepaintBoundary isolates from indicator repaints
          Center(
            child: cachedImage != null
                ? RepaintBoundary(
                    child: RawImage(
                      image: cachedImage,
                      fit: BoxFit.contain,
                    ),
                  )
                : const CircularProgressIndicator(),
          ),

          // Tap zones
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goToPreviousPage,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goToNextPage,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),

          // Page indicator
          if (widget.document.pagesCount > 0)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _pageIndicatorOpacity,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_currentPage / ${widget.document.pagesCount}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white54,
                size: 28,
              ),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
            ),
          ),
        ],
      ),
    );
  }
}
