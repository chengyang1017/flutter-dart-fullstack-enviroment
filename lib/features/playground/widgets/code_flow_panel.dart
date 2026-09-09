import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

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
          _statusMessage = '光标暂时不在函数内，继续保留上一条电线。';
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

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.cable_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '电线模式',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _analyzing ? '自动更新中…' : '已开启 · 自动追踪当前函数',
                        key: const ValueKey('wire-mode-live-indicator'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _analyzing
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '立即刷新电线',
                  onPressed: _analyzing ? null : _analyze,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_statusMessage case final status?)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (graph != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '${graph.scannedFiles} 个 Dart 文件 · '
                '${graph.declarationCount} 个方法/函数 · 自动保持显示',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SegmentedButton<FunctionCallGraphDirection>(
                key: const ValueKey('code-flow-direction-selector'),
                showSelectedIcon: false,
                segments: <ButtonSegment<FunctionCallGraphDirection>>[
                  ButtonSegment<FunctionCallGraphDirection>(
                    value: FunctionCallGraphDirection.outgoing,
                    icon: const Icon(Icons.call_made_outlined, size: 16),
                    label: Text('我调用 ${graph.directCalleeCount}'),
                  ),
                  ButtonSegment<FunctionCallGraphDirection>(
                    value: FunctionCallGraphDirection.incoming,
                    icon: const Icon(Icons.call_received_outlined, size: 16),
                    label: Text('调用我 ${graph.directCallerCount}'),
                  ),
                ],
                selected: <FunctionCallGraphDirection>{_direction},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  setState(() => _direction = selection.first);
                },
              ),
            ),
          ],
          const Divider(height: 16),
          Expanded(
            child: _buildBody(context, graph),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, CodeFlowGraph? graph) {
    if (_error case final error?) {
      return _PanelMessage(
        icon: Icons.cable_outlined,
        title: '电线模式等待可追踪函数',
        message: '$error\n\n把光标移进任意 Dart 方法或函数，电线会自动出现。',
      );
    }

    if (graph == null) {
      return const _PanelMessage(
        icon: Icons.cable_outlined,
        title: '电线模式已开启',
        message: '不需要再点“分析”。\n\n'
            '把光标移进 Dart 方法或函数，切文件、移动光标或修改代码后，调用电线都会自动更新并持续显示。',
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
                  ? '当前函数没有解析到继续调用的 Workspace 本地函数；电线模式仍保持开启。'
                  : '当前函数没有解析到 Workspace 内的调用者；电线模式仍保持开启。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
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
