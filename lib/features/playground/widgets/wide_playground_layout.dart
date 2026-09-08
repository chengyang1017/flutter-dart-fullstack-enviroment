import 'dart:async';

import 'package:flutter/material.dart';

import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/runner_console_panel.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/widgets/workspace_editor_tabs.dart';
import '../../workspace/widgets/workspace_file_explorer.dart';
import '../controllers/concept_label_controller.dart';
import '../controllers/playground_controller.dart';
import 'code_editor_panel.dart';
import 'code_flow_panel.dart';
import 'concept_label_editor_layer.dart';
import 'error_panel.dart';

class WidePlaygroundLayout extends StatefulWidget {
  const WidePlaygroundLayout({
    super.key,
    required this.controller,
    required this.runner,
    required this.toolbar,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final Widget toolbar;

  @override
  State<WidePlaygroundLayout> createState() => _WidePlaygroundLayoutState();
}

class _WidePlaygroundLayoutState extends State<WidePlaygroundLayout> {
  bool _showExplorer = true;
  bool _showPreview = true;
  bool _showConsole = true;
  bool _wireModeEnabled = false;
  bool _labelModeEnabled = false;
  late final ConceptLabelController _labels;

  @override
  void initState() {
    super.initState();
    _labels = ConceptLabelController();
    unawaited(_labels.load());
  }

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  Future<void> _openAddLabelDialog() async {
    if (_labelModeEnabled) {
      setState(() => _labelModeEnabled = false);
      await Future<void>.delayed(Duration.zero);
    }

    if (!mounted) return;

    final editor = widget.controller.textController;
    final lines = editor.text.split('\n');
    if (lines.isEmpty) return;

    final lineIndex = editor.selection.extentIndex.clamp(0, lines.length - 1).toInt();
    final sourceLine = lines[lineIndex];
    final selected = editor.selectedText;
    final selectedSingleLine = selected.trim().isNotEmpty && !selected.contains('\n');

    final sourceController = TextEditingController(
      text: selectedSingleLine ? selected : sourceLine.trim(),
    );
    final labelController = TextEditingController();
    var reusable = selectedSingleLine;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加标签'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      reusable ? 'Flutter / Dart 通用标签' : '当前文件第 ${lineIndex + 1} 行',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sourceController,
                      readOnly: !reusable,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: reusable ? '要覆盖的源码' : '当前源码',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '你自己输入的标签',
                        hintText: reusable ? '例如：等' : '例如：读取商品并刷新页面',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('在 Flutter / Dart 中通用复用'),
                      subtitle: const Text('关闭后只覆盖当前文件的这一行'),
                      value: reusable,
                      onChanged: (value) {
                        setDialogState(() {
                          reusable = value;
                          errorText = null;
                          sourceController.text = value
                              ? (selectedSingleLine ? selected : sourceLine.trim())
                              : sourceLine;
                        });
                      },
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
                    final source = sourceController.text.trim();
                    final label = labelController.text.trim();
                    if (source.isEmpty || label.isEmpty) {
                      setDialogState(() => errorText = '源码和标签都不能为空');
                      return;
                    }
                    if (reusable && source.contains('\n')) {
                      setDialogState(() => errorText = '通用标签第一版只支持单行源码');
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
      if (reusable) {
        await _labels.addReusableRule(
          path: widget.controller.activeFilePath,
          source: sourceController.text,
          label: labelController.text,
        );
      } else {
        await _labels.setLineLabel(
          path: widget.controller.activeFilePath,
          lineNumber: lineIndex + 1,
          sourceLine: sourceLine,
          label: labelController.text,
        );
      }
    }

    sourceController.dispose();
    labelController.dispose();
  }

  Future<void> _openManageLabelsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: _labels,
          builder: (context, _) {
            final language = ConceptLabelController.languageForPath(
              widget.controller.activeFilePath,
            );
            final rules = _labels.rules
                .where((rule) => rule.language == language)
                .toList(growable: false);

            return AlertDialog(
              title: Text('我的标签 · $language'),
              content: SizedBox(
                width: 560,
                height: 360,
                child: rules.isEmpty
                    ? const Center(
                        child: Text('还没有标签。先在源码里选择内容，再点“添加标签”。'),
                      )
                    : ListView.separated(
                        itemCount: rules.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          return ListTile(
                            dense: true,
                            title: Text('${rule.source}  →  ${rule.label}'),
                            subtitle: Text(
                              rule.isReusable
                                  ? '通用复用'
                                  : '${rule.filePath ?? ''} · 第 ${rule.lineNumber ?? '-'} 行',
                            ),
                            trailing: IconButton(
                              tooltip: '删除标签',
                              onPressed: () => _labels.removeRule(rule.id),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          widget.toolbar,
          Expanded(
            child: Row(
              children: [
                if (_showExplorer)
                  SizedBox(
                    width: 230,
                    child: WorkspaceFileExplorer(
                      workspace: widget.controller.workspace,
                      onOpenFile: widget.controller.selectWorkspaceFile,
                    ),
                  ),
                if (_showExplorer) const VerticalDivider(width: 1),
                Expanded(
                  child: _EditorArea(
                    controller: widget.controller,
                    labels: _labels,
                    runner: widget.runner,
                    showConsole: _showConsole,
                    wireModeEnabled: _wireModeEnabled,
                    labelModeEnabled: _labelModeEnabled,
                    onToggleConsole: () {
                      setState(() => _showConsole = !_showConsole);
                    },
                    onToggleExplorer: () {
                      setState(() => _showExplorer = !_showExplorer);
                    },
                    onTogglePreview: () {
                      setState(() => _showPreview = !_showPreview);
                    },
                    onToggleWireMode: () {
                      setState(() => _wireModeEnabled = !_wireModeEnabled);
                    },
                    onToggleLabelMode: () {
                      setState(() => _labelModeEnabled = !_labelModeEnabled);
                    },
                    onAddLabel: _openAddLabelDialog,
                    onManageLabels: _openManageLabelsDialog,
                    explorerVisible: _showExplorer,
                    previewVisible: _showPreview,
                  ),
                ),
                if (_wireModeEnabled) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 42,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_tree_outlined,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ç”µçº¿æ¨¡å¼',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'æŒç»­æ˜¾ç¤º Â· è‡ªåŠ¨è·Ÿéšä»£ç ',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'å…³é—­ç”µçº¿æ¨¡å¼',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() => _wireModeEnabled = false);
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: CodeFlowPanel(controller: widget.controller),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_showPreview) const VerticalDivider(width: 1),
                if (_showPreview)
                  SizedBox(
                    width: 330,
                    child: _PreviewArea(
                      controller: widget.controller,
                      runner: widget.runner,
                      onClose: () {
                        setState(() => _showPreview = false);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorArea extends StatelessWidget {
  const _EditorArea({
    required this.controller,
    required this.labels,
    required this.runner,
    required this.showConsole,
    required this.wireModeEnabled,
    required this.labelModeEnabled,
    required this.onToggleConsole,
    required this.onToggleExplorer,
    required this.onTogglePreview,
    required this.onToggleWireMode,
    required this.onToggleLabelMode,
    required this.onAddLabel,
    required this.onManageLabels,
    required this.explorerVisible,
    required this.previewVisible,
  });

  final PlaygroundController controller;
  final ConceptLabelController labels;
  final FlutterRunnerController runner;
  final bool showConsole;
  final bool wireModeEnabled;
  final bool labelModeEnabled;
  final bool explorerVisible;
  final bool previewVisible;
  final VoidCallback onToggleConsole;
  final VoidCallback onToggleExplorer;
  final VoidCallback onTogglePreview;
  final VoidCallback onToggleWireMode;
  final VoidCallback onToggleLabelMode;
  final VoidCallback onAddLabel;
  final VoidCallback onManageLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EditorCommandBar(
          controller: controller,
          explorerVisible: explorerVisible,
          previewVisible: previewVisible,
          wireModeEnabled: wireModeEnabled,
          labelModeEnabled: labelModeEnabled,
          onToggleExplorer: onToggleExplorer,
          onTogglePreview: onTogglePreview,
          onToggleWireMode: onToggleWireMode,
          onToggleLabelMode: onToggleLabelMode,
          onAddLabel: onAddLabel,
          onManageLabels: onManageLabels,
        ),
        WorkspaceEditorTabs(
          workspace: controller.workspace,
          onSelect: controller.selectWorkspaceFile,
          onClose: controller.closeWorkspaceFile,
        ),
        Expanded(
          child: ConceptLabelEditorLayer(
            controller: controller,
            labels: labels,
            enabled: labelModeEnabled,
            child: CodeEditorPanel(
              controller: controller,
              wireModeEnabled: wireModeEnabled,
            ),
          ),
        ),
        ErrorPanel(controller: controller, maxHeight: 110),
        _ConsoleBar(expanded: showConsole, onPressed: onToggleConsole),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: showConsole ? 135 : 0,
          child: showConsole ? RunnerConsolePanel(runner: runner) : null,
        ),
      ],
    );
  }
}

class _EditorCommandBar extends StatelessWidget {
  const _EditorCommandBar({
    required this.controller,
    required this.explorerVisible,
    required this.previewVisible,
    required this.wireModeEnabled,
    required this.labelModeEnabled,
    required this.onToggleExplorer,
    required this.onTogglePreview,
    required this.onToggleWireMode,
    required this.onToggleLabelMode,
    required this.onAddLabel,
    required this.onManageLabels,
  });

  final PlaygroundController controller;
  final bool explorerVisible;
  final bool previewVisible;
  final bool wireModeEnabled;
  final bool labelModeEnabled;
  final VoidCallback onToggleExplorer;
  final VoidCallback onTogglePreview;
  final VoidCallback onToggleWireMode;
  final VoidCallback onToggleLabelMode;
  final VoidCallback onAddLabel;
  final VoidCallback onManageLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: scheme.surface,
      child: Row(
        children: [
          IconButton(
            tooltip: explorerVisible ? 'æ”¶èµ·æ–‡ä»¶æ ‘' : 'å±•å¼€æ–‡ä»¶æ ‘',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleExplorer,
            icon: Icon(
              explorerVisible ? Icons.chevron_left : Icons.chevron_right,
              size: 18,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              controller.activeFilePath,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (controller.workspace.isDirty)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('add-concept-label'),
            tooltip: '给选中代码 / 当前行添加自己的标签',
            visualDensity: VisualDensity.compact,
            onPressed: onAddLabel,
            icon: const Icon(Icons.new_label_outlined, size: 18),
          ),
          IconButton(
            key: const ValueKey('manage-concept-labels'),
            tooltip: '管理我的标签',
            visualDensity: VisualDensity.compact,
            onPressed: onManageLabels,
            icon: const Icon(Icons.label_important_outline, size: 18),
          ),
          if (labelModeEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '标签 ON',
                key: const ValueKey('label-mode-active-label'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          IconButton(
            key: const ValueKey('label-mode-toggle'),
            tooltip: labelModeEnabled ? '切回原代码视角' : '显示我自己创建的标签',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: labelModeEnabled
                  ? scheme.tertiaryContainer
                  : Colors.transparent,
              foregroundColor: labelModeEnabled
                  ? scheme.onTertiaryContainer
                  : scheme.onSurfaceVariant,
            ),
            onPressed: onToggleLabelMode,
            icon: Icon(
              labelModeEnabled ? Icons.label : Icons.label_outline,
              size: 18,
            ),
          ),
          if (wireModeEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '电线 ON',
                key: const ValueKey('wire-mode-active-label'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          IconButton(
            key: const ValueKey('wire-mode-toggle'),
            tooltip:
                wireModeEnabled ? 'å…³é—­ç”µçº¿æ¨¡å¼' : 'æ‰“å¼€ç”µçº¿æ¨¡å¼',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: wireModeEnabled
                  ? scheme.primaryContainer
                  : Colors.transparent,
              foregroundColor: wireModeEnabled
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            onPressed: onToggleWireMode,
            icon: Icon(
              wireModeEnabled ? Icons.cable : Icons.cable_outlined,
              size: 18,
            ),
          ),
          IconButton(
            tooltip:
                previewVisible ? 'æ”¶èµ·è®¾å¤‡é¢„è§ˆ' : 'å±•å¼€è®¾å¤‡é¢„è§ˆ',
            visualDensity: VisualDensity.compact,
            onPressed: onTogglePreview,
            icon: Icon(
              previewVisible ? Icons.chevron_right : Icons.chevron_left,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleBar extends StatelessWidget {
  const _ConsoleBar({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.terminal_outlined, size: 15),
                const SizedBox(width: 7),
                const Text(
                  'Console',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.controller,
    required this.runner,
    required this.onClose,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_android_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Device Preview',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'æ”¶èµ·',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.chevron_right, size: 19),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
          Expanded(
            child: RunnerPreviewPanel(
              playground: controller,
              runner: runner,
            ),
          ),
        ],
      ),
    );
  }
}
