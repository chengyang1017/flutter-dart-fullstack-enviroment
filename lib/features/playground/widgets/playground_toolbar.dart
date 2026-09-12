import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/workbench_palette.dart';
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

  @override
  Widget build(BuildContext context) {
    final canExport =
        controller.workspace.isDirty && supportsWorkspaceExportDownload;
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;

    const dartFrog = DartFrogWorkspaceService();
    const serverpod = ServerpodWorkspaceService();

    final dartFrogEnabled = dartFrog.isEnabled(controller.workspace);
    final serverpodEnabled = serverpod.isEnabled(controller.workspace);
    final backendUrl = runner.session?.backendUrl;
    final apiLabUrl =
        dartFrogEnabled && runner.canHotReload ? backendUrl : null;

    final workbenchTheme = Theme.of(context).copyWith(
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shadowColor: Theme.of(context).shadowColor,
        textStyle: TextStyle(
          color: palette.text,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.text,
        iconColor: palette.muted,
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        space: 1,
        thickness: 1,
      ),
    );

    return Theme(
      data: workbenchTheme,
      child: Material(
        color: palette.surface,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: palette.border),
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
                  label: runner.isMock
                      ? l10n.tr('模拟运行', 'Run Mock')
                      : l10n.tr('运行', 'Run'),
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
                  tooltip: l10n.tr('快速预览', 'Quick Preview'),
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
                  tooltip: l10n.tr('停止', 'Stop'),
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
                  tooltip: controller.autoRun
                      ? l10n.tr('关闭自动预览', 'Disable auto preview')
                      : l10n.tr('开启自动预览', 'Enable auto preview'),
                  icon: controller.autoRun
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  selected: controller.autoRun,
                  onPressed: controller.toggleAutoRun,
                ),
                const AppLanguageToggleButton(compact: true),
                const AppThemeToggleButton(compact: true),
                _ToolbarIconAction(
                  tooltip: controller.darkPreview
                      ? l10n.tr('切换浅色预览', 'Switch preview to light')
                      : l10n.tr('切换深色预览', 'Switch preview to dark'),
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
      label = context.l10n.tr('后端', 'Backend');
      icon = Icons.account_tree_outlined;
    }

    return PopupMenuButton<_BackendChoice>(
      key: const ValueKey('backend-workspace-menu'),
      enabled: runner.canRun,
      tooltip: context.l10n.tr('选择后端环境', 'Choose backend environment'),
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
            subtitle: context.l10n.tr('轻量 Dart API 后端', 'Lightweight Dart API backend'),
            selected: dartFrogEnabled,
          ),
        ),
        PopupMenuItem(
          value: _BackendChoice.serverpod,
          child: _BackendMenuItem(
            icon: Icons.hub_outlined,
            title: 'Serverpod',
            subtitle: context.l10n.tr('Flutter 全栈后端', 'Flutter full-stack backend'),
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
    final palette = WorkbenchPalette.of(context);
    final menuTextStyle = TextStyle(
      color: palette.text,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final menuSubtextStyle = TextStyle(
      color: palette.muted,
      fontSize: 11.5,
    );

    return PopupMenuButton<_TransferAction>(
      tooltip: context.l10n.tr('ApplyKit 导入 / 导出', 'Import / export ApplyKit'),
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
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(
              context.l10n.tr('导入 ApplyKit', 'Import ApplyKit'),
              style: menuTextStyle,
            ),
            subtitle: Text(
              context.l10n.tr('应用一组 Workspace 修改', 'Apply a set of Workspace changes'),
              style: menuSubtextStyle,
            ),
          ),
        ),
        PopupMenuItem(
          value: _TransferAction.exportApplyKit,
          enabled: canExport,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.download_outlined),
            title: Text(
              context.l10n.tr('导出 ApplyKit', 'Export ApplyKit'),
              style: menuTextStyle,
            ),
            subtitle: Text(
              context.l10n.tr('导出当前 Workspace 修改', 'Export current Workspace changes'),
              style: menuSubtextStyle,
            ),
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
      tooltip: context.l10n.tr('预览设备', 'Preview device'),
      initialValue: controller.device,
      onSelected: controller.changeDevice,
      itemBuilder: (context) => [
        _deviceItem(
          context,
          PreviewDevice.androidPhone,
          Icons.phone_android,
          'Android Phone',
        ),
        _deviceItem(
          context,
          PreviewDevice.smallPhone,
          Icons.smartphone,
          'Small Phone',
        ),
        _deviceItem(
          context,
          PreviewDevice.tablet,
          Icons.tablet_android,
          'Tablet',
        ),
        _deviceItem(
          context,
          PreviewDevice.responsive,
          Icons.devices_outlined,
          'Responsive',
        ),
      ],
      child: _ToolbarIconSurface(
        icon: _deviceIcon(controller.device),
        tooltip: context.l10n.tr('设备', 'Device'),
      ),
    );
  }

  PopupMenuItem<PreviewDevice> _deviceItem(
    BuildContext context,
    PreviewDevice value,
    IconData icon,
    String label,
  ) {
    final selected = controller.device == value;
    final palette = WorkbenchPalette.of(context);

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: selected ? palette.accent : palette.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: palette.accent,
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
    final palette = WorkbenchPalette.of(context);
    final menuTextStyle = TextStyle(
      color: palette.text,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return PopupMenuButton<_MoreAction>(
      tooltip: context.l10n.tr('更多操作', 'More actions'),
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
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _MoreAction.clear,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.clear),
            title: Text(
              context.l10n.tr('清空代码', 'Clear code'),
              style: menuTextStyle,
            ),
          ),
        ),
        PopupMenuItem(
          value: _MoreAction.resetExample,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.restore),
            title: Text(
              context.l10n.tr('恢复示例', 'Restore example'),
              style: menuTextStyle,
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MoreAction.supportedWidgets,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.help_outline),
            title: Text(
              context.l10n.tr(
                'Quick Preview 支持组件',
                'Quick Preview supported widgets',
              ),
              style: menuTextStyle,
            ),
          ),
        ),
      ],
      child: _ToolbarIconSurface(
        icon: Icons.more_horiz_rounded,
        tooltip: context.l10n.tr('更多', 'More'),
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
          context.l10n.tr(
            '当前 Workspace 已启用 $current。请新建或重置练习后再启用 $requested。',
            'This Workspace already uses $current. Create or reset the exercise before enabling $requested.',
          ),
        ),
      ),
    );
  }

  void _showFrameworkError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.tr(
            '全栈环境创建失败：$error',
            'Failed to create the full-stack environment: $error',
          ),
        ),
      ),
    );
  }

  Future<void> _importWorkspace(BuildContext context) async {
    if (controller.workspace.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            dialogContext.l10n.tr(
              '导入新的 ApplyKit？',
              'Import a new ApplyKit?',
            ),
          ),
          content: Text(
            dialogContext.l10n.tr(
              '当前 Workspace 有未导出的修改。导入会恢复基线后应用 ApplyKit 中的修改。',
              'The current Workspace has unexported changes. Importing restores the baseline before applying the ApplyKit changes.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.tr('继续导入', 'Continue import')),
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
            context.l10n.tr(
              '已导入 ${manifest.changes.length} 个 Workspace 修改。',
              'Imported ${manifest.changes.length} Workspace changes.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('导入失败：$error', 'Import failed: $error'),
          ),
        ),
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
            context.l10n.tr(
              '已导出 ${bundle.manifest.changes.length} 个修改：${bundle.fileName}',
              'Exported ${bundle.manifest.changes.length} changes: ${bundle.fileName}',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('导出失败：$error', 'Export failed: $error'),
          ),
        ),
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
    final palette = WorkbenchPalette.of(context);
    return SizedBox(
      height: 36,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          disabledBackgroundColor: palette.surfaceRaised,
          disabledForegroundColor: palette.muted.withValues(alpha: .42),
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
    final palette = WorkbenchPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          maximumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          backgroundColor: selected && enabled ? palette.selection : null,
          foregroundColor: selected && enabled
              ? palette.accent
              : enabled
                  ? palette.muted
                  : palette.muted.withValues(alpha: .32),
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
    final palette = WorkbenchPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 36,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: onPressed == null
                ? palette.muted.withValues(alpha: .32)
                : palette.text,
            backgroundColor: palette.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: BorderSide(color: palette.border),
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
    final palette = WorkbenchPalette.of(context);
    final foreground =
        enabled ? palette.text : palette.muted.withValues(alpha: .34);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border),
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
    final palette = WorkbenchPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: palette.muted,
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
    final palette = WorkbenchPalette.of(context);
    return SizedBox(
      height: 24,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: palette.border,
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
    final palette = WorkbenchPalette.of(context);
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: selected ? palette.accent : palette.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: palette.accent,
            ),
        ],
      ),
    );
  }
}
