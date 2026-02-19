import 'dart:async';
import 'dart:io';
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

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(1);
  final ValueNotifier<ui.Image?> _currentImage = ValueNotifier<ui.Image?>(null);
  final ValueNotifier<bool> _sliderVisible = ValueNotifier<bool>(false);
  late final AnimationController _fadeController;
  Timer? _hideTimer;

  /// Decoded GPU-ready images, keyed by page number.
  final Map<int, ui.Image> _pageCache = {};

  late final StreamController<List<int>> _renderChannel;
  static const _cacheAhead = 4;
  static const _cacheBehind = 2;

  /// Render scale computed from screen physical size.
  double _renderScale = 1.5;

  /// Incremented on every navigation; lets the consumer skip stale renders.
  int _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _currentPage.addListener(_updateCurrentImage);
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
    _hideTimer?.cancel();
    _fadeController.dispose();
    _currentPage.dispose();
    _currentImage.dispose();
    _sliderVisible.dispose();
    _renderChannel.close();
    for (final img in _pageCache.values) {
      img.dispose();
    }
    widget.document.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _updateCurrentImage() {
    _currentImage.value = _pageCache[_currentPage.value];
  }

  // ── Render consumer (runs for the lifetime of the screen) ─────────

  /// Listens on [_renderChannel] and renders pages sequentially,
  /// always prioritising the page closest to [_currentPage].
  void _startRenderConsumer() {
    _renderChannel.stream.listen((requestedPages) async {
      final gen = _renderGeneration;
      requestedPages.sort(
        (a, b) => (a - _currentPage.value).abs().compareTo(
          (b - _currentPage.value).abs(),
        ),
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
      final p = _currentPage.value + i;
      if (p >= 1 && p <= widget.document.pagesCount) needed.add(p);
    }

    final toEvict = _pageCache.keys.where((p) => !needed.contains(p)).toList();
    for (final p in toEvict) {
      _pageCache.remove(p)?.dispose();
    }
    // Update the current image in case it was just evicted
    _updateCurrentImage();

    final missing = needed.where((p) => !_pageCache.containsKey(p)).toList();
    if (missing.isNotEmpty) {
      _renderChannel.add(missing);
    }
  }

  // ── Rendering ─────────────────────────────────────────────────────

  bool _isInWindow(int pageNum) =>
      pageNum >= _currentPage.value - _cacheBehind &&
      pageNum <= _currentPage.value + _cacheAhead;

  Future<void> _renderPage(int pageNum, int gen) async {
    final page = await widget.document.getPage(pageNum);
    if (gen != _renderGeneration) {
      await page.close();
      return;
    }
    final format = Platform.isAndroid ? PdfPageImageFormat.webp : PdfPageImageFormat.jpeg;
    final pageImage = await page.render(
      width: page.width * _renderScale,
      height: page.height * _renderScale,
      format: format,
    );
    await page.close();
    if (gen != _renderGeneration ||
        !mounted ||
        pageImage == null ||
        !_isInWindow(pageNum))
      return;
    final codec = await ui.instantiateImageCodec(pageImage.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (gen != _renderGeneration || !mounted || !_isInWindow(pageNum)) {
      frame.image.dispose();
      return;
    }
    _pageCache[pageNum] = frame.image;
    if (pageNum == _currentPage.value) {
      _updateCurrentImage();
    }
  }

  // ── Page indicator ────────────────────────────────────────────────

  void _showPageIndicator() {
    _fadeController.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_sliderVisible.value) {
        _fadeController.reverse();
      }
    });
  }

  // ── Navigation ────────────────────────────────────────────────────

  void _goToPreviousPage() {
    if (_currentPage.value == 1) return;
    _currentPage.value--;
    _showPageIndicator();
    _requestPages();
  }

  void _goToNextPage() {
    if (_currentPage.value >= widget.document.pagesCount) return;
    _currentPage.value++;
    _showPageIndicator();
    _requestPages();
  }

  void _toggleSlider() {
    _sliderVisible.value = !_sliderVisible.value;
    if (!_sliderVisible.value) {
      _showPageIndicator(); // Start fade out timer
      return;
    }
    _hideTimer?.cancel();
    _fadeController.value = 1.0; // Keep opaque while interacting
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Rendered page — RepaintBoundary isolates from indicator repaints
          Center(
            child: ValueListenableBuilder<ui.Image?>(
              valueListenable: _currentImage,
              builder: (context, cachedImage, child) {
                return cachedImage != null
                    ? RepaintBoundary(
                        child: RawImage(
                          image: cachedImage,
                          fit: BoxFit.contain,
                        ),
                      )
                    : const CircularProgressIndicator();
              },
            ),
          ),

          // Tap zones: left 35% | center 30% | right 35%
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  flex: 35,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goToPreviousPage,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  flex: 30,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleSlider,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  flex: 35,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goToNextPage,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),

          // Page slider + indicator
          if (widget.document.pagesCount > 0)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeController,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _sliderVisible,
                  builder: (context, isSliderVisible, child) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _currentPage,
                      builder: (context, currentPage, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSliderVisible)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white54,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    overlayColor: Colors.white24,
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                  ),
                                  child: Slider(
                                    min: 1,
                                    max: widget.document.pagesCount.toDouble(),
                                    value: currentPage.toDouble(),
                                    divisions: widget.document.pagesCount > 1
                                        ? widget.document.pagesCount - 1
                                        : null,
                                    onChanged: (v) {
                                      _currentPage.value = v.round();
                                    },
                                    onChangeEnd: (v) {
                                      _requestPages();
                                    },
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$currentPage / ${widget.document.pagesCount}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),

          // Back button
          Positioned(
            top: 8,
            left: 8,
            child: Builder(
              builder: (context) {
                return Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white54,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
