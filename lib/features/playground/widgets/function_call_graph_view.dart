import 'package:flutter/material.dart';

import '../services/dart_code_flow_analyzer.dart';

enum FunctionCallGraphDirection { outgoing, incoming }

/// Visual function-call graph.
///
/// The endpoint semantics never change:
/// - the solid dot is always the caller (the function that starts the call),
/// - the arrowhead always points at the callee (the function being called).
///
/// Incoming mode only changes which declaration is used as the visual root;
/// it does not reverse the meaning of a call.
class FunctionCallGraphView extends StatelessWidget {
  const FunctionCallGraphView({
    super.key,
    required this.root,
    required this.direction,
    required this.onNodeTap,
  });

  final CodeFlowNode root;
  final FunctionCallGraphDirection direction;
  final ValueChanged<CodeFlowNode> onNodeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = _FunctionGraphLayout.build(root);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CallEdgeLegend(),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRect(
            child: InteractiveViewer(
              key: const ValueKey('function-call-graph-viewport'),
              constrained: false,
              boundaryMargin: const EdgeInsets.all(80),
              minScale: 0.55,
              maxScale: 2.0,
              child: SizedBox(
                width: layout.width,
                height: layout.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final node in layout.nodes)
                      Positioned.fromRect(
                        rect: node.rect,
                        child: _FunctionNodeCard(
                          key: ValueKey('function-call-node-${node.id}'),
                          node: node.node,
                          isRoot: node.id == 0,
                          onTap: () => onNodeTap(node.node),
                        ),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('function-call-edge-layer'),
                          painter: _FunctionCallEdgePainter(
                            edges: layout.edges,
                            direction: direction,
                            lineColor: theme.colorScheme.primary,
                            labelColor: theme.colorScheme.onSurfaceVariant,
                            labelSurface: theme.colorScheme.surface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallEdgeLegend extends StatelessWidget {
  const _CallEdgeLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('function-call-edge-legend'),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _LegendItem(
            icon: Icons.circle,
            iconSize: 9,
            label: '调用者：圆点发出调用',
            color: theme.colorScheme.primary,
          ),
          _LegendItem(
            icon: Icons.arrow_right_alt,
            iconSize: 20,
            label: '被调用者：箭头指向这里',
            color: theme.colorScheme.primary,
          ),
          Text(
            '调用 → 被调用',
            key: const ValueKey('function-call-direction-meaning'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _FunctionNodeCard extends StatelessWidget {
  const _FunctionNodeCard({
    super.key,
    required this.node,
    required this.isRoot,
    required this.onTap,
  });

  final CodeFlowNode node;
  final bool isRoot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: isRoot ? 2 : 0,
      color: isRoot
          ? theme.colorScheme.primaryContainer.withOpacity(0.55)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: node.isCycle
              ? theme.colorScheme.tertiary
              : isRoot
                  ? theme.colorScheme.primary.withOpacity(0.65)
                  : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    node.isCycle ? Icons.replay_outlined : Icons.functions,
                    size: 16,
                    color: node.isCycle
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isRoot)
                    Text(
                      '当前',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${node.location.filePath}:${node.location.line}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FunctionGraphLayout {
  const _FunctionGraphLayout({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  static const double nodeWidth = 220;
  static const double nodeHeight = 72;
  static const double horizontalGap = 132;
  static const double verticalGap = 34;
  static const double padding = 28;

  final List<_PositionedFunctionNode> nodes;
  final List<_HierarchyEdge> edges;
  final double width;
  final double height;

  factory _FunctionGraphLayout.build(CodeFlowNode root) {
    final builder = _FunctionGraphLayoutBuilder();
    final layoutRoot = builder.layout(root, 0);
    final nodes = <_PositionedFunctionNode>[];
    final edges = <_HierarchyEdge>[];
    var maxDepth = 0;

    void collect(_PositionedFunctionNode node) {
      nodes.add(node);
      if (node.depth > maxDepth) maxDepth = node.depth;
      for (final child in node.children) {
        edges.add(_HierarchyEdge(parent: node, child: child));
        collect(child);
      }
    }

    collect(layoutRoot);

    final width = padding * 2 +
        (maxDepth + 1) * nodeWidth +
        maxDepth * horizontalGap;
    final contentBottom = nodes.fold<double>(
      0,
      (current, node) => node.rect.bottom > current ? node.rect.bottom : current,
    );
    final height = contentBottom + padding;

    return _FunctionGraphLayout(
      nodes: nodes,
      edges: edges,
      width: width,
      height: height,
    );
  }
}

class _FunctionGraphLayoutBuilder {
  var _nextId = 0;
  var _nextLeafY = _FunctionGraphLayout.padding;

  _PositionedFunctionNode layout(CodeFlowNode node, int depth) {
    final id = _nextId++;
    final children = <_PositionedFunctionNode>[];
    for (final child in node.children) {
      children.add(layout(child, depth + 1));
    }

    final double y;
    if (children.isEmpty) {
      y = _nextLeafY;
      _nextLeafY +=
          _FunctionGraphLayout.nodeHeight + _FunctionGraphLayout.verticalGap;
    } else {
      final firstCenter = children.first.rect.center.dy;
      final lastCenter = children.last.rect.center.dy;
      y = (firstCenter + lastCenter) / 2 -
          _FunctionGraphLayout.nodeHeight / 2;
    }

    final x = _FunctionGraphLayout.padding +
        depth *
            (_FunctionGraphLayout.nodeWidth +
                _FunctionGraphLayout.horizontalGap);

    return _PositionedFunctionNode(
      id: id,
      node: node,
      depth: depth,
      rect: Rect.fromLTWH(
        x,
        y,
        _FunctionGraphLayout.nodeWidth,
        _FunctionGraphLayout.nodeHeight,
      ),
      children: children,
    );
  }
}

class _PositionedFunctionNode {
  const _PositionedFunctionNode({
    required this.id,
    required this.node,
    required this.depth,
    required this.rect,
    required this.children,
  });

  final int id;
  final CodeFlowNode node;
  final int depth;
  final Rect rect;
  final List<_PositionedFunctionNode> children;
}

class _HierarchyEdge {
  const _HierarchyEdge({required this.parent, required this.child});

  final _PositionedFunctionNode parent;
  final _PositionedFunctionNode child;
}

class _FunctionCallEdgePainter extends CustomPainter {
  const _FunctionCallEdgePainter({
    required this.edges,
    required this.direction,
    required this.lineColor,
    required this.labelColor,
    required this.labelSurface,
  });

  final List<_HierarchyEdge> edges;
  final FunctionCallGraphDirection direction;
  final Color lineColor;
  final Color labelColor;
  final Color labelSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = lineColor.withOpacity(0.78)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final marker = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (final hierarchyEdge in edges) {
      final caller = direction == FunctionCallGraphDirection.outgoing
          ? hierarchyEdge.parent
          : hierarchyEdge.child;
      final callee = direction == FunctionCallGraphDirection.outgoing
          ? hierarchyEdge.child
          : hierarchyEdge.parent;

      final callerIsLeft = caller.rect.center.dx < callee.rect.center.dx;
      final start = callerIsLeft
          ? caller.rect.centerRight
          : caller.rect.centerLeft;
      final end = callerIsLeft
          ? callee.rect.centerLeft
          : callee.rect.centerRight;
      final controlDistance = (end.dx - start.dx).abs() * 0.48;
      final firstControl = Offset(
        start.dx + (callerIsLeft ? controlDistance : -controlDistance),
        start.dy,
      );
      final secondControl = Offset(
        end.dx + (callerIsLeft ? -controlDistance : controlDistance),
        end.dy,
      );

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          firstControl.dx,
          firstControl.dy,
          secondControl.dx,
          secondControl.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, stroke);

      // Caller endpoint: a solid dot means this function starts the call.
      canvas.drawCircle(start, 5, marker);

      // Callee endpoint: the arrowhead always points at the function being
      // called, including when incoming mode makes the call travel right->left.
      final arrow = Path();
      if (callerIsLeft) {
        arrow
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx - 11, end.dy - 6.5)
          ..lineTo(end.dx - 11, end.dy + 6.5)
          ..close();
      } else {
        arrow
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx + 11, end.dy - 6.5)
          ..lineTo(end.dx + 11, end.dy + 6.5)
          ..close();
      }
      canvas.drawPath(arrow, marker);

      _paintEndpointLabel(
        canvas,
        text: '调用',
        anchor: start,
        callerIsLeft: callerIsLeft,
        isCaller: true,
      );
      _paintEndpointLabel(
        canvas,
        text: '被调用',
        anchor: end,
        callerIsLeft: callerIsLeft,
        isCaller: false,
      );
    }
  }

  void _paintEndpointLabel(
    Canvas canvas, {
    required String text,
    required Offset anchor,
    required bool callerIsLeft,
    required bool isCaller,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final moveRight = isCaller ? callerIsLeft : !callerIsLeft;
    final dx = moveRight
        ? anchor.dx + 10
        : anchor.dx - textPainter.width - 10;
    final dy = isCaller
        ? anchor.dy - textPainter.height - 7
        : anchor.dy + 7;
    final textOffset = Offset(dx, dy);
    final background = Rect.fromLTWH(
      textOffset.dx - 4,
      textOffset.dy - 2,
      textPainter.width + 8,
      textPainter.height + 4,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(5)),
      Paint()..color = labelSurface.withOpacity(0.94),
    );
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _FunctionCallEdgePainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.direction != direction ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.labelSurface != labelSurface;
}
