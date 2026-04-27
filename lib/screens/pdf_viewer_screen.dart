import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libresheets/models/dynamic_annotation.dart';
import 'package:libresheets/models/viewer_page_layout.dart';
import 'package:libresheets/services/pdf_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'dynamic_annotation_widgets.dart';

const _minPageSwipeDistance = 72.0;
const _minPageSwipeVelocity = 300.0;

typedef AddDynamicAnnotation =
    Future<DynamicAnnotation> Function(
      DynamicAnnotationType type,
      int pageNumber,
      double x,
      double y,
    );

class PdfViewerScreen extends StatefulWidget {
  final PdfPageSource pdfService;
  final int initialPage;
  final Future<void> Function(int page)? onSaveProgress;
  final Future<List<DynamicAnnotation>> Function()? onLoadAnnotations;
  final AddDynamicAnnotation? onAddAnnotation;
  final Future<void> Function(DynamicAnnotation annotation)? onDeleteAnnotation;
  final Future<void> Function(DynamicAnnotation annotation, double scale)?
      onResizeAnnotation;

  const PdfViewerScreen({
    super.key,
    required this.pdfService,
    this.initialPage = 1,
    this.onSaveProgress,
    this.onLoadAnnotations,
    this.onAddAnnotation,
    this.onDeleteAnnotation,
    this.onResizeAnnotation,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ValueNotifier<int> _currentPage;
  final ValueNotifier<bool> _sliderVisible = ValueNotifier<bool>(false);
  final FocusNode _focusNode = FocusNode(debugLabel: 'pdf_viewer');
  late final AnimationController _fadeController;
  Timer? _hideTimer;
  List<DynamicAnnotation> _annotations = [];
  DynamicAnnotationType? _selectedAnnotationType;
  double _pageDragDelta = 0;
  bool _isLandscape = false;
  bool get _isAnnotationMode =>
      _selectedAnnotationType != null && widget.onAddAnnotation != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPage = ValueNotifier<int>(
      clampViewerPage(widget.initialPage, widget.pdfService.pageCount),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(WakelockPlus.enable());
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _showPageIndicator();
    _requestPages();
    unawaited(_loadAnnotations());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _fadeController.dispose();
    _currentPage.dispose();
    _sliderVisible.dispose();
    _focusNode.dispose();
    unawaited(widget.pdfService.close());
    unawaited(WakelockPlus.disable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_isLandscape == isLandscape) {
      return;
    }
    _isLandscape = isLandscape;
    final normalizedPage = normalizeViewerPage(
      page: _currentPage.value,
      pageCount: widget.pdfService.pageCount,
      isLandscape: _isLandscape,
    );
    if (normalizedPage == _currentPage.value) {
      return;
    }
    _currentPage.value = normalizedPage;
    _showPageIndicator();
    _requestPages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveProgress());
    }
  }

  void _requestPages() {
    widget.pdfService.requestPages(_currentPage.value);
  }

  Future<void> _loadAnnotations() async {
    final onLoadAnnotations = widget.onLoadAnnotations;
    if (onLoadAnnotations == null) {
      return;
    }
    try {
      final annotations = await onLoadAnnotations();
      if (mounted) {
        setState(() {
          _annotations = annotations;
        });
      }
    } catch (error, stackTrace) {
      _reportViewerError(error, stackTrace, 'while loading annotations');
    }
  }

  Future<void> _saveProgress() async {
    final onSaveProgress = widget.onSaveProgress;
    if (onSaveProgress == null) {
      return;
    }
    try {
      await onSaveProgress(_currentPage.value);
    } catch (error, stackTrace) {
      _reportViewerError(error, stackTrace, 'while saving viewer progress');
    }
  }

