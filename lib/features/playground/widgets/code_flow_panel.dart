import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../controllers/playground_controller.dart';
import '../services/dart_code_flow_analyzer.dart';
import 'function_call_graph_view.dart';

class CodeFlowPanel extends StatefulWidget {
  const CodeFlowPanel({
    super.key,
    required this.controller,
    this.onNavigate,
  });

  final PlaygroundController controller;
  final VoidCallback? onNavigate;

  @override
  State<CodeFlowPanel> createState() => _CodeFlowPanelState();
}

class _CodeFlowPanelState extends State<CodeFlowPanel> {
  static const _analyzer = DartCodeFlowAnalyzer();

  CodeFlowGraph? _graph;
  String? _error;
  bool _analyzing = false;
  FunctionCallGraphDirection _direction = FunctionCallGraphDirection.outgoing;

  @override
  void didUpdateWidget(covariant CodeFlowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _graph = null;
      _error = null;
      _analyzing = false;
      _direction = FunctionCallGraphDirection.outgoing;
    }
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
    });

    // Give Web one frame to paint the progress indicator before parsing a
    // larger imported Workspace on the UI isolate.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    try {
      final selection = widget.controller.textController.selection;
      final graph = _analyzer.analyze(
        entries: widget.controller.workspace.entries,
        activeFilePath: widget.controller.activeFilePath,
        cursorLine: selection.extentIndex,
        cursorColumn: selection.extentOffset,
      );
      if (!mounted) return;
      setState(() {
        _graph = graph;
        _error = null;
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _graph = null;
        _error = error.toString();
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
                const Icon(Icons.account_tree_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '代码调用链',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '重新分析当前方法',
                  onPressed: _analyzing ? null : _analyze,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilledButton.icon(
              key: const ValueKey('code-flow-analyze-button'),
              onPressed: _analyzing ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route_outlined),
              label: Text(_analyzing ? '分析中…' : '分析光标所在方法'),
            ),
          ),
          const SizedBox(height: 8),
          if (graph != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '${graph.scannedFiles} 个 Dart 文件 · '
                '${graph.declarationCount} 个方法/函数',
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
        icon: Icons.info_outline,
        title: '暂时无法分析',
        message: error,
      );
    }

    if (graph == null) {
      return const _PanelMessage(
        icon: Icons.route_outlined,
        title: '从一个方法开始',
        message: '把光标放在 Dart 方法或函数内部，然后点击“分析光标所在方法”。\n\n'
            '可以查看它调用了谁，也可以反向查看 Workspace 内是谁调用了它。',
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
          ),
        ),
        if (root.children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Text(
              _direction == FunctionCallGraphDirection.outgoing
                  ? 'Workspace 内没有解析到这个方法继续调用的本地方法。'
                  : 'Workspace 内没有解析到调用这个方法的本地方法。',
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
