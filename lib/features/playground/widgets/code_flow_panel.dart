import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../controllers/playground_controller.dart';
import '../services/dart_code_flow_analyzer.dart';

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

  @override
  void didUpdateWidget(covariant CodeFlowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _graph = null;
      _error = null;
      _analyzing = false;
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
          if (graph != null)
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
            '第一版会追踪 Workspace 内能解析到的调用，并允许点击节点跳回源码。',
      );
    }

    final rows = <_FlowRow>[];
    _flatten(graph.root, 0, rows);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _FlowNodeRow(
          row: row,
          onTap: () => _openNode(row.node),
        );
      },
    );
  }

  void _flatten(CodeFlowNode node, int depth, List<_FlowRow> rows) {
    rows.add(_FlowRow(node: node, depth: depth));
    for (final child in node.children) {
      _flatten(child, depth + 1, rows);
    }
  }
}

class _FlowRow {
  const _FlowRow({required this.node, required this.depth});

  final CodeFlowNode node;
  final int depth;
}

class _FlowNodeRow extends StatelessWidget {
  const _FlowNodeRow({
    required this.row,
    required this.onTap,
  });

  final _FlowRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16.0, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  node.isCycle
                      ? Icons.replay_outlined
                      : row.depth == 0
                          ? Icons.radio_button_checked
                          : Icons.subdirectory_arrow_right,
                  size: 17,
                  color: node.isCycle
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            row.depth == 0 ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              const SizedBox(width: 4),
              const Icon(Icons.open_in_new, size: 14),
            ],
          ),
        ),
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
