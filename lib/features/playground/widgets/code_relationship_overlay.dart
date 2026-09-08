import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/single_file_code_relationship_analyzer.dart';

class CodeRelationshipOverlay extends StatelessWidget {
  const CodeRelationshipOverlay({
    super.key,
    required this.relationships,
    required this.activeRelationshipIndexes,
    required this.focusLine,
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

  static const _maxFocusedWires = 6;
  static const _maxFallbackWires = 4;
  static const _laneRightInset = 30.0;
  static const _laneSpacing = 24.0;
  static const _tokenGap = 7.0;

  final List<CodeRelationship> relationships;
  final Set<int> activeRelationshipIndexes;
  final int focusLine;
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
        final selected = _selectRelationships(size);
        final layouts = <_WireLayout>[];

        for (var laneIndex = 0; laneIndex < selected.length; laneIndex++) {
          final item = selected[laneIndex];
          layouts.add(
            _layoutFor(
              relationship: item.relationship,
              relationshipIndex: item.index,
              laneIndex: laneIndex,
              active: item.active,
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
              if (layout.sourceDockVisible)
                _EndpointHitTarget(
                  point: layout.sourceDock,
                  tooltip: '${layout.relationship.kind.label}: '
                      '${layout.relationship.description}\n点击跳到另一端',
                  onEnter: () => onHoverRelationship(layout.index),
                  onExit: () => onHoverRelationship(null),
                  onTap: () => onJumpTo(layout.relationship.target),
                ),
              if (layout.targetDockVisible)
                _EndpointHitTarget(
                  point: layout.targetDock,
                  tooltip: '${layout.relationship.kind.label}: '
                      '${layout.relationship.description}\n点击跳到另一端',
                  onEnter: () => onHoverRelationship(layout.index),
                  onExit: () => onHoverRelationship(null),
                  onTap: () => onJumpTo(layout.relationship.source),
                ),
            ],
            Positioned(
              top: 6,
              right: 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff111318).withValues(alpha: .92),
                    border: Border.all(
                      color: const Color(0xff334155).withValues(alpha: .8),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    child: Text(
                      '⚡ ${layouts.length} / ${relationships.length}',
                      key: const ValueKey('code-relationship-count'),
                      style: const TextStyle(
                        color: Color(0xffaab4c3),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
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

  List<_IndexedRelationship> _selectRelationships(Size size) {
    final focused = <_IndexedRelationship>[];
    final fallback = <_IndexedRelationship>[];

    for (var index = 0; index < relationships.length; index++) {
      final relationship = relationships[index];
      final sourceY = _yFor(relationship.source);
      final targetY = _yFor(relationship.target);
      final sourceVisible = _isVerticallyVisible(sourceY, size);
      final targetVisible = _isVerticallyVisible(targetY, size);
      final crossesViewport = !_bothOutsideSameSide(sourceY, targetY, size);
      final active = activeRelationshipIndexes.contains(index);

      final item = _IndexedRelationship(
        index: index,
        relationship: relationship,
        active: active,
      );

      if (active && crossesViewport) {
        focused.add(item);
      } else if (activeRelationshipIndexes.isEmpty &&
          (sourceVisible || targetVisible)) {
        fallback.add(item);
      }
    }

    final selected = focused.isNotEmpty ? focused : fallback;
    selected.sort(_compareRelationshipPriority);
    final maxCount = focused.isNotEmpty ? _maxFocusedWires : _maxFallbackWires;
    if (selected.length > maxCount) {
      return selected.take(maxCount).toList(growable: false);
    }
    return selected;
  }

  int _compareRelationshipPriority(
    _IndexedRelationship a,
    _IndexedRelationship b,
  ) {
    final kindOrder = _kindPriority(a.relationship.kind).compareTo(
      _kindPriority(b.relationship.kind),
    );
    if (kindOrder != 0) return kindOrder;

    final aDistance = _distanceToFocus(a.relationship);
    final bDistance = _distanceToFocus(b.relationship);
    final distanceOrder = aDistance.compareTo(bDistance);
    if (distanceOrder != 0) return distanceOrder;

    return a.index.compareTo(b.index);
  }

  int _kindPriority(CodeRelationshipKind kind) => switch (kind) {
        CodeRelationshipKind.call ||
        CodeRelationshipKind.recursion ||
        CodeRelationshipKind.callback ||
        CodeRelationshipKind.constructor => 0,
        CodeRelationshipKind.getterRead ||
        CodeRelationshipKind.setterWrite ||
        CodeRelationshipKind.overrideImplementation => 1,
        CodeRelationshipKind.parameterFlow ||
        CodeRelationshipKind.returnFlow => 2,
        CodeRelationshipKind.variableRead ||
        CodeRelationshipKind.variableWrite => 3,
      };

  int _distanceToFocus(CodeRelationship relationship) {
    return math.min(
      (relationship.source.line - focusLine).abs(),
      (relationship.target.line - focusLine).abs(),
    );
  }

  _WireLayout _layoutFor({
    required CodeRelationship relationship,
    required int relationshipIndex,
    required int laneIndex,
    required bool active,
    required Size size,
  }) {
    final rawSourceY = _yFor(relationship.source);
    final rawTargetY = _yFor(relationship.target);

    // Lanes live inside the editor, immediately to the left of its scrollbar.
    // Each selected relationship gets a separate lane with a generous gap.
    final rightMostLane = math.max(
      codeOriginX + 48,
      size.width - _laneRightInset,
    );
    final laneX = math.max(
      codeOriginX + 24,
      rightMostLane - (laneIndex * _laneSpacing),
    );

    final source = Offset(
      laneX,
      rawSourceY.clamp(0, size.height).toDouble(),
    );
    final target = Offset(
      laneX,
      rawTargetY.clamp(0, size.height).toDouble(),
    );

    final rawSourceDockX = _dockXFor(relationship.source);
    final rawTargetDockX = _dockXFor(relationship.target);
    final sourceDockX = math.min(rawSourceDockX, laneX - 10);
    final targetDockX = math.min(rawTargetDockX, laneX - 10);

    final sourceDock = Offset(sourceDockX, source.dy);
    final targetDock = Offset(targetDockX, target.dy);
    final sourceDockVisible = _isAnchorVisible(
      x: rawSourceDockX,
      y: rawSourceY,
      laneX: laneX,
      size: size,
    );
    final targetDockVisible = _isAnchorVisible(
      x: rawTargetDockX,
      y: rawTargetY,
      laneX: laneX,
      size: size,
    );

    return _WireLayout(
      relationship: relationship,
      index: relationshipIndex,
      source: source,
      target: target,
      sourceDock: sourceDock,
      targetDock: targetDock,
      active: active,
      sourceDockVisible: sourceDockVisible,
      targetDockVisible: targetDockVisible,
      bothOutsideSameSide: _bothOutsideSameSide(
        rawSourceY,
        rawTargetY,
        size,
      ),
    );
  }

  double _dockXFor(CodeRelationshipAnchor anchor) {
    final tokenEndColumn = (anchor.column - 1) + anchor.length;
    return codeOriginX +
        (tokenEndColumn * charWidth) -
        horizontalScrollOffset +
        _tokenGap;
  }

  double _yFor(CodeRelationshipAnchor anchor) {
    return verticalPadding +
        ((anchor.line - 1) * lineHeight) +
        (lineHeight / 2) -
        verticalScrollOffset;
  }

  bool _isVerticallyVisible(double y, Size size) => y >= 0 && y <= size.height;

  bool _isAnchorVisible({
    required double x,
    required double y,
    required double laneX,
    required Size size,
  }) {
    return _isVerticallyVisible(y, size) &&
        x >= codeOriginX - charWidth &&
        x <= laneX - 8;
  }

  bool _bothOutsideSameSide(double a, double b, Size size) {
    if (a < 0 && b < 0) return true;
    if (a > size.height && b > size.height) return true;
    return false;
  }
}

class _IndexedRelationship {
  const _IndexedRelationship({
    required this.index,
    required this.relationship,
    required this.active,
  });

  final int index;
  final CodeRelationship relationship;
  final bool active;
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
    required this.sourceDock,
    required this.targetDock,
    required this.active,
    required this.sourceDockVisible,
    required this.targetDockVisible,
    required this.bothOutsideSameSide,
  });

  final CodeRelationship relationship;
  final int index;
  final Offset source;
  final Offset target;
  final Offset sourceDock;
  final Offset targetDock;
  final bool active;
  final bool sourceDockVisible;
  final bool targetDockVisible;
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
      final baseColor = _colorFor(layout.relationship.kind);
      final coreColor = baseColor.withValues(
        alpha: highlighted
            ? .98
            : hasHighlight
                ? .2
                : layout.active
                    ? .78
                    : .34,
      );
      final glowColor = baseColor.withValues(
        alpha: highlighted
            ? .25
            : layout.active
                ? .09
                : .0,
      );

      final path = _pathFor(layout);

      if (glowColor.a > 0) {
        final glowPaint = Paint()
          ..color = glowColor
          ..strokeWidth = highlighted ? 9 : 6.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter;
        canvas.drawPath(path, glowPaint);
      }

      final wirePaint = Paint()
        ..color = coreColor
        ..strokeWidth = highlighted
            ? 3.8
            : layout.active
                ? 2.6
                : 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter;
      canvas.drawPath(path, wirePaint);

      final markerPaint = Paint()
        ..color = coreColor
        ..style = PaintingStyle.fill;

      if (layout.sourceDockVisible) {
        _drawSourceMarker(canvas, layout, markerPaint, highlighted);
      }

      // The arrow is drawn only at the real target token. If that token is
      // outside the viewport, the visible wire simply continues off-screen.
      if (layout.targetDockVisible) {
        _drawCodeFacingArrow(canvas, layout, markerPaint, highlighted);
      }
    }
  }

  Path _pathFor(_WireLayout layout) {
    final path = Path();

    if (layout.sourceDockVisible) {
      path
        ..moveTo(layout.sourceDock.dx, layout.sourceDock.dy)
        ..lineTo(layout.source.dx, layout.source.dy);
    }

    path
      ..moveTo(layout.source.dx, layout.source.dy)
      ..lineTo(layout.target.dx, layout.target.dy);

    if (layout.targetDockVisible) {
      path.lineTo(layout.targetDock.dx, layout.targetDock.dy);
    }

    return path;
  }

  void _drawSourceMarker(
    Canvas canvas,
    _WireLayout layout,
    Paint paint,
    bool highlighted,
  ) {
    final size = highlighted ? 5.5 : 4.2;
    canvas.drawRect(
      Rect.fromCenter(
        center: layout.sourceDock,
        width: size,
        height: size,
      ),
      paint,
    );
  }

  void _drawCodeFacingArrow(
    Canvas canvas,
    _WireLayout layout,
    Paint paint,
    bool highlighted,
  ) {
    final target = layout.targetDock;
    final length = highlighted ? 10.0 : 8.0;
    final halfHeight = highlighted ? 5.5 : 4.5;

    final arrow = Path()
      ..moveTo(target.dx, target.dy)
      ..lineTo(target.dx + length, target.dy - halfHeight)
      ..lineTo(target.dx + length, target.dy + halfHeight)
      ..close();
    canvas.drawPath(arrow, paint);
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