  void _reportViewerError(
    Object error,
    StackTrace stackTrace,
    String description,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'libresheets',
        context: ErrorDescription(description),
      ),
    );
  }

  void _requestViewerFocus() {
    if (_focusNode.canRequestFocus) {
      _focusNode.requestFocus();
    }
  }

  void _showPageIndicator() {
    _fadeController.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_sliderVisible.value) {
        _fadeController.reverse();
      }
    });
  }

  void _setCurrentPage(
    int page, {
    bool shouldRequestPages = true,
    bool shouldKeepIndicator = true,
    bool shouldRequestFocus = true,
  }) {
    final normalizedPage = normalizeViewerPage(
      page: page,
      pageCount: widget.pdfService.pageCount,
      isLandscape: _isLandscape,
    );
    if (normalizedPage == _currentPage.value) {
      if (shouldRequestFocus) {
        _requestViewerFocus();
      }
      return;
    }
    _currentPage.value = normalizedPage;
    if (shouldKeepIndicator) {
      _showPageIndicator();
    }
    if (shouldRequestPages) {
      _requestPages();
    }
    if (shouldRequestFocus) {
      _requestViewerFocus();
    }
  }

  void _goToPreviousPage() {
    _setCurrentPage(
      previousViewerPage(
        page: _currentPage.value,
        pageCount: widget.pdfService.pageCount,
        isLandscape: _isLandscape,
      ),
    );
  }

  void _goToNextPage() {
    _setCurrentPage(
      nextViewerPage(
        page: _currentPage.value,
        pageCount: widget.pdfService.pageCount,
        isLandscape: _isLandscape,
      ),
    );
  }

  void _startPageDrag(DragStartDetails details) {
    _pageDragDelta = 0;
  }

  void _updatePageDrag(DragUpdateDetails details) {
    _pageDragDelta += details.primaryDelta ?? details.delta.dx;
  }

  void _endPageDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_pageDragDelta <= -_minPageSwipeDistance ||
        velocity <= -_minPageSwipeVelocity) {
      _goToNextPage();
    } else if (_pageDragDelta >= _minPageSwipeDistance ||
        velocity >= _minPageSwipeVelocity) {
      _goToPreviousPage();
    } else {
      _requestViewerFocus();
    }
    _pageDragDelta = 0;
  }

  void _toggleSlider() {
    if (_isAnnotationMode) {
      return;
    }
    _sliderVisible.value = !_sliderVisible.value;
    if (!_sliderVisible.value) {
      _showPageIndicator();
      _requestViewerFocus();
      return;
    }
    _hideTimer?.cancel();
    _fadeController.value = 1.0;
    _requestViewerFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      _goToPreviousPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _goToNextPage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleAnnotationMode() {
    setState(() {
      _selectedAnnotationType = _selectedAnnotationType == null
          ? DynamicAnnotationType.piano
          : null;
    });
    _requestViewerFocus();
  }

  void _selectAnnotationType(DynamicAnnotationType type) {
    setState(() {
      _selectedAnnotationType = type;
    });
    _requestViewerFocus();
  }

  Future<void> _addAnnotation(int pageNumber, double x, double y) async {
    final type = _selectedAnnotationType;
    final onAddAnnotation = widget.onAddAnnotation;
    if (type == null || onAddAnnotation == null) {
      return;
    }
    try {
      final annotation = await onAddAnnotation(type, pageNumber, x, y);
      if (mounted) {
        setState(() {
          _annotations = [..._annotations, annotation];
        });
      }
    } catch (error, stackTrace) {
      _reportViewerError(error, stackTrace, 'while adding annotation');
    }
  }

  Future<void> _deleteAnnotation(DynamicAnnotation annotation) async {
    final onDeleteAnnotation = widget.onDeleteAnnotation;
    if (onDeleteAnnotation == null) {
      return;
    }
    try {
      await onDeleteAnnotation(annotation);
      if (mounted) {
        setState(() {
          _annotations = _annotations
              .where((item) => !_isSameAnnotation(item, annotation))
              .toList();
        });
      }
    } catch (error, stackTrace) {
      _reportViewerError(error, stackTrace, 'while deleting annotation');
    }
  }

  Future<void> _resizeAnnotation(
    DynamicAnnotation annotation,
    double scale,
  ) async {
    final onResizeAnnotation = widget.onResizeAnnotation;
    if (onResizeAnnotation == null) {
      return;
    }
    try {
      await onResizeAnnotation(annotation, scale);
    } catch (error, stackTrace) {
      _reportViewerError(error, stackTrace, 'while resizing annotation');
    }
  }

  void _handleBackButton() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  List<DynamicAnnotation> _annotationsForPage(int pageNumber) => _annotations
      .where((annotation) => annotation.pageNumber == pageNumber)
      .toList();

  Widget _buildVisiblePages(VisiblePages visiblePages) {
    final leadingImage = widget.pdfService.getPage(visiblePages.leadingPage);
    final trailingImage = visiblePages.trailingPage == null
        ? null
        : widget.pdfService.getPage(visiblePages.trailingPage!);
    if (leadingImage == null ||
        (visiblePages.trailingPage != null && trailingImage == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trailingImage == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: DynamicAnnotationPage(
          pageNumber: visiblePages.leadingPage,
          image: leadingImage,
          annotations: _annotationsForPage(visiblePages.leadingPage),
          isAnnotationMode: _isAnnotationMode,
          onAddAnnotation: _addAnnotation,
          onDeleteAnnotation: widget.onDeleteAnnotation == null
              ? null
              : (annotation) {
                  unawaited(_deleteAnnotation(annotation));
                },
          onResizeAnnotation: widget.onResizeAnnotation == null
              ? null
              : (annotation, scale) {
                  unawaited(_resizeAnnotation(annotation, scale));
                },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: DynamicAnnotationPage(
              pageNumber: visiblePages.leadingPage,
              image: leadingImage,
              annotations: _annotationsForPage(visiblePages.leadingPage),
              isAnnotationMode: _isAnnotationMode,
              onAddAnnotation: _addAnnotation,
              onDeleteAnnotation: widget.onDeleteAnnotation == null
                  ? null
                  : (annotation) {
                      unawaited(_deleteAnnotation(annotation));
                    },
              onResizeAnnotation: widget.onResizeAnnotation == null
                  ? null
                  : (annotation, scale) {
                      unawaited(_resizeAnnotation(annotation, scale));
                    },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DynamicAnnotationPage(
              pageNumber: visiblePages.trailingPage!,
              image: trailingImage,
              annotations: _annotationsForPage(visiblePages.trailingPage!),
              isAnnotationMode: _isAnnotationMode,
              onAddAnnotation: _addAnnotation,
              onDeleteAnnotation: widget.onDeleteAnnotation == null
                  ? null
                  : (annotation) {
                      unawaited(_deleteAnnotation(annotation));
                    },
              onResizeAnnotation: widget.onResizeAnnotation == null
                  ? null
                  : (annotation, scale) {
                      unawaited(_resizeAnnotation(annotation, scale));
                    },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_saveProgress());
        }
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              SizedBox.expand(
                child: OrientationBuilder(
                  builder: (context, orientation) {
                    final isLandscape = orientation == Orientation.landscape;
                    return ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.pdfService,
                        _currentPage,
                      ]),
                      builder: (context, child) {
                        return _buildVisiblePages(
                          buildVisiblePages(
                            page: _currentPage.value,
                            pageCount: widget.pdfService.pageCount,
                            isLandscape: isLandscape,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (!_isAnnotationMode)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: _startPageDrag,
                    onHorizontalDragUpdate: _updatePageDrag,
                    onHorizontalDragEnd: _endPageDrag,
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
                ),
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
                            final isLandscape =
                                MediaQuery.orientationOf(context) ==
                                Orientation.landscape;
                            final anchors = buildViewerAnchors(
                              widget.pdfService.pageCount,
                              isLandscape,
                            );
                            final visiblePages = buildVisiblePages(
                              page: currentPage,
                              pageCount: widget.pdfService.pageCount,
                              isLandscape: isLandscape,
                            );
                            final sliderValue = isLandscape
                                ? sliderIndexForPage(
                                    page: currentPage,
                                    pageCount: widget.pdfService.pageCount,
                                    isLandscape: true,
                                  ).toDouble()
                                : currentPage.toDouble();
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
                                        min: isLandscape ? 0 : 1,
                                        max: isLandscape
                                            ? (anchors.length - 1).toDouble()
                                            : widget.pdfService.pageCount
                                                  .toDouble(),
                                        value: sliderValue,
                                        divisions: isLandscape
                                            ? (anchors.length > 1
                                                  ? anchors.length - 1
                                                  : null)
                                            : (widget.pdfService.pageCount > 1
                                                  ? widget
                                                            .pdfService
                                                            .pageCount -
                                                        1
                                                  : null),
                                        onChanged: (value) {
                                          _setCurrentPage(
                                            isLandscape
                                                ? pageForSliderIndex(
                                                    index: value.round(),
                                                    pageCount: widget
                                                        .pdfService
                                                        .pageCount,
                                                    isLandscape: true,
                                                  )
                                                : value.round(),
                                            shouldRequestPages: false,
                                            shouldKeepIndicator: false,
                                            shouldRequestFocus: false,
                                          );
                                        },
                                        onChangeEnd: (value) {
                                          _setCurrentPage(
                                            isLandscape
                                                ? pageForSliderIndex(
                                                    index: value.round(),
                                                    pageCount: widget
                                                        .pdfService
                                                        .pageCount,
                                                    isLandscape: true,
                                                  )
                                                : value.round(),
                                          );
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
                                    formatVisiblePageLabel(
                                      visiblePages,
                                      widget.pdfService.pageCount,
                                    ),
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
                        onPressed: _handleBackButton,
                        tooltip: 'Back',
                      ),
                    );
                  },
                ),
              ),
              if (widget.onAddAnnotation != null)
                DynamicAnnotationControls(
                  selectedType: _selectedAnnotationType,
                  onToggle: _toggleAnnotationMode,
                  onSelected: _selectAnnotationType,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameAnnotation(DynamicAnnotation a, DynamicAnnotation b) {
  if (a.id != null && b.id != null) {
    return a.id == b.id;
  }
  return identical(a, b);
}
