import 'package:flutter/material.dart';

import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/runner_console_panel.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/widgets/workspace_editor_tabs.dart';
import '../../workspace/widgets/workspace_file_explorer.dart';
import '../controllers/playground_controller.dart';
import 'code_editor_panel.dart';
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
                    runner: widget.runner,
                    showConsole: _showConsole,
                    wireModeEnabled: _wireModeEnabled,
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
                    explorerVisible: _showExplorer,
                    previewVisible: _showPreview,
                  ),
                ),
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
    required this.runner,
    required this.showConsole,
    required this.wireModeEnabled,
    required this.onToggleConsole,
    required this.onToggleExplorer,
    required this.onTogglePreview,
    required this.onToggleWireMode,
    required this.explorerVisible,
    required this.previewVisible,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final bool showConsole;
  final bool wireModeEnabled;
  final bool explorerVisible;
  final bool previewVisible;
  final VoidCallback onToggleConsole;
  final VoidCallback onToggleExplorer;
  final VoidCallback onTogglePreview;
  final VoidCallback onToggleWireMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EditorCommandBar(
          controller: controller,
          explorerVisible: explorerVisible,
          previewVisible: previewVisible,
          wireModeEnabled: wireModeEnabled,
          onToggleExplorer: onToggleExplorer,
          onTogglePreview: onTogglePreview,
          onToggleWireMode: onToggleWireMode,
        ),
        WorkspaceEditorTabs(
          workspace: controller.workspace,
          onSelect: controller.selectWorkspaceFile,
          onClose: controller.closeWorkspaceFile,
        ),
        Expanded(
          child: CodeEditorPanel(
            controller: controller,
            wireModeEnabled: wireModeEnabled,
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
    required this.onToggleExplorer,
    required this.onTogglePreview,
    required this.onToggleWireMode,
  });

  final PlaygroundController controller;
  final bool explorerVisible;
  final bool previewVisible;
  final bool wireModeEnabled;
  final VoidCallback onToggleExplorer;
  final VoidCallback onTogglePreview;
  final VoidCallback onToggleWireMode;

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
            tooltip: explorerVisible ? '收起文件树' : '展开文件树',
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
            tooltip: wireModeEnabled ? '关闭代码电线模式' : '打开代码电线模式',
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
            tooltip: previewVisible ? '收起设备预览' : '展开设备预览',
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
                    tooltip: '收起',
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
