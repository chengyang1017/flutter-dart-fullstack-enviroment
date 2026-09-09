import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter/services.dart';

import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/models/run_session.dart';
import '../../runner/widgets/runner_console_panel.dart';

/// A VS Code-style horizontal sash between the editor and bottom panel.
///
/// The sash updates a layout notifier directly. [CustomMultiChildLayout]
/// listens to that notifier through its delegate, so dragging relayouts the
/// two panes without rebuilding Monaco, the terminal, or the surrounding IDE.
class IdeEditorPanelSplit extends StatefulWidget {
  const IdeEditorPanelSplit({
    super.key,
    required this.editor,
    required this.panel,
    required this.panelExpanded,
  });

  final Widget editor;
  final Widget panel;
  final bool panelExpanded;

  @override
  State<IdeEditorPanelSplit> createState() => _IdeEditorPanelSplitState();
}

class _IdeEditorPanelSplitState extends State<IdeEditorPanelSplit> {
  static const _collapsedPanelHeight = 36.0;
  static const _defaultPanelHeight = 260.0;
  static const _minPanelHeight = 120.0;
  static const _minEditorHeight = 120.0;
  static const _sashHeight = 6.0;
  static const _keyboardStep = 20.0;

  late final ValueNotifier<double> _panelHeight;
  late final ValueNotifier<double?> _previewPanelHeight;
  late final ValueNotifier<bool> _sashHighlighted;
  final FocusNode _sashFocusNode =
      FocusNode(debugLabel: 'IDE bottom panel sash');

  final GlobalKey _splitSurfaceKey = GlobalKey();

  int? _activePointerId;
  double _dragPointerOffsetInSash = _sashHeight / 2;
  double _dragStartPanelHeight = _defaultPanelHeight;
  double _availableHeight = 0;
  bool _dragShieldVisible = false;
  bool _globalPointerRouteInstalled = false;

  @override
  void initState() {
    super.initState();
    _panelHeight = ValueNotifier<double>(_defaultPanelHeight);
    _previewPanelHeight = ValueNotifier<double?>(null);
    _sashHighlighted = ValueNotifier<bool>(false);
  }

  @override
  void dispose() {
    _removeGlobalPointerRoute();
    _panelHeight.dispose();
    _previewPanelHeight.dispose();
    _sashHighlighted.dispose();
    _sashFocusNode.dispose();
    super.dispose();
  }

  double _clampPanelHeight(double requested) {
    final maxHeight = math
        .max(
          _collapsedPanelHeight,
          _availableHeight - _minEditorHeight - _sashHeight,
        )
        .toDouble();
    final minHeight = math.min(_minPanelHeight, maxHeight).toDouble();
    return requested.clamp(minHeight, maxHeight).toDouble();
  }

  void _beginResize(PointerDownEvent event) {
    if (!widget.panelExpanded || _activePointerId != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }

    _activePointerId = event.pointer;
    _dragPointerOffsetInSash =
        event.localPosition.dy.clamp(0.0, _sashHeight).toDouble();
    _dragStartPanelHeight = _clampPanelHeight(_panelHeight.value);
    _previewPanelHeight.value = _dragStartPanelHeight;
    _sashHighlighted.value = true;
    _sashFocusNode.requestFocus();

    // Flutter Monaco 3.4.3 hosts Monaco in an iframe on Flutter Web. The
    // iframe wins browser hit testing unless we install the package's own DOM
    // overlay shield. Keep a global Flutter pointer route for the active drag,
    // then reveal a MonacoOverlayBoundary over the whole split surface so
    // pointer move/up events continue reaching Flutter even above the editor.
    _installGlobalPointerRoute();
    if (!_dragShieldVisible && mounted) {
      setState(() => _dragShieldVisible = true);
    }
  }

  void _installGlobalPointerRoute() {
    if (_globalPointerRouteInstalled) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _globalPointerRouteInstalled = true;
  }

  void _removeGlobalPointerRoute() {
    if (!_globalPointerRouteInstalled) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _globalPointerRouteInstalled = false;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    final activePointer = _activePointerId;
    if (activePointer == null || event.pointer != activePointer) return;

    if (event is PointerMoveEvent) {
      _updateResizeFromGlobalPosition(event.position);
      return;
    }

    if (event is PointerUpEvent) {
      _finishResize(activePointer, commit: true);
      return;
    }

    if (event is PointerCancelEvent) {
      _finishResize(activePointer, commit: false);
    }
  }

