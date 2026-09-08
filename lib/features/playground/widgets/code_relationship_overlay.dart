import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/single_file_code_relationship_analyzer.dart';

class CodeRelationshipOverlay extends StatelessWidget {
  const CodeRelationshipOverlay({
    super.key,
    required this.relationships,
    required this.codeOriginX,
    required this.charWidth,
    required this.lineHeight,
    required this.verticalPadding,
    required this.verticalScrollOffset,
    required this.horizontalScrollOffset,
    required this.highlightedIndex,
    required this.onHoverRelationship,
    required this.onJumpTo,
  });

  final List<CodeRelationship> relationships;
  final double codeOriginX;
  final double charWidth;
  final double lineHeight;
  final double verticalPadding;
  final double verticalScrollOffset;
  final double horizontalScrollOffset;
  final int? highlightedIndex;
  final ValueChanged<int?> onHoverRelationship;
  final ValueChanged<CodeRelationshipAnchor> onJumpTo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layouts = <_WireLayout>[];
        for (var i = 0; i < relationships.length; i++) {
          layouts.add(
            _layoutFor(
              relationship: relationships[i],
              index: i,
              size: size,
            ),
          );
        }

        return Stack(
          key: const ValueKey('code-relationship-overlay'),
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('code-relationship-wire-layer'),
                  painter: _RelationshipWirePainter(
                    layouts: layouts,
                    highlightedIndex: highlightedIndex,
                  ),
                ),
              ),
            ),
            for (final layout in layouts) ...[
              if (layout.sourceVisible)
                _EndpointHitTarget(
                  point: layout.source,
                  tooltip: '${layout.relationship.kind.label}: '
                      '${layout.relationship.description}\n点击跳到另一端',
                  onEnter: () => onHoverRelationship(layout.index),
                  onExit: () => onHoverRelationship(null),
                  onTap: () => onJumpTo(layout.relationship.target),
                ),
              if (layout.targetVisible)
                _EndpointHitTarget(
                  point: layout.target,
                  tooltip: '${layout.relationship.kind.label}: '
                      '${layout.relationship.description}\n点击跳到另一端',
                  onEnter: () => onHoverRelationship(layout.index),
                  onExit: () => onHoverRelationship(null),
                  onTap: () => onJumpTo(layout.relationship.source),
                ),
            ],
            Positioned(
              top: 7,
              right: 9,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff111318).withValues(alpha: .86),
                    border: Border.all(color: const Color(0xff334155)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      '电线 ${relationships.length}  ·  ● 起点  ▷ 终点',
                      key: const ValueKey('code-relationship-count'),
                      style: const TextStyle(
                        color: Color(0xffaab4c3),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  _WireLayout _layoutFor({
    required CodeRelationship relationship,
    required int index,
    required Size size,
  }) {
    final rawSource = _pointFor(relationship.source, size);
    final rawTarget = _pointFor(relationship.target, size);
    final sourceVisible = _isVisible(rawSource, size);
    final targetVisible = _isVisible(rawTarget, size);

    final source = Offset(
      rawSource.dx.clamp(6, size.width - 6).toDouble(),
      rawSource.dy.clamp(7, size.height - 7).toDouble(),
    );
    final target = Offset(
      rawTarget.dx.clamp(6, size.width - 6).toDouble(),
      rawTarget.dy.clamp(7, size.height - 7).toDouble(),
    );

    return _WireLayout(
      relationship: relationship,
      index: index,
      source: source,
      target: target,
      sourceVisible: sourceVisible,
      targetVisible: targetVisible,
      bothOutsideSameSide: _bothOutsideSameSide(rawSource, rawTarget, size),
    );
  }

  Offset _pointFor(CodeRelationshipAnchor anchor, Size size) {
    final x = codeOriginX +
        ((anchor.column - 1) * charWidth) -
        horizontalScrollOffset;
    final y = verticalPadding +
        ((anchor.line - 1) * lineHeight) +
        (lineHeight / 2) -
        verticalScrollOffset;
    return Offset(x, y);
  }

  bool _isVisible(Offset point, Size size) =>
      point.dy >= 0 && point.dy <= size.height && point.dx >= 0 && point.dx <= size.width;

  bool _bothOutsideSameSide(Offset a, Offset b, Size size) {
    if (a.dy < 0 && b.dy < 0) return true;
    if (a.dy > size.height && b.dy > size.height) return true;
    return false;
  }
}

class _EndpointHitTarget extends StatelessWidget {
  const _EndpointHitTarget({
    required this.point,
    required this.tooltip,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  final Offset point;
  final String tooltip;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: point.dx - 8,
      top: point.dy - 8,
      width: 16,
      height: 16,
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 180),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _WireLayout {
  const _WireLayout({
    required this.relationship,
    required this.index,
    required this.source,
    required this.target,
    required this.sourceVisible,
    required this.targetVisible,
    required this.bothOutsideSameSide,
  });

  final CodeRelationship relationship;
  final int index;
  final Offset source;
  final Offset target;
  final bool sourceVisible;
  final bool targetVisible;
  final bool bothOutsideSameSide;
}

class _RelationshipWirePainter extends CustomPainter {
  const _RelationshipWirePainter({
    required this.layouts,
    required this.highlightedIndex,
  });

  final List<_WireLayout> layouts;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    for (final layout in layouts) {
      if (layout.bothOutsideSameSide) continue;
      final highlighted = highlightedIndex == layout.index;
      final hasHighlight = highlightedIndex != null;
      final color = _colorFor(layout.relationship.kind).withValues(
        alpha: highlighted
            ? .96
            : hasHighlight
                ? .13
                : .42,
      );
      final paint = Paint()
        ..color = color
        ..strokeWidth = highlighted ? 2.7 : 1.55
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = _pathFor(layout, size);
      canvas.drawPath(path, paint);

      final markerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(layout.source, highlighted ? 4.5 : 3.2, markerPaint);
      _drawArrow(canvas, layout, markerPaint);

      if (highlighted) {
        _drawLabel(canvas, layout, size);
      }
    }
  }

  Path _pathFor(_WireLayout layout, Size size) {
    final source = layout.source;
    final target = layout.target;
    final laneOffset = 28.0 + ((layout.index % 6) * 11.0);
    final laneX = math.min(
      size.width - 14,
      math.max(source.dx, target.dx) + laneOffset,
    );

    final path = Path()..moveTo(source.dx, source.dy);
    if ((source.dy - target.dy).abs() < 2) {
      final loopY = math.max(
        10.0,
        source.dy - 18 - (layout.index % 4) * 5,
      );
      path.cubicTo(
        source.dx + 18,
        loopY,
        target.dx + 18,
        loopY,
        target.dx,
        target.dy,
      );
      return path;
    }

    path.cubicTo(
      laneX,
      source.dy,
      laneX,
      target.dy,
      target.dx,
      target.dy,
    );
    return path;
  }

  void _drawArrow(Canvas canvas, _WireLayout layout, Paint paint) {
    final target = layout.target;
    final source = layout.source;
    final laneX = math.max(source.dx, target.dx) + 24;
    final incoming = Offset(target.dx - laneX, target.dy - target.dy);
    final fallback = target - source;
    final vector = incoming.distance > .1 ? incoming : fallback;
    final angle = math.atan2(vector.dy, vector.dx);
    const length = 7.0;
    const spread = .55;
    final p1 = Offset(
      target.dx - length * math.cos(angle - spread),
      target.dy - length * math.sin(angle - spread),
    );
    final p2 = Offset(
      target.dx - length * math.cos(angle + spread),
      target.dy - length * math.sin(angle + spread),
    );
    final arrow = Path()
      ..moveTo(target.dx, target.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(arrow, paint);
  }

  void _drawLabel(Canvas canvas, _WireLayout layout, Size size) {
    final text = '${layout.relationship.kind.label} · ${layout.relationship.description}';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xffe6edf7),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.min(300, size.width * .52));

    final midpoint = Offset(
      (layout.source.dx + layout.target.dx) / 2,
      (layout.source.dy + layout.target.dy) / 2,
    );
    final left = (midpoint.dx + 8)
        .clamp(6, size.width - painter.width - 12)
        .toDouble();
    final top = (midpoint.dy - painter.height - 6)
        .clamp(6, size.height - painter.height - 8)
        .toDouble();
    final rect = Rect.fromLTWH(
      left - 5,
      top - 3,
      painter.width + 10,
      painter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xff1d2430).withValues(alpha: .96),
    );
    painter.paint(canvas, Offset(left, top));
  }

  Color _colorFor(CodeRelationshipKind kind) => switch (kind) {
        CodeRelationshipKind.call => const Color(0xff58a6ff),
        CodeRelationshipKind.recursion => const Color(0xffc084fc),
        CodeRelationshipKind.callback => const Color(0xff22d3ee),
        CodeRelationshipKind.constructor => const Color(0xfffb923c),
        CodeRelationshipKind.getterRead => const Color(0xff4ade80),
        CodeRelationshipKind.setterWrite => const Color(0xfff87171),
        CodeRelationshipKind.variableRead => const Color(0xff2dd4bf),
        CodeRelationshipKind.variableWrite => const Color(0xfffbbf24),
        CodeRelationshipKind.parameterFlow => const Color(0xfff472b6),
        CodeRelationshipKind.returnFlow => const Color(0xff818cf8),
        CodeRelationshipKind.overrideImplementation => const Color(0xff94a3b8),
      };

  @override
  bool shouldRepaint(covariant _RelationshipWirePainter oldDelegate) =>
      oldDelegate.layouts != layouts ||
      oldDelegate.highlightedIndex != highlightedIndex;
}
