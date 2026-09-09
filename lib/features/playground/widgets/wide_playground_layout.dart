import 'dart:async';

import 'package:flutter/material.dart';

import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/widgets/workspace_editor_tabs.dart';
import '../controllers/concept_label_controller.dart';
import '../controllers/playground_controller.dart';
import '../models/workspace_view_mode.dart';
import 'monaco_code_editor_panel.dart';
import 'code_flow_panel.dart';
import 'error_panel.dart';
import 'ide_bottom_panel.dart';
import 'unified_workspace_explorer.dart';
import 'workspace_diff_panel.dart';

class WidePlaygroundLayout extends StatefulWidget {
  const WidePlaygroundLayout({
    super.key,
    required this.controller,
    required this.runner,
    required this.toolbar,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final Widget toolbar;
  final WorkspaceViewMode viewMode;
  final ValueChanged<WorkspaceViewMode> onViewModeChanged;

  @override
  State<WidePlaygroundLayout> createState() => _WidePlaygroundLayoutState();
}

class _WidePlaygroundLayoutState extends State<WidePlaygroundLayout> {
  bool _showExplorer = true;
  bool _showPreview = true;
  bool _showConsole = true;
  bool _wireModeEnabled = false;
  bool _labelModeEnabled = false;
  String? _sourceDiffPath;
  late final ConceptLabelController _labels;
  late Widget _persistentMonacoEditor;

  @override
  void initState() {
    super.initState();
    _labels = ConceptLabelController();
    _persistentMonacoEditor = _buildPersistentMonacoEditor();
    unawaited(_labels.load());
  }

  Widget _buildPersistentMonacoEditor() {
    return MonacoCodeEditorPanel(
      controller: widget.controller,
      labels: _labels,
      labelModeEnabled: _labelModeEnabled,
      wireModeEnabled: _wireModeEnabled,
    );
  }

  void _refreshPersistentMonacoEditor() {
    _persistentMonacoEditor = _buildPersistentMonacoEditor();
  }

  @override
  void didUpdateWidget(covariant WidePlaygroundLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _sourceDiffPath = null;
      _refreshPersistentMonacoEditor();
    }
  }

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  Future<void> _openAddLabelDialog() async {
    if (_labelModeEnabled) {
      setState(() {
        _labelModeEnabled = false;
        _refreshPersistentMonacoEditor();
      });
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.toolbar,
          Expanded(
            child: Row(
              children: [
                if (_showExplorer)
                  SizedBox(
                    width: 264,
                    child: UnifiedWorkspaceExplorer(
                      controller: widget.controller,
                      runner: widget.runner,
                      viewMode: widget.viewMode,
                      onViewModeChanged: widget.onViewModeChanged,
                      onShowDiff: (path) {
                        setState(() => _sourceDiffPath = path);
                      },
                    ),
                  ),
                if (_showExplorer)
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xff272d36),
                  ),
                Expanded(
                  child: _EditorArea(
                    controller: widget.controller,
                    labels: _labels,
                    runner: widget.runner,
                    viewMode: widget.viewMode,
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
                      setState(() {
                        _wireModeEnabled = !_wireModeEnabled;
                        _refreshPersistentMonacoEditor();
                      });
                    },
                    onToggleLabelMode: () {
                      setState(() {
                        _labelModeEnabled = !_labelModeEnabled;
                        _refreshPersistentMonacoEditor();
                      });
                    },
                    onAddLabel: _openAddLabelDialog,
                    onManageLabels: _openManageLabelsDialog,
                    explorerVisible: _showExplorer,
                    previewVisible: _showPreview,
                    persistentMonacoEditor: _persistentMonacoEditor,
                    sourceDiffPath: _sourceDiffPath,
                    onCloseSourceDiff: () {
                      setState(() => _sourceDiffPath = null);
                    },
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
                                        '电线模式',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '持续显示 · 自动跟随代码',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭电线模式',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      _wireModeEnabled = false;
                                      _refreshPersistentMonacoEditor();
                                    });
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
                if (_showPreview)
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xff272d36),
                  ),
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
    required this.viewMode,
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
    required this.persistentMonacoEditor,
    required this.sourceDiffPath,
    required this.onCloseSourceDiff,
  });

  final PlaygroundController controller;
  final ConceptLabelController labels;
  final FlutterRunnerController runner;
  final WorkspaceViewMode viewMode;
  final bool showConsole;
  final bool wireModeEnabled;
  final bool labelModeEnabled;
  final bool explorerVisible;
  final bool previewVisible;
  final Widget persistentMonacoEditor;
  final String? sourceDiffPath;
  final VoidCallback onCloseSourceDiff;
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
          pathFilter: viewMode.isConcept
              ? (path) => viewMode.allowsPath(path)
              : null,
        ),
        Expanded(
          child: IdeEditorPanelSplit(
            panelExpanded: showConsole,
            editor: viewMode.isSourceControl && sourceDiffPath != null
                ? WorkspaceDiffPanel(
                    workspace: controller.workspace,
                    path: sourceDiffPath!,
                    onClose: onCloseSourceDiff,
                  )
                : Column(
                    children: [
                      Expanded(child: persistentMonacoEditor),
                      ErrorPanel(controller: controller, maxHeight: 110),
                    ],
                  ),
            panel: IdeBottomPanel(
              runner: runner,
              expanded: showConsole,
              onExpandedChanged: (_) => onToggleConsole(),
            ),
          ),
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

  static const _background = Color(0xff111318);
  static const _border = Color(0xff272d36);
  static const _muted = Color(0xff8f98a8);
  static const _text = Color(0xffcbd3df);
  static const _accent = Color(0xff82aaff);
  static const _selected = Color(0xff22324a);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: const BoxDecoration(
        color: _background,
        border: Border(
          bottom: BorderSide(color: _border),
        ),
      ),
      child: Row(
        children: [
          _EditorBarIconButton(
            tooltip: explorerVisible ? '收起文件树' : '展开文件树',
            icon: explorerVisible
                ? Icons.menu_open_rounded
                : Icons.menu_rounded,
            onPressed: onToggleExplorer,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    controller.activeFilePath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (controller.workspace.isDirty)
                  const Padding(
                    padding: EdgeInsets.only(left: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: _accent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: _border,
            ),
          ),
          const SizedBox(width: 5),
          _EditorBarIconButton(
            key: const ValueKey('add-concept-label'),
            tooltip: '给选中代码 / 当前行添加标签',
            icon: Icons.new_label_outlined,
            onPressed: onAddLabel,
          ),
          _EditorBarIconButton(
            key: const ValueKey('manage-concept-labels'),
            tooltip: '管理标签',
            icon: Icons.label_important_outline,
            onPressed: onManageLabels,
          ),
          _EditorBarIconButton(
            key: const ValueKey('label-mode-toggle'),
            tooltip: labelModeEnabled ? '切回原代码视角' : '显示标签视角',
            icon: labelModeEnabled ? Icons.label : Icons.label_outline,
            selected: labelModeEnabled,
            onPressed: onToggleLabelMode,
          ),
          const SizedBox(width: 4),
          const SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: _border,
            ),
          ),
          const SizedBox(width: 5),
          _EditorBarIconButton(
            key: const ValueKey('wire-mode-toggle'),
            tooltip: wireModeEnabled ? '关闭电线模式' : '打开电线模式',
            icon: wireModeEnabled ? Icons.cable : Icons.cable_outlined,
            selected: wireModeEnabled,
            onPressed: onToggleWireMode,
          ),
          _EditorBarIconButton(
            tooltip: previewVisible ? '收起设备预览' : '展开设备预览',
            icon: Icons.phone_android_outlined,
            selected: previewVisible,
            onPressed: onTogglePreview,
          ),
        ],
      ),
    );
  }
}

class _EditorBarIconButton extends StatelessWidget {
  const _EditorBarIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(31, 30),
        maximumSize: const Size(31, 30),
        padding: EdgeInsets.zero,
        foregroundColor:
            selected ? _EditorCommandBar._accent : _EditorCommandBar._muted,
        backgroundColor:
            selected ? _EditorCommandBar._selected : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
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

  static const _background = Color(0xff111318);
  static const _surface = Color(0xff15191f);
  static const _border = Color(0xff272d36);
  static const _muted = Color(0xff8f98a8);
  static const _text = Color(0xffcbd3df);
  static const _accent = Color(0xff82aaff);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: const BoxDecoration(
              color: _background,
              border: Border(
                bottom: BorderSide(color: _border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(
                    Icons.phone_android_outlined,
                    size: 15,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Preview',
                        style: TextStyle(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Flutter runtime',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 9.5,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '收起设备预览',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: _muted,
                    minimumSize: const Size(30, 30),
                    maximumSize: const Size(30, 30),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.chevron_right_rounded, size: 19),
                ),
              ],
            ),
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
