import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:libresheets/models/dynamic_annotation.dart';

final class DynamicAnnotationPage extends StatelessWidget {
  final int pageNumber;
  final ui.Image image;
  final List<DynamicAnnotation> annotations;
  final bool isAnnotationMode;
  final void Function(int pageNumber, double x, double y) onAddAnnotation;
  final void Function(DynamicAnnotation annotation)? onDeleteAnnotation;
  final void Function(DynamicAnnotation annotation, double scale)?
      onResizeAnnotation;

  const DynamicAnnotationPage({
    super.key,
    required this.pageNumber,
    required this.image,
    required this.annotations,
    required this.isAnnotationMode,
    required this.onAddAnnotation,
    this.onDeleteAnnotation,
    this.onResizeAnnotation,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: isAnnotationMode
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTapUp: isAnnotationMode
              ? (details) {
                  onAddAnnotation(
                    pageNumber,
                    _normalizedCoordinate(details.localPosition.dx, size.width),
                    _normalizedCoordinate(
                      details.localPosition.dy,
                      size.height,
                    ),
                  );
                }
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: RawImage(
                  image: image,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              for (final annotation in annotations)
                _PositionedAnnotation(
                  key: ValueKey(annotation.id ?? annotation),
                  annotation: annotation,
                  size: size,
                  onDeleteAnnotation: onDeleteAnnotation,
                  onResizeAnnotation: onResizeAnnotation,
                ),
            ],
          ),
        );
      },
    );
  }
}

final class DynamicAnnotationControls extends StatelessWidget {
  final DynamicAnnotationType? selectedType;
  final VoidCallback onToggle;
  final ValueChanged<DynamicAnnotationType> onSelected;

  const DynamicAnnotationControls({
    super.key,
    required this.selectedType,
    required this.onToggle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: selectedType == null
            ? IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.black54),
                onPressed: onToggle,
                tooltip: 'Annotations',
              )
            : _DynamicAnnotationPalette(
                selectedType: selectedType!,
                onToggle: onToggle,
                onSelected: onSelected,
              ),
      ),
    );
  }
}

final class _DynamicAnnotationPalette extends StatelessWidget {
  final DynamicAnnotationType selectedType;
  final VoidCallback onToggle;
  final ValueChanged<DynamicAnnotationType> onSelected;

  const _DynamicAnnotationPalette({
    required this.selectedType,
    required this.onToggle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: onToggle,
            tooltip: 'Close annotations',
          ),
          for (final type in DynamicAnnotationType.values)
            _AnnotationTypeButton(
              type: type,
              isSelected: type == selectedType,
              onPressed: () {
                onSelected(type);
              },
            ),
        ],
      ),
    );
  }
}

final class _AnnotationTypeButton extends StatelessWidget {
  final DynamicAnnotationType type;
  final bool isSelected;
  final VoidCallback onPressed;

  const _AnnotationTypeButton({
    required this.type,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _annotationTooltip(type),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(42, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: isSelected ? Colors.black87 : Colors.white70,
          backgroundColor: isSelected ? Colors.white70 : Colors.transparent,
          textStyle: const TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onPressed,
        child: Text(type.symbol),
      ),
    );
  }
}

final class _PositionedAnnotation extends StatefulWidget {
  final DynamicAnnotation annotation;
  final Size size;
  final void Function(DynamicAnnotation annotation)? onDeleteAnnotation;
  final void Function(DynamicAnnotation annotation, double scale)?
      onResizeAnnotation;

  const _PositionedAnnotation({
    super.key,
    required this.annotation,
    required this.size,
    this.onDeleteAnnotation,
    this.onResizeAnnotation,
  });

  @override
  State<_PositionedAnnotation> createState() => _PositionedAnnotationState();
}

class _PositionedAnnotationState extends State<_PositionedAnnotation> {
  late double _scale;
  double _baseScale = 1.0;
  bool _hasPendingChange = false;
  Timer? _saveTimer;

  static const _minScale = 0.5;
  static const _maxScale = 3.0;

  @override
  void initState() {
    super.initState();
    _scale = widget.annotation.scale;
  }

  @override
  void didUpdateWidget(_PositionedAnnotation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.annotation.id != widget.annotation.id) {
      _scale = widget.annotation.scale;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _persistScale() {
    if (widget.annotation.id == null) {
      return;
    }
    widget.onResizeAnnotation?.call(widget.annotation, _scale);
  }

  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), _persistScale);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    setState(() {
      _scale = (_baseScale * details.scale).clamp(_minScale, _maxScale);
      _hasPendingChange = true;
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (!_hasPendingChange) {
      return;
    }
    _hasPendingChange = false;
    _saveTimer?.cancel();
    _persistScale();
  }

  void _handleScroll(PointerScrollEvent event) {
    setState(() {
      _scale = (_scale - event.scrollDelta.dy * 0.001)
          .clamp(_minScale, _maxScale);
      _hasPendingChange = true;
    });
    _schedulePersist();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.annotation.x.clamp(0.0, 1.0) * widget.size.width,
      top: widget.annotation.y.clamp(0.0, 1.0) * widget.size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleScroll(event);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: widget.onDeleteAnnotation == null
                ? null
                : () => widget.onDeleteAnnotation!(widget.annotation),
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            onScaleEnd: _handleScaleEnd,
            child: Transform.scale(
              scale: _scale,
              child: _DynamicAnnotationMark(widget.annotation.type),
            ),
          ),
        ),
      ),
    );
  }
}

final class _DynamicAnnotationMark extends StatelessWidget {
  final DynamicAnnotationType type;

  const _DynamicAnnotationMark(this.type);

  @override
  Widget build(BuildContext context) {
    final glyph = type.smuflGlyph;
    if (glyph == null) {
      return SizedBox(
        width: 96,
        height: 32,
        child: CustomPaint(
          painter: _DynamicWedgePainter(
            isCrescendo: type == DynamicAnnotationType.crescendo,
          ),
        ),
      );
    }
    return Text(
      glyph,
      style: const TextStyle(
        fontFamily: 'Bravura',
        color: Colors.black,
        fontSize: 32,
      ),
    );
  }
}

final class _DynamicWedgePainter extends CustomPainter {
  final bool isCrescendo;

  const _DynamicWedgePainter({required this.isCrescendo});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final startX = isCrescendo ? 0.0 : size.width;
    final endX = isCrescendo ? size.width : 0.0;
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(startX, centerY),
      Offset(endX, size.height * 0.2),
      paint,
    );
    canvas.drawLine(
      Offset(startX, centerY),
      Offset(endX, size.height * 0.8),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DynamicWedgePainter oldDelegate) =>
      oldDelegate.isCrescendo != isCrescendo;
}

double _normalizedCoordinate(double value, double max) {
  if (max <= 0) {
    return 0;
  }
  return (value / max).clamp(0.0, 1.0).toDouble();
}

String _annotationTooltip(DynamicAnnotationType type) => switch (type) {
  DynamicAnnotationType.pianissimo => 'Pianissimo',
  DynamicAnnotationType.piano => 'Piano',
  DynamicAnnotationType.mezzoPiano => 'Mezzo piano',
  DynamicAnnotationType.mezzoForte => 'Mezzo forte',
  DynamicAnnotationType.forte => 'Forte',
  DynamicAnnotationType.fortissimo => 'Fortissimo',
  DynamicAnnotationType.crescendo => 'Crescendo',
  DynamicAnnotationType.diminuendo => 'Diminuendo',
};
