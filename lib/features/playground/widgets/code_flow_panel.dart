import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controllers/concept_label_controller.dart';
import '../controllers/playground_controller.dart';
import '../services/dart_code_flow_analyzer.dart';
import 'function_call_graph_view.dart';

class CodeFlowPanel extends StatefulWidget {
  const CodeFlowPanel({
    super.key,
    required this.controller,
    this.labels,
    this.labelModeEnabled = false,
    this.onNavigate,
  });

  final PlaygroundController controller;
  final ConceptLabelController? labels;
  final bool labelModeEnabled;
  final VoidCallback? onNavigate;

  @override
  State<CodeFlowPanel> createState() => _CodeFlowPanelState();
}

class _CodeFlowPanelState extends State<CodeFlowPanel> {
  static const _analyzer = DartCodeFlowAnalyzer();
  static const _autoAnalyzeDelay = Duration(milliseconds: 180);

  CodeFlowGraph? _graph;
  String? _error;
  String? _statusMessage;
  String? _lastAnalyzedPath;
  Timer? _analysisDebounce;
  bool _analyzing = false;
  FunctionCallGraphDirection _direction = FunctionCallGraphDirection.outgoing;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _analyze();
    });
  }

  @override
  void didUpdateWidget(covariant CodeFlowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detachController(oldWidget.controller);
      _analysisDebounce?.cancel();
      _graph = null;
      _error = null;
      _statusMessage = null;
      _lastAnalyzedPath = null;
      _analyzing = false;
      _direction = FunctionCallGraphDirection.outgoing;
      _attachController(widget.controller);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyze();
      });
    }
  }

  @override
  void dispose() {
    _analysisDebounce?.cancel();
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController(PlaygroundController controller) {
    controller.textController.addListener(_scheduleAnalyze);
    controller.workspace.addListener(_scheduleAnalyze);
  }

  void _detachController(PlaygroundController controller) {
    controller.textController.removeListener(_scheduleAnalyze);
    controller.workspace.removeListener(_scheduleAnalyze);
  }

  void _scheduleAnalyze() {
    _analysisDebounce?.cancel();
    _analysisDebounce = Timer(_autoAnalyzeDelay, () {
      if (mounted) _analyze();
    });
  }

  void _analyze() {
    if (_analyzing || !mounted) return;

    setState(() {
      _analyzing = true;
      _error = null;
    });

    final activePath = widget.controller.activeFilePath;

    try {
      final selection = widget.controller.textController.selection;
      final graph = _analyzer.analyze(
        entries: widget.controller.workspace.entries,
        activeFilePath: activePath,
        cursorLine: selection.extentIndex,
        cursorColumn: selection.extentOffset,
      );

      if (!mounted) return;
      setState(() {
        _graph = graph;
        _lastAnalyzedPath = activePath;
        _error = null;
        _statusMessage = null;
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      final canKeepCurrentGraph =
          _graph != null && _lastAnalyzedPath == activePath;

      setState(() {
        if (!canKeepCurrentGraph) {
          _graph = null;
          _lastAnalyzedPath = null;
          _error = error.toString();
          _statusMessage = null;
        } else {
          _error = null;
          _statusMessage = context.l10n.tr(
            '光标暂时不在函数内，继续保留上一条电线。',
            'The cursor is temporarily outside a function; keeping the previous wire graph.',
          );
        }
        _analyzing = false;
      });
    }
  }

  void _openNode(CodeFlowNode node) {
    final location = node.location;
    widget.controller.selectWorkspaceFile(location.filePath);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editor = widget.controller.textController;
      final lines = editor.text.split('\n');
      if (lines.isEmpty) return;

      final lineIndex = (location.line - 1).clamp(0, lines.length - 1).toInt();
      final columnIndex =
          (location.column - 1).clamp(0, lines[lineIndex].length).toInt();
      final endOffset = (columnIndex + location.length)
          .clamp(columnIndex, lines[lineIndex].length)
          .toInt();

      editor.selection = CodeLineSelection(
        baseIndex: lineIndex,
        baseOffset: columnIndex,
        extentIndex: lineIndex,
        extentOffset: endOffset,
      );
      widget.onNavigate?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final graph = _graph;
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (graph != null)
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _DirectionButton(
                      icon: Icons.call_made_outlined,
                      label: l10n.tr(
                        '我调用 ${graph.directCalleeCount}',
                        'Calls ${graph.directCalleeCount}',
                      ),
                      selected:
                          _direction == FunctionCallGraphDirection.outgoing,
                      onPressed: () {
                        if (_direction == FunctionCallGraphDirection.outgoing) {
                          return;
                        }
                        setState(() {
                          _direction = FunctionCallGraphDirection.outgoing;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  Expanded(
                    child: _DirectionButton(
                      icon: Icons.call_received_outlined,
                      label: l10n.tr(
                        '调用我 ${graph.directCallerCount}',
                        'Called by ${graph.directCallerCount}',
                      ),
                      selected:
                          _direction == FunctionCallGraphDirection.incoming,
                      onPressed: () {
                        if (_direction == FunctionCallGraphDirection.incoming) {
                          return;
                        }
                        setState(() {
                          _direction = FunctionCallGraphDirection.incoming;
                        });
                      },
                    ),
                  ),
                  if (_statusMessage case final status?)
                    Tooltip(
                      message: status,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: l10n.tr('立即刷新电线', 'Refresh wire graph now'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 36, height: 36),
                    onPressed: _analyzing ? null : _analyze,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          Expanded(
            child: _buildBody(context, graph),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, CodeFlowGraph? graph) {
    final l10n = context.l10n;

    if (_error case final error?) {
      return _PanelMessage(
        icon: Icons.cable_outlined,
        title: l10n.tr(
          '电线模式等待可追踪函数',
          'Wire mode is waiting for a traceable function',
        ),
        message: l10n.tr(
          '$error\n\n把光标移进任意 Dart 方法或函数，电线会自动出现。',
          '$error\n\nMove the cursor inside any Dart method or function and the wire graph will appear automatically.',
        ),
      );
    }

    if (graph == null) {
      return _PanelMessage(
        icon: Icons.cable_outlined,
        title: l10n.tr('电线模式已开启', 'Wire mode is enabled'),
        message: l10n.tr(
          '不需要再点“分析”。\n\n把光标移进 Dart 方法或函数，切文件、移动光标或修改代码后，调用电线都会自动更新并持续显示。',
          'You do not need to click “Analyze”.\n\nMove the cursor into a Dart method or function. The call graph updates automatically when you switch files, move the cursor, or edit code.',
        ),
      );
    }

    final root = _direction == FunctionCallGraphDirection.outgoing
        ? graph.root
        : graph.callersRoot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FunctionCallGraphView(
            key: const ValueKey('function-call-graph'),
            root: root,
            direction: _direction,
            onNodeTap: _openNode,
            labels: widget.labels,
            labelModeEnabled: widget.labelModeEnabled,
          ),
        ),
        if (root.children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Text(
              _direction == FunctionCallGraphDirection.outgoing
                  ? l10n.tr(
                      '当前函数没有解析到继续调用的 Workspace 本地函数；电线模式仍保持开启。',
                      'No further local Workspace calls were resolved from this function; wire mode remains enabled.',
                    )
                  : l10n.tr(
                      '当前函数没有解析到 Workspace 内的调用者；电线模式仍保持开启。',
                      'No callers inside this Workspace were resolved for this function; wire mode remains enabled.',
                    ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size.fromHeight(38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        backgroundColor: selected
            ? theme.colorScheme.primaryContainer.withOpacity(0.55)
            : Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
