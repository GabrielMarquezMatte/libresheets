import 'dart:async';

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
  final Map<int, Uint8List> _pageCache = {};
  late final StreamController<List<int>> _renderChannel;
  static const _cacheAhead = 2;
  static const _cacheBehind = 1;
  static const _renderScale = 3.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _renderChannel = StreamController<List<int>>();
    _startRenderConsumer();
    _showPageIndicator();
    _requestPages();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _renderChannel.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Render consumer (runs for the lifetime of the screen) ─────────

  /// Listens on [_renderChannel] and renders pages sequentially,
  /// always prioritising the page closest to [_currentPage].
  void _startRenderConsumer() {
    _renderChannel.stream.listen((requestedPages) async {
      // Sort by proximity to the current page
      requestedPages.sort(
        (a, b) => (a - _currentPage).abs().compareTo((b - _currentPage).abs()),
      );

      for (final pageNum in requestedPages) {
        if (!mounted) return;
        if (_pageCache.containsKey(pageNum) || !_isInWindow(pageNum)) continue;
        await _renderPage(pageNum);
      }
    });
  }

  // ── Page request producer ─────────────────────────────────────────

  /// Calculates which pages are needed, evicts stale entries, and sends
  /// the missing page numbers through the render channel.
  void _requestPages() {
    final needed = <int>{};
    for (int i = -_cacheBehind; i <= _cacheAhead; i++) {
      final p = _currentPage + i;
      if (p >= 1 && p <= widget.document.pagesCount) needed.add(p);
    }
    // Evict pages outside the window
    _pageCache.removeWhere((page, _) => !needed.contains(page));

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

  Future<void> _renderPage(int pageNum) async {
    final page = await widget.document.getPage(pageNum);
    final pageImage = await page.render(
      width: page.width * _renderScale,
      height: page.height * _renderScale,
      format: PdfPageImageFormat.png,
    );
    await page.close();
    if (!mounted || pageImage == null) return;

    if (_isInWindow(pageNum)) {
      setState(() => _pageCache[pageNum] = pageImage.bytes);
    }
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
    final pageImage = _pageCache[_currentPage];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Rendered page
          Center(
            child: pageImage != null
                ? Image.memory(
                    pageImage,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
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
