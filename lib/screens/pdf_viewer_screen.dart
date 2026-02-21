import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libresheets/services/pdf_service.dart';

class PdfViewerScreen extends StatefulWidget {
  final PdfService pdfService;

  const PdfViewerScreen({
    super.key,
    required this.pdfService,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(1);
  final ValueNotifier<bool> _sliderVisible = ValueNotifier<bool>(false);
  late final AnimationController _fadeController;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _showPageIndicator();
    _requestPages();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    _currentPage.dispose();
    _sliderVisible.dispose();
    widget.pdfService.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Page request producer ─────────────────────────────────────────

  /// Calculates which pages are needed, evicts stale entries, and sends
  /// the missing page numbers through the render channel.
  void _requestPages() {
    widget.pdfService.requestPages(_currentPage.value);
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
    if (_currentPage.value >= widget.pdfService.pageCount) return;
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Rendered page — RepaintBoundary isolates from indicator repaints
          Center(
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.pdfService, _currentPage]),
              builder: (context, child) {
                final cachedImage = widget.pdfService.getPage(
                  _currentPage.value,
                );
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
          if (widget.pdfService.pageCount > 0)
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
                                    activeTrackColor: Colors.black54,
                                    inactiveTrackColor: Colors.black26,
                                    thumbColor: Colors.black54,
                                    overlayColor: Colors.black26,
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                  ),
                                  child: Slider(
                                    activeColor: Colors.black54,
                                    min: 1,
                                    max: widget.pdfService.pageCount.toDouble(),
                                    value: currentPage.toDouble(),
                                    divisions: widget.pdfService.pageCount > 1
                                        ? widget.pdfService.pageCount - 1
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
                                '$currentPage / ${widget.pdfService.pageCount}',
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
                      color: Colors.black54,
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
