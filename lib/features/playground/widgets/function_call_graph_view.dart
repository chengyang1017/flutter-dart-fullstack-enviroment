import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../controllers/concept_label_controller.dart';
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
class FunctionCallGraphView extends StatefulWidget {
  const FunctionCallGraphView({
    super.key,
    required this.root,
    required this.direction,
    required this.onNodeTap,
    this.labels,
    this.labelModeEnabled = false,
  });

  final CodeFlowNode root;
  final FunctionCallGraphDirection direction;
  final ValueChanged<CodeFlowNode> onNodeTap;
  final ConceptLabelController? labels;
  final bool labelModeEnabled;

  @override
  State<FunctionCallGraphView> createState() => _FunctionCallGraphViewState();
}

class _FunctionCallGraphViewState extends State<FunctionCallGraphView> {
  static const double _minScale = 0.20;
  static const double _maxScale = 4.0;
  static const double _zoomStep = 1.16;

  final TransformationController _transformController =
      TransformationController();

  Size _viewportSize = Size.zero;
  Size _contentSize = Size.zero;
  bool _fitScheduled = false;
  bool _didInitialFit = false;
  final Set<String> _expandedNodeKeys = <String>{};
  final Set<String> _sourceHoverKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _attachLabels(widget.labels);
  }

  @override
  void dispose() {
    _detachLabels(widget.labels);
    _transformController.dispose();
    super.dispose();
  }

  void _attachLabels(ConceptLabelController? labels) {
    labels?.addListener(_handleLabelsChanged);
  }

  void _detachLabels(ConceptLabelController? labels) {
    labels?.removeListener(_handleLabelsChanged);
  }

  void _handleLabelsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant FunctionCallGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.labels, widget.labels)) {
      _detachLabels(oldWidget.labels);
      _attachLabels(widget.labels);
    }

    final oldLocation = oldWidget.root.location;
    final newLocation = widget.root.location;
    final rootChanged = oldLocation.filePath != newLocation.filePath ||
        oldLocation.line != newLocation.line;

    if (rootChanged || oldWidget.direction != widget.direction) {
      _expandedNodeKeys.clear();
      _sourceHoverKeys.clear();
      _scheduleFit();
    }
  }

  void _setSourceHovered(CodeFlowNode node, bool hovered) {
    final key = _functionNodeIdentity(node);
    setState(() {
      if (hovered) {
        _sourceHoverKeys.add(key);
      } else {
        _sourceHoverKeys.remove(key);
      }
    });
  }

  void _scheduleFit() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (!mounted) return;
      _fitContent();
    });
  }

  double get _currentScale => _transformController.value.getMaxScaleOnAxis();

  void _setMatrix(double scale, Offset translation) {
    final clamped = scale.clamp(_minScale, _maxScale).toDouble();
    _transformController.value = Matrix4.identity()
      ..translate(translation.dx, translation.dy)
      ..scale(clamped);
  }

  void _setCenteredScale(double scale) {
    if (_viewportSize.isEmpty || _contentSize.isEmpty) return;
    final clamped = scale.clamp(_minScale, _maxScale).toDouble();
    final translation = Offset(
      (_viewportSize.width - _contentSize.width * clamped) / 2,
      (_viewportSize.height - _contentSize.height * clamped) / 2,
    );
    _setMatrix(clamped, translation);
  }

  void _fitContent() {
    if (_viewportSize.isEmpty || _contentSize.isEmpty) return;

    const padding = 32.0;
    final usableWidth = (_viewportSize.width - padding * 2)
        .clamp(1.0, double.infinity)
        .toDouble();
    final usableHeight = (_viewportSize.height - padding * 2)
        .clamp(1.0, double.infinity)
        .toDouble();
    final fitScale = math
        .min(
          usableWidth / _contentSize.width,
          usableHeight / _contentSize.height,
        )
        .toDouble();

    _setCenteredScale(fitScale);
  }

  void _actualSize() => _setCenteredScale(1.0);

  void _zoomBy(double factor) {
    if (_viewportSize.isEmpty) return;

    final focal = Offset(
      _viewportSize.width / 2,
      _viewportSize.height / 2,
    );
    final scenePoint = _transformController.toScene(focal);
    final nextScale =
        (_currentScale * factor).clamp(_minScale, _maxScale).toDouble();
    final translation = Offset(
      focal.dx - scenePoint.dx * nextScale,
      focal.dy - scenePoint.dy * nextScale,
    );
    _setMatrix(nextScale, translation);
  }

  void _toggleNode(CodeFlowNode node) {
    final key = _functionNodeIdentity(node);
    setState(() {
      if (!_expandedNodeKeys.add(key)) {
        _expandedNodeKeys.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = _FunctionGraphLayout.build(
      widget.root,
      expandedNodeKeys: _expandedNodeKeys,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              _contentSize = Size(layout.width, layout.height);

              if (!_didInitialFit &&
                  !_viewportSize.isEmpty &&
                  !_contentSize.isEmpty) {
                _didInitialFit = true;
                _scheduleFit();
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: InteractiveViewer(
                      key: const ValueKey('function-call-graph-viewport'),
                      transformationController: _transformController,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(1200),
                      minScale: _minScale,
                      maxScale: _maxScale,
                      scaleEnabled: _sourceHoverKeys.isEmpty,
                      scaleFactor: 420,
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
                                  key: ValueKey(
                                    'function-call-node-${node.id}',
                                  ),
                                  node: node.node,
                                  isRoot: node.id == 0,
                                  expanded: _expandedNodeKeys.contains(
                                    _functionNodeIdentity(node.node),
                                  ),
                                  onToggle: () => _toggleNode(node.node),
                                  onOpenSource: () =>
                                      widget.onNodeTap(node.node),
                                  labels: widget.labels,
                                  labelModeEnabled: widget.labelModeEnabled,
                                  onSourceHoverChanged: (hovered) =>
                                      _setSourceHovered(node.node, hovered),
                                ),
                              ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  key: const ValueKey(
                                    'function-call-edge-layer',
                                  ),
                                  painter: _FunctionCallEdgePainter(
                                    edges: layout.edges,
                                    direction: widget.direction,
                                    lineColor: theme.colorScheme.primary,
                                    labelColor:
                                        theme.colorScheme.onSurfaceVariant,
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
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _GraphZoomToolbar(
                      controller: _transformController,
                      onZoomOut: () => _zoomBy(1 / _zoomStep),
                      onZoomIn: () => _zoomBy(_zoomStep),
                      onActualSize: _actualSize,
                      onFit: _fitContent,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GraphZoomToolbar extends StatelessWidget {
  const _GraphZoomToolbar({
    required this.controller,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onActualSize,
    required this.onFit,
  });

  final TransformationController controller;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onActualSize;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow.withOpacity(0.96),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GraphZoomButton(
              tooltip: '缩小',
              icon: Icons.remove_rounded,
              onPressed: onZoomOut,
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final percent =
                    (controller.value.getMaxScaleOnAxis() * 100).round();
                return SizedBox(
                  width: 48,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
            _GraphZoomButton(
              tooltip: '放大',
              icon: Icons.add_rounded,
              onPressed: onZoomIn,
            ),
            const SizedBox(
              height: 18,
              child: VerticalDivider(width: 1),
            ),
            Tooltip(
              message: '实际大小 100%',
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(42, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onActualSize,
                child: const Text('1:1'),
              ),
            ),
            _GraphZoomButton(
              tooltip: '适合窗口',
              icon: Icons.fit_screen_rounded,
              onPressed: onFit,
            ),
            const SizedBox(
              height: 18,
              child: VerticalDivider(width: 1),
            ),
            PopupMenuButton<void>(
              tooltip: '电线说明',
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  enabled: false,
                  child: _LegendItem(
                    icon: Icons.circle,
                    iconSize: 9,
                    label: '调用者：圆点发出调用',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                PopupMenuItem<void>(
                  enabled: false,
                  child: _LegendItem(
                    icon: Icons.arrow_right_alt,
                    iconSize: 20,
                    label: '被调用者：箭头指向这里',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                PopupMenuItem<void>(
                  enabled: false,
                  child: _LegendItem(
                    icon: Icons.more_horiz_rounded,
                    iconSize: 20,
                    label: '虚线：应用 ↔ 后端',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphZoomButton extends StatelessWidget {
  const _GraphZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
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

String _functionNodeIdentity(CodeFlowNode node) =>
    '${node.location.filePath}:${node.location.line}:${node.location.column}:'
    '${node.displayName}';

bool _crossesApplicationBackendBoundary(
  CodeFlowNode first,
  CodeFlowNode second,
) {
  if (first.isBackend != second.isBackend) {
    return true;
  }

  final firstPath = first.location.filePath;
  final secondPath = second.location.filePath;
  return (_isAppSourcePath(firstPath) && _isBackendSourcePath(secondPath)) ||
      (_isBackendSourcePath(firstPath) && _isAppSourcePath(secondPath));
}

bool _isAppSourcePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (_isBackendSourcePath(normalized)) return false;
  return normalized == 'lib' ||
      normalized.startsWith('lib/') ||
      (normalized.startsWith('apps/') && normalized.contains('/lib/')) ||
      normalized.contains('_app/lib/');
}

bool _isBackendSourcePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized == 'backend' ||
      normalized.startsWith('backend/') ||
      normalized.startsWith('server/') ||
      normalized.contains('/server/') ||
      normalized.contains('_server/lib/');
}

Future<void> _showFunctionNodeNameDialog(
  BuildContext context,
  CodeFlowNode node,
  ConceptLabelController labels,
) async {
  final existing = labels.nodeNameRuleFor(
    path: node.location.filePath,
    originalName: node.displayName,
    lineNumber: node.location.line,
    sourceCode: node.sourceCode,
  );
  final nameController = TextEditingController(text: existing?.label ?? '');
  String? errorText;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('给这个容器取名字'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '原函数：${node.displayName}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '名字只属于这个函数容器；函数移动或内部代码变化后会继续智能跟随。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '容器名称',
                      hintText: '例如：获取商品',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    await labels.removeRule(existing.id);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(false);
                    }
                  },
                  child: const Text('恢复原名'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) {
                    setDialogState(() => errorText = '名称不能为空');
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  if (saved == true) {
    await labels.setNodeName(
      path: node.location.filePath,
      originalName: node.displayName,
      lineNumber: node.location.line,
      sourceCode: node.sourceCode,
      name: nameController.text,
    );
  }
  nameController.dispose();
}

class _FunctionNodeCard extends StatelessWidget {
  const _FunctionNodeCard({
    super.key,
    required this.node,
    required this.isRoot,
    required this.expanded,
    required this.onToggle,
    required this.onOpenSource,
    required this.labels,
    required this.labelModeEnabled,
    required this.onSourceHoverChanged,
  });

  final CodeFlowNode node;
  final bool isRoot;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenSource;
  final ConceptLabelController? labels;
  final bool labelModeEnabled;
  final ValueChanged<bool> onSourceHoverChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final customName = labels?.nodeNameFor(
      path: node.location.filePath,
      originalName: node.displayName,
      lineNumber: node.location.line,
      sourceCode: node.sourceCode,
    );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        child: Tooltip(
                          message: customName == null
                              ? node.displayName
                              : '$customName\n${node.displayName}',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customName ?? node.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (customName != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  node.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: muted,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (labels != null)
                        IconButton(
                          tooltip: customName == null ? '给容器取名字' : '修改容器名称',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          onPressed: () => _showFunctionNodeNameDialog(
                            context,
                            node,
                            labels!,
                          ),
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                        ),
                      if (isRoot) ...[
                        Text(
                          '当前',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${node.location.filePath}:${node.location.line}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Workspace 原始源码',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                        ),
                        onPressed: onOpenSource,
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        label: const Text('打开源码'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _FunctionSourceViewport(
                    node: node,
                    labels: labels,
                    labelModeEnabled: labelModeEnabled,
                    onHoverChanged: onSourceHoverChanged,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FunctionSourceViewport extends StatefulWidget {
  const _FunctionSourceViewport({
    required this.node,
    required this.labels,
    required this.labelModeEnabled,
    required this.onHoverChanged,
  });

  final CodeFlowNode node;
  final ConceptLabelController? labels;
  final bool labelModeEnabled;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_FunctionSourceViewport> createState() =>
      _FunctionSourceViewportState();
}

class _WireLabelSelection {
  const _WireLabelSelection({
    required this.globalLine,
    required this.startColumn,
    required this.endColumn,
    required this.source,
  });

  final int globalLine;
  final int startColumn;
  final int endColumn;
  final String source;
}

class _FunctionSourceViewportState extends State<_FunctionSourceViewport> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  TextSelection? _selection;

  @override
  void didUpdateWidget(covariant _FunctionSourceViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.location.filePath != widget.node.location.filePath ||
        oldWidget.node.location.line != widget.node.location.line ||
        oldWidget.node.sourceCode != widget.node.sourceCode ||
        oldWidget.labelModeEnabled != widget.labelModeEnabled) {
      _selection = null;
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  _WireLabelSelection? _selectedSource() {
    if (widget.labelModeEnabled) return null;

    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;

    final source = widget.node.sourceCode;
    final start = selection.start.clamp(0, source.length).toInt();
    final end = selection.end.clamp(start, source.length).toInt();
    if (end <= start) return null;

    final selected = source.substring(start, end);
    if (selected.trim().isEmpty || selected.contains('\n')) return null;

    final before = source.substring(0, start);
    final localLine = '\n'.allMatches(before).length;
    final lastBreak = before.lastIndexOf('\n');
    final lineStart = lastBreak < 0 ? 0 : lastBreak + 1;

    return _WireLabelSelection(
      globalLine: widget.node.sourceStartLine + localLine,
      startColumn: start - lineStart,
      endColumn: end - lineStart,
      source: selected,
    );
  }

  Future<void> _addSelectedLabel() async {
    final labels = widget.labels;
    final selected = _selectedSource();
    if (labels == null || selected == null) return;

    final labelController = TextEditingController();
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加位置标签'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.node.location.filePath}:${selected.globalLine} '
                      '· 第 ${selected.startColumn + 1}–${selected.endColumn} 列',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '只绑定这一处源码；上方增删行或函数移动后会智能重新定位。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '选中的源码',
                        border: OutlineInputBorder(),
                      ),
                      child: SelectableText(
                        selected.source,
                        maxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '显示成什么',
                        hintText: '例如：等待',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (labelController.text.trim().isEmpty) {
                      setDialogState(() => errorText = '标签不能为空');
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await labels.setPositionLabel(
        path: widget.node.location.filePath,
        sourceText: widget.node.sourceCode,
        lineNumber: selected.globalLine,
        startColumn: selected.startColumn,
        endColumn: selected.endColumn,
        label: labelController.text,
        wholeLine: false,
        baseLineNumber: widget.node.sourceStartLine,
      );
      if (mounted) {
        setState(() => _selection = null);
      }
    }

    labelController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontFamily: 'monospace',
      fontSize: 10.5,
      height: 1.45,
    );
    final selected = _selectedSource();
    final canAdd = widget.labels != null && selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) => widget.onHoverChanged(false),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                primary: false,
                padding: const EdgeInsets.all(10),
                child: Scrollbar(
                  controller: _horizontalController,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(
                      TextSpan(
                        style: sourceStyle,
                        children: _buildDisplayedSourceSpans(
                          node: widget.node,
                          labels: widget.labels,
                          labelModeEnabled: widget.labelModeEnabled,
                          theme: theme,
                        ),
                      ),
                      onSelectionChanged: (selection, cause) {
                        if (!mounted) return;
                        setState(() => _selection = selection);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 30,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.labelModeEnabled
                      ? '先关闭电线标签显示，再选择源码添加标签'
                      : selected == null
                          ? '选择同一行的一段源码即可添加标签'
                          : '已选择：${selected.source}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const ValueKey('wire-source-add-label'),
                onPressed: canAdd ? _addSelectedLabel : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.label_outline_rounded, size: 15),
                label: const Text('添加标签'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<InlineSpan> _buildDisplayedSourceSpans({
  required CodeFlowNode node,
  required ConceptLabelController? labels,
  required bool labelModeEnabled,
  required ThemeData theme,
}) {
  final source = node.sourceCode;
  final replacements = <_SourceReplacement>[];

  if (labelModeEnabled && labels != null) {
    final lineStarts = _lineStartOffsets(source);
    final resolved = labels.resolveLabelsForSource(
      path: node.location.filePath,
      sourceText: source,
      baseLineNumber: node.sourceStartLine,
    );

    for (final match in resolved) {
      final localLine = match.lineNumber - node.sourceStartLine;
      if (localLine < 0 || localLine >= lineStarts.length) continue;
      final start = lineStarts[localLine] + match.startColumn;
      final end = lineStarts[localLine] + match.endColumn;
      if (start < 0 || end <= start || end > source.length) continue;
      if (source.substring(start, end) != match.source) continue;
      replacements.add(
        _SourceReplacement(
          start: start,
          end: end,
          label: match.rule.label,
          lineScoped: match.lineScoped,
        ),
      );
    }
  }

  replacements.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return b.end.compareTo(a.end);
  });

  // Never let overlapping labels hide each other unpredictably. The first
  // resolved anchor wins; ambiguous anchors were already rejected upstream.
  final accepted = <_SourceReplacement>[];
  var occupiedUntil = -1;
  for (final replacement in replacements) {
    if (replacement.start < occupiedUntil) continue;
    accepted.add(replacement);
    occupiedUntil = replacement.end;
  }

  return _renderHighlightedDartSource(
    source: source,
    replacements: accepted,
    theme: theme,
  );
}

List<int> _lineStartOffsets(String source) {
  final result = <int>[0];
  for (var index = 0; index < source.length; index++) {
    if (source.codeUnitAt(index) == 10) result.add(index + 1);
  }
  return result;
}

List<InlineSpan> _renderHighlightedDartSource({
  required String source,
  required List<_SourceReplacement> replacements,
  required ThemeData theme,
}) {
  final tokens = _tokenizeDartSource(source);
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final replacement in replacements) {
    if (replacement.start > cursor) {
      spans.addAll(
        _highlightedRangeSpans(
          source: source,
          start: cursor,
          end: replacement.start,
          tokens: tokens,
          theme: theme,
        ),
      );
    }
    spans.add(
      _conceptLabelSpan(
        replacement.label,
        lineScoped: replacement.lineScoped,
      ),
    );
    cursor = replacement.end;
  }

  if (cursor < source.length) {
    spans.addAll(
      _highlightedRangeSpans(
        source: source,
        start: cursor,
        end: source.length,
        tokens: tokens,
        theme: theme,
      ),
    );
  }
  if (spans.isEmpty) spans.add(const TextSpan(text: ''));
  return spans;
}

List<InlineSpan> _highlightedRangeSpans({
  required String source,
  required int start,
  required int end,
  required List<_DartSyntaxToken> tokens,
  required ThemeData theme,
}) {
  final spans = <InlineSpan>[];
  var cursor = start;

  for (final token in tokens) {
    if (token.end <= start) continue;
    if (token.start >= end) break;

    final tokenStart = math.max(start, token.start);
    final tokenEnd = math.min(end, token.end);
    if (tokenStart > cursor) {
      spans.add(TextSpan(text: source.substring(cursor, tokenStart)));
    }
    if (tokenEnd > tokenStart) {
      spans.add(
        TextSpan(
          text: source.substring(tokenStart, tokenEnd),
          style: TextStyle(color: _syntaxColor(token.kind, theme)),
        ),
      );
      cursor = tokenEnd;
    }
  }

  if (cursor < end) {
    spans.add(TextSpan(text: source.substring(cursor, end)));
  }
  return spans;
}

Color _syntaxColor(_DartSyntaxKind kind, ThemeData theme) {
  switch (kind) {
    case _DartSyntaxKind.keyword:
      return const Color(0xffc792ea);
    case _DartSyntaxKind.string:
      return const Color(0xffc3e88d);
    case _DartSyntaxKind.comment:
      return theme.colorScheme.onSurfaceVariant.withOpacity(0.74);
    case _DartSyntaxKind.number:
      return const Color(0xfff78c6c);
    case _DartSyntaxKind.type:
      return const Color(0xffffcb6b);
  }
}

List<_DartSyntaxToken> _tokenizeDartSource(String source) {
  final tokens = <_DartSyntaxToken>[];
  var index = 0;

  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final start = index;
      final newline = source.indexOf('\n', index + 2);
      index = newline < 0 ? source.length : newline;
      tokens.add(
        _DartSyntaxToken(start, index, _DartSyntaxKind.comment),
      );
      continue;
    }

    if (source.startsWith('/*', index)) {
      final start = index;
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      tokens.add(
        _DartSyntaxToken(start, index, _DartSyntaxKind.comment),
      );
      continue;
    }

    final rawString =
        (source.codeUnitAt(index) == 114 || source.codeUnitAt(index) == 82) &&
            index + 1 < source.length &&
            (source.codeUnitAt(index + 1) == 39 ||
                source.codeUnitAt(index + 1) == 34);
    final current = source.codeUnitAt(index);
    if (rawString || current == 39 || current == 34) {
      final start = index;
      final raw = rawString;
      if (raw) index++;
      final quote = source.codeUnitAt(index);
      final triple = index + 2 < source.length &&
          source.codeUnitAt(index + 1) == quote &&
          source.codeUnitAt(index + 2) == quote;
      index += triple ? 3 : 1;

      while (index < source.length) {
        if (triple) {
          if (index + 2 < source.length &&
              source.codeUnitAt(index) == quote &&
              source.codeUnitAt(index + 1) == quote &&
              source.codeUnitAt(index + 2) == quote) {
            index += 3;
            break;
          }
        } else if (source.codeUnitAt(index) == quote) {
          index++;
          break;
        }

        if (!raw &&
            source.codeUnitAt(index) == 92 &&
            index + 1 < source.length) {
          index += 2;
        } else {
          index++;
        }
      }

      tokens.add(
        _DartSyntaxToken(start, index, _DartSyntaxKind.string),
      );
      continue;
    }

    if (_isDigit(current)) {
      final start = index;
      if (current == 48 &&
          index + 1 < source.length &&
          (source.codeUnitAt(index + 1) == 120 ||
              source.codeUnitAt(index + 1) == 88)) {
        index += 2;
        while (index < source.length &&
            _isHexDigitOrUnderscore(source.codeUnitAt(index))) {
          index++;
        }
      } else {
        index++;
        while (index < source.length &&
            _isNumberContinuation(source.codeUnitAt(index))) {
          index++;
        }
      }
      tokens.add(
        _DartSyntaxToken(start, index, _DartSyntaxKind.number),
      );
      continue;
    }

    if (_isIdentifierStart(current)) {
      final start = index++;
      while (index < source.length &&
          _isIdentifierPart(source.codeUnitAt(index))) {
        index++;
      }
      final word = source.substring(start, index);
      if (_dartKeywords.contains(word)) {
        tokens.add(
          _DartSyntaxToken(start, index, _DartSyntaxKind.keyword),
        );
      } else if (word.isNotEmpty &&
          word.codeUnitAt(0) >= 65 &&
          word.codeUnitAt(0) <= 90) {
        tokens.add(
          _DartSyntaxToken(start, index, _DartSyntaxKind.type),
        );
      }
      continue;
    }

    index++;
  }
  return tokens;
}

bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

bool _isHexDigitOrUnderscore(int codeUnit) =>
    _isDigit(codeUnit) ||
    (codeUnit >= 65 && codeUnit <= 70) ||
    (codeUnit >= 97 && codeUnit <= 102) ||
    codeUnit == 95;

bool _isNumberContinuation(int codeUnit) =>
    _isDigit(codeUnit) ||
    codeUnit == 95 ||
    codeUnit == 46 ||
    codeUnit == 101 ||
    codeUnit == 69 ||
    codeUnit == 43 ||
    codeUnit == 45;

bool _isIdentifierStart(int codeUnit) =>
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122) ||
    codeUnit == 95 ||
    codeUnit == 36;

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) || _isDigit(codeUnit);

const Set<String> _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

InlineSpan _conceptLabelSpan(
  String label, {
  required bool lineScoped,
}) {
  final background = lineScoped
      ? const Color(0xff53398e).withOpacity(0.88)
      : const Color(0xff1d567e).withOpacity(0.92);
  final foreground =
      lineScoped ? const Color(0xffeee7ff) : const Color(0xffdff3ff);

  return TextSpan(
    text: ' $label ',
    style: TextStyle(
      color: foreground,
      backgroundColor: background,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
      fontSize: 10.5,
      height: 1.45,
    ),
  );
}

class _SourceReplacement {
  const _SourceReplacement({
    required this.start,
    required this.end,
    required this.label,
    required this.lineScoped,
  });

  final int start;
  final int end;
  final String label;
  final bool lineScoped;
}

enum _DartSyntaxKind { keyword, string, comment, number, type }

class _DartSyntaxToken {
  const _DartSyntaxToken(this.start, this.end, this.kind);

  final int start;
  final int end;
  final _DartSyntaxKind kind;
}

class _FunctionGraphLayout {
  const _FunctionGraphLayout({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  static const double nodeWidth = 340;
  static const double expandedMinNodeWidth = 420;
  static const double expandedMaxNodeWidth = 760;
  static const double collapsedNodeHeight = 76;
  static const double expandedNodeHeight = 324;
  static const double nodeHeight = collapsedNodeHeight;
  static const double horizontalGap = 132;
  static const double verticalGap = 34;
  static const double padding = 28;

  final List<_PositionedFunctionNode> nodes;
  final List<_HierarchyEdge> edges;
  final double width;
  final double height;

  static double expandedWidthFor(CodeFlowNode node) {
    final painter = TextPainter(
      text: TextSpan(
        text: node.sourceCode.replaceAll('\t', '    '),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          height: 1.45,
        ),
      ),
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout();

    // 20 px for the source viewport's own horizontal padding,
    // 20 px for the expanded card padding, plus a little breathing room.
    final requested = painter.width + 48;
    painter.dispose();

    return requested
        .clamp(expandedMinNodeWidth, expandedMaxNodeWidth)
        .toDouble();
  }

  factory _FunctionGraphLayout.build(
    CodeFlowNode root, {
    required Set<String> expandedNodeKeys,
  }) {
    final builder = _ExpandableFunctionGraphLayoutBuilder(expandedNodeKeys);
    final measuredRoot = builder.measure(root, 0);
    final layoutRoot = builder.position(measuredRoot, padding);
    final nodes = <_PositionedFunctionNode>[];
    final edges = <_HierarchyEdge>[];

    void collect(_PositionedFunctionNode node) {
      nodes.add(node);
      for (final child in node.children) {
        edges.add(_HierarchyEdge(parent: node, child: child));
        collect(child);
      }
    }

    collect(layoutRoot);

    final contentRight = nodes.fold<double>(
      0,
      (current, node) => node.rect.right > current ? node.rect.right : current,
    );
    final width = contentRight + padding;
    final contentBottom = nodes.fold<double>(
      0,
      (current, node) =>
          node.rect.bottom > current ? node.rect.bottom : current,
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
      y = (firstCenter + lastCenter) / 2 - _FunctionGraphLayout.nodeHeight / 2;
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

class _ExpandableFunctionGraphLayoutBuilder {
  _ExpandableFunctionGraphLayoutBuilder(this.expandedNodeKeys);

  final Set<String> expandedNodeKeys;
  final Map<int, double> _columnWidths = <int, double>{};
  var _nextId = 0;

  _MeasuredFunctionNode measure(CodeFlowNode node, int depth) {
    final children = node.children
        .map((child) => measure(child, depth + 1))
        .toList(growable: false);
    final expanded = expandedNodeKeys.contains(_functionNodeIdentity(node));
    final nodeHeight = expanded
        ? _FunctionGraphLayout.expandedNodeHeight
        : _FunctionGraphLayout.collapsedNodeHeight;
    final nodeWidth = expanded
        ? _FunctionGraphLayout.expandedWidthFor(node)
        : _FunctionGraphLayout.nodeWidth;

    _columnWidths[depth] = math.max(
      _columnWidths[depth] ?? _FunctionGraphLayout.nodeWidth,
      nodeWidth,
    );

    final childrenHeight = children.isEmpty
        ? 0.0
        : children.fold<double>(
              0,
              (sum, child) => sum + child.subtreeHeight,
            ) +
            _FunctionGraphLayout.verticalGap * (children.length - 1);

    return _MeasuredFunctionNode(
      node: node,
      depth: depth,
      nodeWidth: nodeWidth,
      nodeHeight: nodeHeight,
      subtreeHeight: math.max(nodeHeight, childrenHeight).toDouble(),
      children: children,
    );
  }

  _PositionedFunctionNode position(
    _MeasuredFunctionNode measured,
    double top,
  ) {
    final id = _nextId++;
    final totalChildrenHeight = measured.children.isEmpty
        ? 0.0
        : measured.children.fold<double>(
              0,
              (sum, child) => sum + child.subtreeHeight,
            ) +
            _FunctionGraphLayout.verticalGap * (measured.children.length - 1);
    var childTop = top +
        math
            .max(0.0, (measured.subtreeHeight - totalChildrenHeight) / 2)
            .toDouble();
    final children = <_PositionedFunctionNode>[];

    for (final child in measured.children) {
      children.add(position(child, childTop));
      childTop += child.subtreeHeight + _FunctionGraphLayout.verticalGap;
    }

    final x = _xForDepth(measured.depth);
    final y = top + (measured.subtreeHeight - measured.nodeHeight) / 2;

    return _PositionedFunctionNode(
      id: id,
      node: measured.node,
      depth: measured.depth,
      rect: Rect.fromLTWH(
        x,
        y,
        measured.nodeWidth,
        measured.nodeHeight,
      ),
      children: children,
    );
  }

  double _xForDepth(int depth) {
    var x = _FunctionGraphLayout.padding;
    for (var currentDepth = 0; currentDepth < depth; currentDepth++) {
      x += (_columnWidths[currentDepth] ?? _FunctionGraphLayout.nodeWidth) +
          _FunctionGraphLayout.horizontalGap;
    }
    return x;
  }
}

class _MeasuredFunctionNode {
  const _MeasuredFunctionNode({
    required this.node,
    required this.depth,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.subtreeHeight,
    required this.children,
  });

  final CodeFlowNode node;
  final int depth;
  final double nodeWidth;
  final double nodeHeight;
  final double subtreeHeight;
  final List<_MeasuredFunctionNode> children;
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
      final crossesNetworkBoundary = _crossesApplicationBackendBoundary(
        caller.node,
        callee.node,
      );

      final callerIsLeft = caller.rect.center.dx < callee.rect.center.dx;
      final start =
          callerIsLeft ? caller.rect.centerRight : caller.rect.centerLeft;
      final end =
          callerIsLeft ? callee.rect.centerLeft : callee.rect.centerRight;
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
      if (crossesNetworkBoundary) {
        _drawDashedPath(canvas, path, stroke);
      } else {
        canvas.drawPath(path, stroke);
      }

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

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashLength = 10.0;
    const gapLength = 7.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLength;
      }
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
    final dx = moveRight ? anchor.dx + 10 : anchor.dx - textPainter.width - 10;
    final dy = isCaller ? anchor.dy - textPainter.height - 7 : anchor.dy + 7;
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