  void _updateResizeFromGlobalPosition(Offset globalPosition) {
    if (!widget.panelExpanded) return;

    final context = _splitSurfaceKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final localY = renderObject.globalToLocal(globalPosition).dy;
    final requested =
        _availableHeight - localY - _sashHeight + _dragPointerOffsetInSash;
    final next = _clampPanelHeight(requested);

    // Match IDE sash behavior: update only the split layout notifier while the
    // pointer moves. This relayouts the editor and terminal without rebuilding
    // Monaco, the terminal widget tree, or the surrounding workbench.
    if (next != _panelHeight.value) {
      _panelHeight.value = next;
      _previewPanelHeight.value = next;
    }
  }

  void _finishResize(int pointer, {required bool commit}) {
    if (pointer != _activePointerId) return;

    _previewPanelHeight.value = null;
    if (!commit) {
      _panelHeight.value = _clampPanelHeight(_dragStartPanelHeight);
    }

    _activePointerId = null;
    _removeGlobalPointerRoute();
    _sashHighlighted.value = false;
    if (_dragShieldVisible && mounted) {
      setState(() => _dragShieldVisible = false);
    }
  }

  void _resetHeight() {
    _panelHeight.value = _clampPanelHeight(_defaultPanelHeight);
  }

  KeyEventResult _handleSashKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.panelExpanded) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.home) {
      _resetHeight();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _panelHeight.value = _clampPanelHeight(
        _panelHeight.value + _keyboardStep,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _panelHeight.value = _clampPanelHeight(
        _panelHeight.value - _keyboardStep,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSash() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => _sashHighlighted.value = true,
      onExit: (_) {
        if (_activePointerId == null) {
          _sashHighlighted.value = false;
        }
      },
      child: Focus(
        focusNode: _sashFocusNode,
        onKeyEvent: _handleSashKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _resetHeight,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _beginResize,
            child: ValueListenableBuilder<bool>(
              valueListenable: _sashHighlighted,
              builder: (context, highlighted, _) {
                return ColoredBox(
                  color: const Color(0xff15191f),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: double.infinity,
                      height: 2,
                      color: highlighted
                          ? const Color(0xff6a7b94)
                          : const Color(0xff303641),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _availableHeight = constraints.maxHeight;
        return Stack(
          key: _splitSurfaceKey,
          fit: StackFit.expand,
          children: [
            CustomMultiChildLayout(
              delegate: _IdeEditorPanelLayoutDelegate(
                panelExpanded: widget.panelExpanded,
                panelHeight: _panelHeight,
              ),
              children: [
                LayoutId(
                  id: _IdeSplitSlot.editor,
                  child: RepaintBoundary(child: widget.editor),
                ),
                LayoutId(
                  id: _IdeSplitSlot.sash,
                  child: widget.panelExpanded
                      ? _buildSash()
                      : const SizedBox.shrink(),
                ),
                LayoutId(
                  id: _IdeSplitSlot.panel,
                  child: RepaintBoundary(child: widget.panel),
                ),
              ],
            ),
            if (_dragShieldVisible)
              Positioned.fill(
                child: MonacoOverlayBoundary(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Colors.transparent),
                          ValueListenableBuilder<double?>(
                            valueListenable: _previewPanelHeight,
                            builder: (context, previewHeight, _) {
                              if (previewHeight == null) {
                                return const SizedBox.shrink();
                              }

                              final clamped = _clampPanelHeight(previewHeight);
                              final top = math
                                  .max(
                                    0.0,
                                    _availableHeight -
                                        clamped -
                                        _sashHeight / 2,
                                  )
                                  .toDouble();

                              return Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: top,
                                    bottom: 0,
                                    child: const IgnorePointer(
                                      child: ColoredBox(
                                        color: Color(0x0d6a7b94),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: top,
                                    child: const IgnorePointer(
                                      child: SizedBox(
                                        height: 2,
                                        child: ColoredBox(
                                          color: Color(0xff8b9db8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
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
}

enum _IdeSplitSlot { editor, sash, panel }

class _IdeEditorPanelLayoutDelegate extends MultiChildLayoutDelegate {
  _IdeEditorPanelLayoutDelegate({
    required this.panelExpanded,
    required this.panelHeight,
  }) : super(relayout: panelHeight);

  final bool panelExpanded;
  final ValueNotifier<double> panelHeight;

  @override
  void performLayout(Size size) {
    final sashHeight =
        panelExpanded ? _IdeEditorPanelSplitState._sashHeight : 0.0;

    final maxPanelHeight = math
        .max(
          _IdeEditorPanelSplitState._collapsedPanelHeight,
          size.height - _IdeEditorPanelSplitState._minEditorHeight - sashHeight,
        )
        .toDouble();
    final minPanelHeight = math
        .min(
          _IdeEditorPanelSplitState._minPanelHeight,
          maxPanelHeight,
        )
        .toDouble();
    final expandedHeight =
        panelHeight.value.clamp(minPanelHeight, maxPanelHeight).toDouble();
    final requestedPanelHeight = panelExpanded
        ? expandedHeight
        : _IdeEditorPanelSplitState._collapsedPanelHeight;
    final actualPanelHeight = math
        .min(
          size.height,
          requestedPanelHeight,
        )
        .toDouble();
    final editorHeight = math
        .max(
          0.0,
          size.height - actualPanelHeight - sashHeight,
        )
        .toDouble();

    if (hasChild(_IdeSplitSlot.editor)) {
      layoutChild(
        _IdeSplitSlot.editor,
        BoxConstraints.tightFor(
          width: size.width,
          height: editorHeight,
        ),
      );
      positionChild(_IdeSplitSlot.editor, Offset.zero);
    }

    if (hasChild(_IdeSplitSlot.sash)) {
      layoutChild(
        _IdeSplitSlot.sash,
        BoxConstraints.tightFor(
          width: size.width,
          height: sashHeight,
        ),
      );
      positionChild(_IdeSplitSlot.sash, Offset(0, editorHeight));
    }

    if (hasChild(_IdeSplitSlot.panel)) {
      layoutChild(
        _IdeSplitSlot.panel,
        BoxConstraints.tightFor(
          width: size.width,
          height: actualPanelHeight,
        ),
      );
      positionChild(
        _IdeSplitSlot.panel,
        Offset(0, editorHeight + sashHeight),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _IdeEditorPanelLayoutDelegate oldDelegate) {
    return panelExpanded != oldDelegate.panelExpanded;
  }
}

/// VS Code-like bottom panel for Flutter Runner output.
class IdeBottomPanel extends StatefulWidget {
  const IdeBottomPanel({
    super.key,
    required this.runner,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final FlutterRunnerController runner;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<IdeBottomPanel> createState() => _IdeBottomPanelState();
}

class _IdeBottomPanelState extends State<IdeBottomPanel> {
  static const background = Color(0xff111318);
  static const header = Color(0xff15181e);
  static const border = Color(0xff262a32);
  static const muted = Color(0xff7f8795);
  static const text = Color(0xffd7dae0);
  static const accent = Color(0xff7c5cff);

  final List<_ConsoleView> _views = <_ConsoleView>[
    const _ConsoleView(id: 1, startIndex: 0),
  ];

  int _activeViewId = 1;
  int _nextViewId = 2;

  _ConsoleView get _activeView =>
      _views.firstWhere((view) => view.id == _activeViewId);

  void _createView() {
    final view = _ConsoleView(
      id: _nextViewId++,
      startIndex: widget.runner.logs.length,
    );
    setState(() {
      _views.add(view);
      _activeViewId = view.id;
    });
    if (!widget.expanded) widget.onExpandedChanged(true);
  }

  void _closeView(int id) {
    if (_views.length == 1) {
      widget.onExpandedChanged(false);
      return;
    }

    final index = _views.indexWhere((view) => view.id == id);
    if (index < 0) return;

    setState(() {
      _views.removeAt(index);
      if (_activeViewId == id) {
        final nextIndex = index.clamp(0, _views.length - 1).toInt();
        _activeViewId = _views[nextIndex].id;
      }
    });
  }

  void _selectView(int id) {
    if (_activeViewId != id) setState(() => _activeViewId = id);
    if (!widget.expanded) widget.onExpandedChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: header,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          _PanelHeader(
            runner: widget.runner,
            views: _views,
            activeViewId: _activeViewId,
            expanded: widget.expanded,
            onSelectView: _selectView,
            onCloseView: _closeView,
            onCreateView: _createView,
            onToggleExpanded: () => widget.onExpandedChanged(!widget.expanded),
          ),
          if (widget.expanded)
            Expanded(
              child: RepaintBoundary(
                child: ColoredBox(
                  color: background,
                  child: ClipRect(
                    child: Column(
                      children: [
                        Expanded(
                          child: RunnerConsolePanel(
                            key: ValueKey(
                              'runner-console-view-${_activeView.id}',
                            ),
                            runner: widget.runner,
                            showHeader: false,
                            logStartIndex: _activeView.startIndex,
                          ),
                        ),
                        _TerminalCommandBar(
                          key: ValueKey(
                            'terminal-command-${_activeView.id}',
                          ),
                          onSubmit: widget.runner.canRunTerminalCommand
                              ? widget.runner.runTerminalCommand
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.runner,
    required this.views,
    required this.activeViewId,
    required this.expanded,
    required this.onSelectView,
    required this.onCloseView,
    required this.onCreateView,
    required this.onToggleExpanded,
  });

  final FlutterRunnerController runner;
  final List<_ConsoleView> views;
  final int activeViewId;
  final bool expanded;
  final ValueChanged<int> onSelectView;
  final ValueChanged<int> onCloseView;
  final VoidCallback onCreateView;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(
            Icons.terminal_outlined,
            size: 15,
            color: _IdeBottomPanelState.muted,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: views.length,
              separatorBuilder: (_, __) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final view = views[index];
                return _ConsoleTab(
                  label: 'Terminal ${view.id}',
                  active: view.id == activeViewId,
                  onTap: () => onSelectView(view.id),
                  onClose: () => onCloseView(view.id),
                );
              },
            ),
          ),
          _RunnerStatusBadge(status: runner.status),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              runner.runnerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: _IdeBottomPanelState.muted,
              ),
            ),
          ),
          const SizedBox(width: 5),
          _PanelIconButton(
            tooltip: '新建 Terminal 窗口',
            icon: Icons.add,
            onPressed: onCreateView,
          ),
          _PanelIconButton(
            tooltip: '清空 Runner 日志',
            icon: Icons.delete_sweep_outlined,
            onPressed: runner.logs.isEmpty ? null : runner.clearConsole,
          ),
          _PanelIconButton(
            tooltip: expanded ? '收起 Panel' : '展开 Panel',
            icon:
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            onPressed: onToggleExpanded,
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }
}

class _TerminalCommandBar extends StatefulWidget {
  const _TerminalCommandBar({
    super.key,
    required this.onSubmit,
  });

  final Future<void> Function(String command)? onSubmit;

  @override
  State<_TerminalCommandBar> createState() => _TerminalCommandBarState();
}

class _TerminalCommandBarState extends State<_TerminalCommandBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _history = <String>[];
  int _historyIndex = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty || _submitting || widget.onSubmit == null) return;
    _history.remove(command);
    _history.add(command);
    _historyIndex = _history.length;
    _controller.clear();
    setState(() => _submitting = true);
    try {
      await widget.onSubmit!(command);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _focusNode.requestFocus();
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _history.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyIndex = (_historyIndex - 1).clamp(0, _history.length - 1);
      _showHistory();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _historyIndex = (_historyIndex + 1).clamp(0, _history.length);
      if (_historyIndex == _history.length) {
        _controller.clear();
      } else {
        _showHistory();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showHistory() {
    final value = _history[_historyIndex];
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onSubmit != null;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _IdeBottomPanelState.background,
        border: Border(
          top: BorderSide(color: _IdeBottomPanelState.border),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '>',
            style: TextStyle(
              fontFamily: 'Cascadia Code',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _IdeBottomPanelState.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: enabled && !_submitting,
                onSubmitted: _submit,
                maxLines: 1,
                cursorColor: const Color(0xffc7ccd6),
                style: const TextStyle(
                  fontFamily: 'Cascadia Code',
                  fontFamilyFallback: ['Consolas', 'monospace'],
                  fontSize: 12,
                  color: _IdeBottomPanelState.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: enabled
                      ? '输入命令并按 Enter，例如 flutter --version'
                      : '连接真实 Flutter Runner 后可执行命令',
                  hintStyle: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xff626b79),
                  ),
                ),
              ),
            ),
          ),
          if (_submitting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
        ],
      ),
    );
  }
}

class _ConsoleTab extends StatelessWidget {
  const _ConsoleTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color:
                    active ? _IdeBottomPanelState.accent : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cascadia Code',
                  fontFamilyFallback: const ['Consolas', 'monospace'],
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? _IdeBottomPanelState.text
                      : _IdeBottomPanelState.muted,
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 26,
                child: IconButton(
                  tooltip: '关闭窗口',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close,
                    size: 13,
                    color: active
                        ? const Color(0xffaeb4bf)
                        : const Color(0xff626b79),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 31,
      height: 31,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: const Color(0xffaeb4bf),
        disabledColor: const Color(0xff4f5663),
      ),
    );
  }
}

class _RunnerStatusBadge extends StatelessWidget {
  const _RunnerStatusBadge({required this.status});

  final RunnerStatus status;

  @override
  Widget build(BuildContext context) {
    final isError = status == RunnerStatus.error;
    final isRunning = status == RunnerStatus.running;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isError
            ? const Color(0xff3d2024)
            : isRunning
                ? const Color(0xff173524)
                : const Color(0xff252a33),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: isError
              ? const Color(0xffff9b9b)
              : isRunning
                  ? const Color(0xff8de5ad)
                  : const Color(0xffb8c0cc),
        ),
      ),
    );
  }
}

class _ConsoleView {
  const _ConsoleView({required this.id, required this.startIndex});

  final int id;
  final int startIndex;
}
