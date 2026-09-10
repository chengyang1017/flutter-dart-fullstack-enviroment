import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

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
  static const double _wirePanelMinWidth = 320;
  static const double _wirePanelDefaultWidth = 460;
  static const double _editorMinWidth = 320;
  static const double _wireSashWidth = 7;

  bool _showExplorer = true;
  bool _showPreview = true;
  bool _showConsole = true;
  bool _wireModeEnabled = false;
  bool _wireModeFullscreen = false;
  bool _labelModeEnabled = false;
  bool _wireLabelModeEnabled = false;
  double _wirePanelWidth = _wirePanelDefaultWidth;
  String? _sourceDiffPath;
  late final ConceptLabelController _labels;
  late final ValueNotifier<double> _wirePanelLiveWidth;
  late final ValueNotifier<bool> _wireSashHighlighted;

  int? _wireActivePointerId;
  double _wireDragStartGlobalX = 0;
  double _wireDragStartWidth = _wirePanelDefaultWidth;
  double _wirePanelMaxWidth = _wirePanelDefaultWidth;
  bool _wireGlobalPointerRouteInstalled = false;
  bool _wirePanelHasCustomWidth = false;
  OverlayEntry? _wireDragShieldEntry;

  @override
  void initState() {
    super.initState();
    _labels = ConceptLabelController();
    _wirePanelLiveWidth = ValueNotifier<double>(_wirePanelDefaultWidth);
    _wireSashHighlighted = ValueNotifier<bool>(false);
    unawaited(_labels.load());
  }

  @override
  void didUpdateWidget(covariant WidePlaygroundLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _sourceDiffPath = null;
    }
  }

  @override
  void dispose() {
    _removeWireGlobalPointerRoute();
    _removeWireDragShield();
    _wirePanelLiveWidth.dispose();
    _wireSashHighlighted.dispose();
    _labels.dispose();
    super.dispose();
  }

  double _clampWirePanelWidth(double requested) {
    final maxWidth = _wirePanelMaxWidth < _wirePanelMinWidth
        ? _wirePanelMinWidth
        : _wirePanelMaxWidth;
    return requested.clamp(_wirePanelMinWidth, maxWidth).toDouble();
  }

  void _beginWireResize(PointerDownEvent event) {
    if (!_wireModeEnabled ||
        _wireModeFullscreen ||
        _wireActivePointerId != null) {
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }

    _wireActivePointerId = event.pointer;
    _wireDragStartGlobalX = event.position.dx;
    _wireDragStartWidth = _clampWirePanelWidth(_wirePanelWidth);
    _wirePanelLiveWidth.value = _wireDragStartWidth;
    _wireSashHighlighted.value = true;
    _installWireGlobalPointerRoute();
    _showWireDragShield();
  }

  void _installWireGlobalPointerRoute() {
    if (_wireGlobalPointerRouteInstalled) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleWireGlobalPointerEvent,
    );
    _wireGlobalPointerRouteInstalled = true;
  }

  void _removeWireGlobalPointerRoute() {
    if (!_wireGlobalPointerRouteInstalled) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleWireGlobalPointerEvent,
    );
    _wireGlobalPointerRouteInstalled = false;
  }

  void _showWireDragShield() {
    if (_wireDragShieldEntry != null || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: MonacoOverlayBoundary(
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: const Listener(
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(color: Colors.transparent),
            ),
          ),
        ),
      ),
    );
    _wireDragShieldEntry = entry;
    overlay.insert(entry);
  }

  void _removeWireDragShield() {
    _wireDragShieldEntry?.remove();
    _wireDragShieldEntry = null;
  }

  void _handleWireGlobalPointerEvent(PointerEvent event) {
    final activePointer = _wireActivePointerId;
    if (activePointer == null || event.pointer != activePointer) return;

    if (event is PointerMoveEvent) {
      final delta = event.position.dx - _wireDragStartGlobalX;
      final next = _clampWirePanelWidth(_wireDragStartWidth - delta);
      if (next != _wirePanelLiveWidth.value) {
        _wirePanelLiveWidth.value = next;
      }
      return;
    }

    if (event is PointerUpEvent) {
      _finishWireResize(activePointer, commit: true);
      return;
    }

    if (event is PointerCancelEvent) {
      _finishWireResize(activePointer, commit: false);
    }
  }

  void _finishWireResize(int pointer, {required bool commit}) {
    if (pointer != _wireActivePointerId) return;
    if (commit) {
      _wirePanelWidth = _clampWirePanelWidth(_wirePanelLiveWidth.value);
      _wirePanelHasCustomWidth = true;
    } else {
      _wirePanelLiveWidth.value = _wirePanelWidth;
    }

    _wireActivePointerId = null;
    _removeWireGlobalPointerRoute();
    _removeWireDragShield();
    _wireSashHighlighted.value = false;
  }

  void _resetWirePanelWidth() {
    setState(() {
      _wirePanelWidth = _clampWirePanelWidth(_wirePanelDefaultWidth);
      _wirePanelLiveWidth.value = _wirePanelWidth;
      _wirePanelHasCustomWidth = false;
    });
  }

  Widget _buildWireSash() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => _wireSashHighlighted.value = true,
      onExit: (_) {
        if (_wireActivePointerId == null) {
          _wireSashHighlighted.value = false;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _resetWirePanelWidth,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _beginWireResize,
          child: SizedBox(
            width: _wireSashWidth,
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: _wireSashHighlighted,
                builder: (context, highlighted, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: highlighted ? 2 : 1,
                    color: highlighted
                        ? const Color(0xff82aaff)
                        : const Color(0xff303641),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddLabelDialog() async {
    if (_labelModeEnabled) {
      setState(() {
        _labelModeEnabled = false;
      });
      await Future<void>.delayed(Duration.zero);
    }

    if (!mounted) return;

    final editor = widget.controller.textController;
    final lines = editor.text.split('\n');
    if (lines.isEmpty) return;

    final selection = editor.selection;
    final selected = editor.selectedText;
    final selectedSingleLine = selection.baseIndex == selection.extentIndex &&
        selected.trim().isNotEmpty &&
        !selected.contains('\n');

    final lineIndex =
        (selectedSingleLine ? selection.baseIndex : selection.extentIndex)
            .clamp(0, lines.length - 1)
            .toInt();
    final sourceLine = lines[lineIndex];

    final int startColumn;
    final int endColumn;
    final bool wholeLine;
    if (selectedSingleLine) {
      final first = selection.baseOffset < selection.extentOffset
          ? selection.baseOffset
          : selection.extentOffset;
      final last = selection.baseOffset > selection.extentOffset
          ? selection.baseOffset
          : selection.extentOffset;
      startColumn = first.clamp(0, sourceLine.length).toInt();
      endColumn = last.clamp(startColumn, sourceLine.length).toInt();
      wholeLine = false;
    } else {
      startColumn =
          RegExp(r'^\s*').firstMatch(sourceLine)?.group(0)?.length ?? 0;
      endColumn = sourceLine.length;
      wholeLine = true;
    }

    if (startColumn >= endColumn) return;
    final targetSource = sourceLine.substring(startColumn, endColumn);
    if (targetSource.trim().isEmpty) return;

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
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      wholeLine
                          ? '当前文件第 ${lineIndex + 1} 行'
                          : '当前文件第 ${lineIndex + 1} 行 · '
                              '第 ${startColumn + 1}–$endColumn 列',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '只绑定这一处源码；上方增删行、代码移动或附近内容变化后会智能重新定位。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '当前源码位置',
                        border: OutlineInputBorder(),
                      ),
                      child: SelectableText(
                        targetSource,
                        maxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '这个位置显示成什么',
                        hintText: wholeLine ? '例如：读取商品并刷新页面' : '例如：等',
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
      await _labels.setPositionLabel(
        path: widget.controller.activeFilePath,
        sourceText: editor.text,
        lineNumber: lineIndex + 1,
        startColumn: startColumn,
        endColumn: endColumn,
        label: labelController.text,
        wholeLine: wholeLine,
      );
    }

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
              title: Text('我的标签与容器名 · $language'),
              content: SizedBox(
                width: 620,
                height: 380,
                child: rules.isEmpty
                    ? const Center(
                        child: Text('还没有标签。先选择一段源码，再点“添加标签”。'),
                      )
                    : ListView.separated(
                        itemCount: rules.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          final String subtitle;
                          switch (rule.scope) {
                            case ConceptLabelScope.language:
                              subtitle = '旧版通用标签 · 已停止自动复用；重新添加即可改为位置专属';
                              break;
                            case ConceptLabelScope.line:
                              subtitle = '${rule.filePath ?? ''} · '
                                  '整行位置标签 · 第 ${rule.lineNumber ?? '-'} 行';
                              break;
                            case ConceptLabelScope.range:
                              final column = rule.startColumn == null
                                  ? '-'
                                  : '${rule.startColumn! + 1}';
                              subtitle = '${rule.filePath ?? ''} · '
                                  '位置标签 · 第 ${rule.lineNumber ?? '-'} 行:$column';
                              break;
                            case ConceptLabelScope.node:
                              subtitle = '${rule.filePath ?? ''} · '
                                  '电线容器名称 · 原函数 ${rule.source}';
                              break;
                          }

                          return ListTile(
                            dense: true,
                            title: Text('${rule.source}  →  ${rule.label}'),
                            subtitle: Text(subtitle),
                            trailing: IconButton(
                              tooltip: '删除',
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
    return ColoredBox(
      color: const Color(0xff111318),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_wireModeFullscreen) widget.toolbar,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_wireModeEnabled && _wireModeFullscreen) {
                  return _buildWirePanel(context, fullscreen: true);
                }

                final reservedWidth = (_showExplorer ? 265.0 : 0.0) +
                    (_showPreview ? 331.0 : 0.0) +
                    420.0;
                final availableForWire = constraints.maxWidth - reservedWidth;
                final maxWireWidth = availableForWire < _wirePanelMinWidth
                    ? _wirePanelMinWidth
                    : availableForWire;
                final ideMaxWireWidth = constraints.maxWidth -
                    (_showExplorer ? 265.0 : 0.0) -
                    (_showPreview ? 331.0 : 0.0) -
                    _editorMinWidth -
                    _wireSashWidth;
                _wirePanelMaxWidth = ideMaxWireWidth < _wirePanelMinWidth
                    ? _wirePanelMinWidth
                    : ideMaxWireWidth;

                final wirePanelWidth = _wirePanelWidth
                    .clamp(_wirePanelMinWidth, maxWireWidth)
                    .toDouble();

                return Row(
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
                            if (!_wireModeEnabled) {
                              _wireModeFullscreen = false;
                            }
                          });
                        },
                        onToggleLabelMode: () {
                          setState(() {
                            _labelModeEnabled = !_labelModeEnabled;
                          });
                        },
                        onAddLabel: _openAddLabelDialog,
                        onManageLabels: _openManageLabelsDialog,
                        explorerVisible: _showExplorer,
                        previewVisible: _showPreview,
                        sourceDiffPath: _sourceDiffPath,
                        onCloseSourceDiff: () {
                          setState(() => _sourceDiffPath = null);
                        },
                      ),
                    ),
                    if (_wireModeEnabled) ...[
                      _buildWireSash(),
                      ValueListenableBuilder<double>(
                        valueListenable: _wirePanelLiveWidth,
                        child: _buildWirePanel(
                          context,
                          fullscreen: false,
                        ),
                        builder: (context, liveWidth, child) {
                          final useDefaultLayoutWidth =
                              _wireActivePointerId == null &&
                                  !_wirePanelHasCustomWidth;
                          final width = useDefaultLayoutWidth
                              ? wirePanelWidth
                              : _clampWirePanelWidth(liveWidth);
                          return SizedBox(
                            width: width,
                            child: child,
                          );
                        },
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  ThemeData _wireTheme() {
    const background = Color(0xff111318);
    const surface = Color(0xff15191f);
    const surfaceHigh = Color(0xff1d2632);
    const selected = Color(0xff22324a);
    const border = Color(0xff2b333e);
    const text = Color(0xffd7dde8);
    const muted = Color(0xff8f98a8);
    const accent = Color(0xff82aaff);

    final base = ThemeData.dark(useMaterial3: true);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: const Color(0xff0d1827),
      primaryContainer: selected,
      onPrimaryContainer: const Color(0xffdbe8ff),
      secondaryContainer: const Color(0xff1c2d45),
      onSecondaryContainer: text,
      surface: background,
      onSurface: text,
      surfaceContainerLow: surface,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: muted,
      outline: const Color(0xff445064),
      outlineVariant: border,
      tertiary: const Color(0xffc792ea),
      surfaceTint: Colors.transparent,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: muted),
    );
  }

  Widget _buildWirePanel(
    BuildContext context, {
    required bool fullscreen,
  }) {
    final wireTheme = _wireTheme();
    final scheme = wireTheme.colorScheme;

    Widget wireLabelButton({required bool compact}) {
      return Tooltip(
        message: _wireLabelModeEnabled ? '关闭电线容器源码标签' : '开启电线容器源码标签',
        child: IconButton(
          key: ValueKey(
            _wireLabelModeEnabled
                ? 'wire-label-mode-on'
                : 'wire-label-mode-off',
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: compact ? 34 : 36,
            height: compact ? 34 : 36,
          ),
          onPressed: () {
            setState(() {
              _wireLabelModeEnabled = !_wireLabelModeEnabled;
            });
          },
          icon: Icon(
            _wireLabelModeEnabled
                ? Icons.label_rounded
                : Icons.label_outline_rounded,
            size: 18,
            color: _wireLabelModeEnabled
                ? const Color(0xff82aaff)
                : const Color(0xff8f98a8),
          ),
        ),
      );
    }

    final codeFlow = CodeFlowPanel(
      controller: widget.controller,
      labels: _labels,
      labelModeEnabled: _wireLabelModeEnabled,
    );

    return Theme(
      data: wireTheme,
      child: Material(
        color: scheme.surface,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!fullscreen)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xff111318),
                      border: Border(
                        bottom: BorderSide(color: Color(0xff2b333e)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_tree_outlined,
                          size: 17,
                          color: Color(0xff82aaff),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '电线模式',
                            style: TextStyle(
                              color: Color(0xffd7dde8),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: '拖动左侧边缘可调整宽度；双击恢复默认宽度',
                          child: ValueListenableBuilder<double>(
                            valueListenable: _wirePanelLiveWidth,
                            builder: (context, liveWidth, _) {
                              final width = _wireActivePointerId == null
                                  ? _wirePanelWidth
                                  : liveWidth;
                              return Text(
                                '${_clampWirePanelWidth(width).round()} px',
                                style: const TextStyle(
                                  color: Color(0xff697386),
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        wireLabelButton(compact: true),
                        IconButton(
                          tooltip: '全屏显示电线模式',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _wireModeFullscreen = true;
                            });
                          },
                          icon: const Icon(
                            Icons.fullscreen_rounded,
                            size: 19,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭电线模式',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _wireModeEnabled = false;
                              _wireModeFullscreen = false;
                            });
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: codeFlow),
              ],
            ),
            if (fullscreen)
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: const Color(0xff15191f).withOpacity(0.94),
                  elevation: 3,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xff2b333e),
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        wireLabelButton(compact: true),
                        IconButton(
                          tooltip: '退出全屏',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () {
                            setState(() {
                              _wireModeFullscreen = false;
                            });
                          },
                          icon: const Icon(
                            Icons.fullscreen_exit_rounded,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭电线模式',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () {
                            setState(() {
                              _wireModeEnabled = false;
                              _wireModeFullscreen = false;
                            });
                          },
                          icon: const Icon(Icons.close, size: 17),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          pathFilter:
              viewMode.isConcept ? (path) => viewMode.allowsPath(path) : null,
        ),
        Expanded(
          child: IdeEditorPanelSplit(
            panelExpanded: showConsole,
            editor: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    Expanded(
                      child: MonacoCodeEditorPanel(
                        controller: controller,
                        labels: labels,
                        labelModeEnabled: labelModeEnabled,
                        wireModeEnabled: wireModeEnabled,
                      ),
                    ),
                    ErrorPanel(controller: controller, maxHeight: 110),
                  ],
                ),
                if (viewMode.isSourceControl && sourceDiffPath != null)
                  Positioned.fill(
                    child: WorkspaceDiffPanel(
                      workspace: controller.workspace,
                      path: sourceDiffPath!,
                      onClose: onCloseSourceDiff,
                    ),
                  ),
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
            icon:
                explorerVisible ? Icons.menu_open_rounded : Icons.menu_rounded,
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
