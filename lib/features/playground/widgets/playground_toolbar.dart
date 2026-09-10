import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../export/services/workspace_export_download.dart';
import '../../export/services/workspace_export_service.dart';
import '../../export/services/workspace_import_picker.dart';
import '../../export/services/workspace_import_service.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/dart_frog_api_lab_dialog.dart';
import '../../workspace/services/dart_frog_workspace_service.dart';
import '../../workspace/services/serverpod_workspace_service.dart';
import '../controllers/playground_controller.dart';
import 'supported_widgets_dialog.dart';

enum _BackendChoice {
  dartFrog,
  serverpod,
}

enum _TransferAction {
  importApplyKit,
  exportApplyKit,
}

enum _MoreAction {
  clear,
  resetExample,
  supportedWidgets,
}

class PlaygroundToolbar extends StatelessWidget {
  const PlaygroundToolbar({
    super.key,
    required this.controller,
    required this.runner,
    this.compact = false,
    this.projectControls,
    this.onRun,
    this.onQuickPreview,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final bool compact;
  final Widget? projectControls;
  final VoidCallback? onRun;
  final VoidCallback? onQuickPreview;

  static const _background = Color(0xff111318);
  static const _surface = Color(0xff15191f);
  static const _surfaceSelected = Color(0xff22324a);
  static const _border = Color(0xff2b333e);
  static const _divider = Color(0xff272d36);
  static const _text = Color(0xffd7dde8);
  static const _muted = Color(0xff8f98a8);
  static const _accent = Color(0xff82aaff);
  static const _run = Color(0xff356a9c);
  static const _menuTextStyle = TextStyle(
    color: _text,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static const _menuSubtextStyle = TextStyle(
    color: _muted,
    fontSize: 11.5,
  );

  @override
  Widget build(BuildContext context) {
    final canExport =
        controller.workspace.isDirty && supportsWorkspaceExportDownload;

    const dartFrog = DartFrogWorkspaceService();
    const serverpod = ServerpodWorkspaceService();

    final dartFrogEnabled = dartFrog.isEnabled(controller.workspace);
    final serverpodEnabled = serverpod.isEnabled(controller.workspace);
    final backendUrl = runner.session?.backendUrl;
    final apiLabUrl =
        dartFrogEnabled && runner.canHotReload ? backendUrl : null;

    final workbenchTheme = Theme.of(context).copyWith(
      popupMenuTheme: PopupMenuThemeData(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: .45),
        textStyle: const TextStyle(
          color: _text,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: _text,
        iconColor: _muted,
      ),
      dividerTheme: const DividerThemeData(
        color: _border,
        space: 1,
        thickness: 1,
      ),
    );

    return Theme(
      data: workbenchTheme,
      child: Material(
        color: _background,
        child: Container(
          height: 50,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _divider),
            ),
          ),
          child: SingleChildScrollView(
            key: const ValueKey('playground-toolbar-scroll'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (projectControls != null) ...[
                  projectControls!,
                  const SizedBox(width: 10),
                  const _TopDivider(),
                  const SizedBox(width: 10),
                ],
                _RunButton(
                  enabled: runner.canRun,
                  label: runner.isMock ? 'Run Mock' : 'Run',
                  onPressed: runner.canRun ? (onRun ?? runner.run) : null,
                ),
                const SizedBox(width: 6),
                _buildBackendButton(
                  context,
                  dartFrog: dartFrog,
                  serverpod: serverpod,
                  dartFrogEnabled: dartFrogEnabled,
                  serverpodEnabled: serverpodEnabled,
                ),
                if (dartFrogEnabled) ...[
                  const SizedBox(width: 4),
                  _ToolbarTextAction(
                    tooltip: 'Dart Frog API Lab',
                    icon: Icons.http_rounded,
                    label: 'API',
                    onPressed: apiLabUrl != null
                        ? () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => DartFrogApiLabDialog(
                                baseUrl: apiLabUrl,
                              ),
                            );
                          }
                        : null,
                  ),
                ],
                const SizedBox(width: 10),
                const _TopDivider(),
                const SizedBox(width: 6),
                _ToolbarIconAction(
                  tooltip: '快速预览',
                  icon: Icons.bolt_rounded,
                  onPressed: onQuickPreview ?? controller.runCode,
                ),
                _ToolbarIconAction(
                  tooltip: 'Hot Reload',
                  icon: Icons.refresh_rounded,
                  onPressed: runner.canHotReload ? runner.hotReload : null,
                ),
                _ToolbarIconAction(
                  tooltip: 'Hot Restart',
                  icon: Icons.restart_alt_rounded,
                  onPressed: runner.canHotRestart ? runner.hotRestart : null,
                ),
                _ToolbarIconAction(
                  tooltip: 'Stop',
                  icon: Icons.stop_rounded,
                  onPressed: runner.canStop ? runner.stop : null,
                ),
                const SizedBox(width: 6),
                const _TopDivider(),
                const SizedBox(width: 6),
                _buildTransferButton(
                  context,
                  canExport: canExport,
                ),
                const SizedBox(width: 6),
                const _TopDivider(),
                const SizedBox(width: 6),
                _ToolbarIconAction(
                  tooltip: controller.autoRun ? '关闭自动预览' : '开启自动预览',
                  icon: controller.autoRun
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  selected: controller.autoRun,
                  onPressed: controller.toggleAutoRun,
                ),
                const AppThemeToggleButton(compact: true),
                _ToolbarIconAction(
                  tooltip: controller.darkPreview ? '切换浅色预览' : '切换深色预览',
                  icon: controller.darkPreview
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  selected: controller.darkPreview,
                  onPressed: controller.togglePreviewTheme,
                ),
                _buildDeviceButton(context),
                const SizedBox(width: 2),
                _buildMoreButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackendButton(
    BuildContext context, {
    required DartFrogWorkspaceService dartFrog,
    required ServerpodWorkspaceService serverpod,
    required bool dartFrogEnabled,
    required bool serverpodEnabled,
  }) {
    final String label;
    final IconData icon;

    if (dartFrogEnabled) {
      label = 'Dart Frog';
      icon = Icons.api_rounded;
    } else if (serverpodEnabled) {
      label = 'Serverpod';
      icon = Icons.hub_outlined;
    } else {
      label = '后端';
      icon = Icons.account_tree_outlined;
    }

    return PopupMenuButton<_BackendChoice>(
      key: const ValueKey('backend-workspace-menu'),
      enabled: runner.canRun,
      tooltip: '选择后端环境',
      onSelected: (choice) {
        switch (choice) {
          case _BackendChoice.dartFrog:
            _enableDartFrog(
              context,
              dartFrog,
              serverpodEnabled: serverpodEnabled,
            );
            break;
          case _BackendChoice.serverpod:
            _enableServerpod(
              context,
              serverpod,
              dartFrogEnabled: dartFrogEnabled,
            );
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _BackendChoice.dartFrog,
          child: _BackendMenuItem(
            icon: Icons.api_rounded,
            title: 'Dart Frog',
            subtitle: '轻量 Dart API 后端',
            selected: dartFrogEnabled,
          ),
        ),
        PopupMenuItem(
          value: _BackendChoice.serverpod,
          child: _BackendMenuItem(
            icon: Icons.hub_outlined,
            title: 'Serverpod',
            subtitle: 'Flutter 全栈后端',
            selected: serverpodEnabled,
          ),
        ),
      ],
      child: _ToolbarPopupSurface(
        enabled: runner.canRun,
        icon: icon,
        label: label,
      ),
    );
  }

  Widget _buildTransferButton(
    BuildContext context, {
    required bool canExport,
  }) {
    final canImport = supportsWorkspaceImportPicker;
    return PopupMenuButton<_TransferAction>(
      tooltip: 'ApplyKit 导入 / 导出',
      enabled: canImport || canExport,
      onSelected: (action) {
        switch (action) {
          case _TransferAction.importApplyKit:
            _importWorkspace(context);
            break;
          case _TransferAction.exportApplyKit:
            _exportWorkspace(context);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _TransferAction.importApplyKit,
          enabled: canImport,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: _muted,
            textColor: _text,
            leading: Icon(Icons.upload_file_outlined),
            title: Text('导入 ApplyKit', style: _menuTextStyle),
            subtitle: Text('应用一组 Workspace 修改', style: _menuSubtextStyle),
          ),
        ),
        PopupMenuItem(
          value: _TransferAction.exportApplyKit,
          enabled: canExport,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: _muted,
            textColor: _text,
            leading: Icon(Icons.download_outlined),
            title: Text('导出 ApplyKit', style: _menuTextStyle),
            subtitle: Text('导出当前 Workspace 修改', style: _menuSubtextStyle),
          ),
        ),
      ],
      child: _ToolbarPopupSurface(
        enabled: canImport || canExport,
        icon: Icons.sync_alt_rounded,
        label: 'ApplyKit',
      ),
    );
  }

  Widget _buildDeviceButton(BuildContext context) {
    return PopupMenuButton<PreviewDevice>(
      tooltip: '预览设备',
      initialValue: controller.device,
      onSelected: controller.changeDevice,
      itemBuilder: (context) => [
        _deviceItem(
          PreviewDevice.androidPhone,
          Icons.phone_android,
          'Android Phone',
        ),
        _deviceItem(
          PreviewDevice.smallPhone,
          Icons.smartphone,
          'Small Phone',
        ),
        _deviceItem(
          PreviewDevice.tablet,
          Icons.tablet_android,
          'Tablet',
        ),
        _deviceItem(
          PreviewDevice.responsive,
          Icons.devices_outlined,
          'Responsive',
        ),
      ],
      child: _ToolbarIconSurface(
        icon: _deviceIcon(controller.device),
        tooltip: '设备',
      ),
    );
  }

  PopupMenuItem<PreviewDevice> _deviceItem(
    PreviewDevice value,
    IconData icon,
    String label,
  ) {
    final selected = controller.device == value;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: selected ? _accent : _muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: _menuTextStyle,
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 18,
              color: _accent,
            ),
        ],
      ),
    );
  }

  IconData _deviceIcon(PreviewDevice value) {
    switch (value) {
      case PreviewDevice.androidPhone:
        return Icons.phone_android;
      case PreviewDevice.smallPhone:
        return Icons.smartphone;
      case PreviewDevice.tablet:
        return Icons.tablet_android;
      case PreviewDevice.responsive:
        return Icons.devices_outlined;
    }
  }

  Widget _buildMoreButton(BuildContext context) {
    return PopupMenuButton<_MoreAction>(
      tooltip: '更多操作',
      onSelected: (action) {
        switch (action) {
          case _MoreAction.clear:
            controller.clearCode();
            break;
          case _MoreAction.resetExample:
            controller.resetExample();
            break;
          case _MoreAction.supportedWidgets:
            showDialog<void>(
              context: context,
              builder: (_) => const SupportedWidgetsDialog(),
            );
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _MoreAction.clear,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: _muted,
            textColor: _text,
            leading: Icon(Icons.clear),
            title: Text('清空代码', style: _menuTextStyle),
          ),
        ),
        PopupMenuItem(
          value: _MoreAction.resetExample,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: _muted,
            textColor: _text,
            leading: Icon(Icons.restore),
            title: Text('恢复示例', style: _menuTextStyle),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _MoreAction.supportedWidgets,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: _muted,
            textColor: _text,
            leading: Icon(Icons.help_outline),
            title: Text(
              'Quick Preview 支持组件',
              style: _menuTextStyle,
            ),
          ),
        ),
      ],
      child: const _ToolbarIconSurface(
        icon: Icons.more_horiz_rounded,
        tooltip: '更多',
      ),
    );
  }

  void _enableDartFrog(
    BuildContext context,
    DartFrogWorkspaceService service, {
    required bool serverpodEnabled,
  }) {
    if (serverpodEnabled) {
      _showFrameworkConflict(
        context,
        current: 'Serverpod',
        requested: 'Dart Frog',
      );
      return;
    }

    try {
      service.ensureEnabled(controller.workspace);
      controller.selectWorkspaceFile(DartFrogWorkspaceService.backendRoutePath);
    } catch (error) {
      _showFrameworkError(context, error);
    }
  }

  void _enableServerpod(
    BuildContext context,
    ServerpodWorkspaceService service, {
    required bool dartFrogEnabled,
  }) {
    if (dartFrogEnabled) {
      _showFrameworkConflict(
        context,
        current: 'Dart Frog',
        requested: 'Serverpod',
      );
      return;
    }

    try {
      service.ensureEnabled(controller.workspace);
      controller
          .selectWorkspaceFile(ServerpodWorkspaceService.greetingEndpointPath);
    } catch (error) {
      _showFrameworkError(context, error);
    }
  }

  void _showFrameworkConflict(
    BuildContext context, {
    required String current,
    required String requested,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '当前 Workspace 已启用 $current。'
          '请新建或重置练习后再启用 $requested。',
        ),
      ),
    );
  }

  void _showFrameworkError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('全栈环境创建失败：$error')),
    );
  }

  Future<void> _importWorkspace(BuildContext context) async {
    if (controller.workspace.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入新的 ApplyKit？'),
          content: const Text(
            '当前 Workspace 有未导出的修改。'
            '导入会恢复基线后应用 ApplyKit 中的修改。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续导入'),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) {
        return;
      }
    }

    try {
      final bytes = await pickWorkspaceImport();
      if (bytes == null || !context.mounted) {
        return;
      }

      final manifest = const WorkspaceImportService().apply(
        bytes,
        controller.workspace,
      );

      controller.runCode();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${manifest.changes.length} 个 Workspace 修改。',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
    }
  }

  Future<void> _exportWorkspace(BuildContext context) async {
    try {
      final bundle = const WorkspaceExportService().build(controller.workspace);

      await downloadWorkspaceExport(
        bundle.bytes,
        bundle.fileName,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${bundle.manifest.changes.length} 个修改：'
            '${bundle.fileName}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$error')),
      );
    }
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: PlaygroundToolbar._run,
          foregroundColor: Colors.white,
          disabledBackgroundColor: PlaygroundToolbar._surface,
          disabledForegroundColor:
              PlaygroundToolbar._muted.withValues(alpha: .42),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ToolbarIconAction extends StatelessWidget {
  const _ToolbarIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          maximumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          backgroundColor:
              selected && enabled ? PlaygroundToolbar._surfaceSelected : null,
          foregroundColor: selected && enabled
              ? PlaygroundToolbar._accent
              : enabled
                  ? PlaygroundToolbar._muted
                  : PlaygroundToolbar._muted.withValues(alpha: .32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _ToolbarTextAction extends StatelessWidget {
  const _ToolbarTextAction({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 36,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: onPressed == null
                ? PlaygroundToolbar._muted.withValues(alpha: .32)
                : PlaygroundToolbar._text,
            backgroundColor: PlaygroundToolbar._surface,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: const BorderSide(color: PlaygroundToolbar._border),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ToolbarPopupSurface extends StatelessWidget {
  const _ToolbarPopupSurface({
    required this.enabled,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? PlaygroundToolbar._text
        : PlaygroundToolbar._muted.withValues(alpha: .34);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: PlaygroundToolbar._surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: PlaygroundToolbar._border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: foreground,
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconSurface extends StatelessWidget {
  const _ToolbarIconSurface({
    required this.icon,
    required this.tooltip,
  });

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: PlaygroundToolbar._muted,
          ),
        ),
      ),
    );
  }
}

class _TopDivider extends StatelessWidget {
  const _TopDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 24,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: PlaygroundToolbar._divider,
      ),
    );
  }
}

class _BackendMenuItem extends StatelessWidget {
  const _BackendMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color:
                selected ? PlaygroundToolbar._accent : PlaygroundToolbar._muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: PlaygroundToolbar._text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: PlaygroundToolbar._muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 18,
              color: PlaygroundToolbar._accent,
            ),
        ],
      ),
    );
  }
}
