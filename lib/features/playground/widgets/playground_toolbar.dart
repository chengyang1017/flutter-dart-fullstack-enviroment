import 'package:flutter/material.dart';

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
    this.onRun,
    this.onQuickPreview,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final bool compact;
  final VoidCallback? onRun;
  final VoidCallback? onQuickPreview;

  @override
  Widget build(BuildContext context) {
    final density = compact
        ? VisualDensity.compact
        : VisualDensity.standard;

    final canExport =
        controller.workspace.isDirty &&
        supportsWorkspaceExportDownload;

    const dartFrog =
        DartFrogWorkspaceService();

    const serverpod =
        ServerpodWorkspaceService();

    final dartFrogEnabled =
        dartFrog.isEnabled(
      controller.workspace,
    );

    final serverpodEnabled =
        serverpod.isEnabled(
      controller.workspace,
    );

    final backendUrl =
        runner.session?.backendUrl;

    final apiLabUrl =
        dartFrogEnabled &&
                runner.canHotReload
            ? backendUrl
            : null;

    return Material(
      color: Theme.of(context)
          .colorScheme
          .surface,
      child: Container(
        height: compact ? 58 : 62,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(
                    alpha: 0.55,
                  ),
            ),
          ),
        ),
        child: SingleChildScrollView(
          key: const ValueKey(
            'playground-toolbar-scroll',
          ),
          scrollDirection:
              Axis.horizontal,
          child: Row(
            children: [
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(
                  visualDensity: density,
                  minimumSize:
                      const Size(92, 40),
                ),
                onPressed: runner.canRun
                    ? (onRun ?? runner.run)
                    : null,
                icon: const Icon(
                  Icons.play_arrow_rounded,
                ),
                label: Text(
                  runner.isMock
                      ? 'Run Mock'
                      : 'Run',
                ),
              ),

              const SizedBox(width: 8),

              _buildBackendButton(
                context,
                density: density,
                dartFrog: dartFrog,
                serverpod: serverpod,
                dartFrogEnabled:
                    dartFrogEnabled,
                serverpodEnabled:
                    serverpodEnabled,
              ),

              if (dartFrogEnabled) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'dart-frog-api-lab-button',
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    visualDensity: density,
                    minimumSize:
                        const Size(0, 40),
                  ),
                  onPressed:
                      apiLabUrl != null
                          ? () {
                              showDialog<void>(
                                context:
                                    context,
                                builder: (_) =>
                                    DartFrogApiLabDialog(
                                  baseUrl:
                                      apiLabUrl,
                                ),
                              );
                            }
                          : null,
                  icon: const Icon(
                    Icons.http_rounded,
                    size: 19,
                  ),
                  label:
                      const Text(
                    'API',
                  ),
                ),
              ],

              const SizedBox(width: 12),

              _ToolbarGroup(
                children: [
                  _ToolbarIconButton(
                    tooltip: '快速预览',
                    icon:
                        Icons.bolt_rounded,
                    onPressed:
                        onQuickPreview ??
                            controller
                                .runCode,
                  ),
                  _ToolbarIconButton(
                    tooltip: 'Hot Reload',
                    icon:
                        Icons.refresh_rounded,
                    onPressed:
                        runner.canHotReload
                            ? runner
                                .hotReload
                            : null,
                  ),
                  _ToolbarIconButton(
                    tooltip:
                        'Hot Restart',
                    icon: Icons
                        .restart_alt_rounded,
                    onPressed:
                        runner.canHotRestart
                            ? runner
                                .hotRestart
                            : null,
                  ),
                  _ToolbarIconButton(
                    tooltip: 'Stop',
                    icon:
                        Icons.stop_rounded,
                    onPressed:
                        runner.canStop
                            ? runner.stop
                            : null,
                  ),
                ],
              ),

              const SizedBox(width: 12),

              _ToolbarGroup(
                children: [
                  _ToolbarTextButton(
                    icon: Icons
                        .upload_file_outlined,
                    label: '导入',
                    tooltip:
                        '导入 ApplyKit',
                    onPressed:
                        supportsWorkspaceImportPicker
                            ? () =>
                                _importWorkspace(
                                  context,
                                )
                            : null,
                  ),
                  _ToolbarTextButton(
                    icon: Icons
                        .download_outlined,
                    label: '导出',
                    tooltip:
                        '导出 Workspace 修改',
                    onPressed: canExport
                        ? () =>
                            _exportWorkspace(
                              context,
                            )
                        : null,
                  ),
                ],
              ),

              const SizedBox(width: 12),

              _ToolbarGroup(
                children: [
                  _ToolbarIconButton(
                    tooltip:
                        controller.autoRun
                            ? '关闭自动预览'
                            : '开启自动预览',
                    icon:
                        controller.autoRun
                            ? Icons
                                .flash_on_rounded
                            : Icons
                                .flash_off_rounded,
                    selected:
                        controller.autoRun,
                    onPressed:
                        controller
                            .toggleAutoRun,
                  ),
                  _ToolbarIconButton(
                    tooltip:
                        controller
                                .darkPreview
                            ? '切换浅色预览'
                            : '切换深色预览',
                    icon: controller
                            .darkPreview
                        ? Icons
                            .dark_mode_rounded
                        : Icons
                            .light_mode_rounded,
                    selected:
                        controller
                            .darkPreview,
                    onPressed:
                        controller
                            .togglePreviewTheme,
                  ),
                  _buildDeviceButton(
                    context,
                  ),
                ],
              ),

              const SizedBox(width: 8),

              _buildMoreButton(
                context,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackendButton(
    BuildContext context, {
    required VisualDensity density,
    required DartFrogWorkspaceService
        dartFrog,
    required ServerpodWorkspaceService
        serverpod,
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
      icon = Icons
          .account_tree_outlined;
    }

    return PopupMenuButton<
        _BackendChoice>(
      key: const ValueKey(
        'backend-workspace-menu',
      ),
      enabled: runner.canRun,
      tooltip: '选择后端环境',
      onSelected: (choice) {
        switch (choice) {
          case _BackendChoice.dartFrog:
            _enableDartFrog(
              context,
              dartFrog,
              serverpodEnabled:
                  serverpodEnabled,
            );
            break;

          case _BackendChoice.serverpod:
            _enableServerpod(
              context,
              serverpod,
              dartFrogEnabled:
                  dartFrogEnabled,
            );
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value:
              _BackendChoice.dartFrog,
          child: _BackendMenuItem(
            icon: Icons.api_rounded,
            title: 'Dart Frog',
            subtitle:
                '轻量 Dart API 后端',
            selected:
                dartFrogEnabled,
          ),
        ),
        PopupMenuItem(
          value:
              _BackendChoice.serverpod,
          child: _BackendMenuItem(
            icon: Icons.hub_outlined,
            title: 'Serverpod',
            subtitle:
                'Flutter 全栈后端',
            selected:
                serverpodEnabled,
          ),
        ),
      ],
      child: _PopupButtonSurface(
        enabled: runner.canRun,
        icon: icon,
        label: label,
      ),
    );
  }

  Widget _buildDeviceButton(
    BuildContext context,
  ) {
    return PopupMenuButton<
        PreviewDevice>(
      tooltip: '预览设备',
      initialValue:
          controller.device,
      onSelected:
          controller.changeDevice,
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
      child:
          _ToolbarIconSurface(
        icon:
            _deviceIcon(
          controller.device,
        ),
        tooltip: '设备',
      ),
    );
  }

  PopupMenuItem<PreviewDevice>
      _deviceItem(
    PreviewDevice value,
    IconData icon,
    String label,
  ) {
    final selected =
        controller.device == value;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 18,
            ),
        ],
      ),
    );
  }

  IconData _deviceIcon(
    PreviewDevice value,
  ) {
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

  Widget _buildMoreButton(
    BuildContext context,
  ) {
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
              builder: (_) =>
                  const SupportedWidgetsDialog(),
            );
            break;
        }
      },
      itemBuilder: (context) =>
          const [
        PopupMenuItem(
          value: _MoreAction.clear,
          child: ListTile(
            dense: true,
            contentPadding:
                EdgeInsets.zero,
            leading:
                Icon(Icons.clear),
            title: Text('清空代码'),
          ),
        ),
        PopupMenuItem(
          value:
              _MoreAction.resetExample,
          child: ListTile(
            dense: true,
            contentPadding:
                EdgeInsets.zero,
            leading:
                Icon(Icons.restore),
            title: Text('恢复示例'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _MoreAction
              .supportedWidgets,
          child: ListTile(
            dense: true,
            contentPadding:
                EdgeInsets.zero,
            leading: Icon(
              Icons.help_outline,
            ),
            title: Text(
              'Quick Preview 支持组件',
            ),
          ),
        ),
      ],
      child: const _ToolbarIconSurface(
        icon:
            Icons.more_horiz_rounded,
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
      service.ensureEnabled(
        controller.workspace,
      );

      controller.selectWorkspaceFile(
        DartFrogWorkspaceService
            .backendRoutePath,
      );
    } catch (error) {
      _showFrameworkError(
        context,
        error,
      );
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
      service.ensureEnabled(
        controller.workspace,
      );

      controller.selectWorkspaceFile(
        ServerpodWorkspaceService
            .greetingEndpointPath,
      );
    } catch (error) {
      _showFrameworkError(
        context,
        error,
      );
    }
  }

  void _showFrameworkConflict(
    BuildContext context, {
    required String current,
    required String requested,
  }) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '当前 Workspace 已启用 $current。'
          '请新建或重置练习后再启用 $requested。',
        ),
      ),
    );
  }

  void _showFrameworkError(
    BuildContext context,
    Object error,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '全栈环境创建失败：$error',
        ),
      ),
    );
  }

  Future<void> _importWorkspace(
    BuildContext context,
  ) async {
    if (controller.workspace.isDirty) {
      final confirmed =
          await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(
          title:
              const Text(
            '导入新的 ApplyKit？',
          ),
          content:
              const Text(
            '当前 Workspace 有未导出的修改。'
            '导入会恢复基线后应用 ApplyKit 中的修改。',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child:
                  const Text('继续导入'),
            ),
          ],
        ),
      );

      if (confirmed != true ||
          !context.mounted) {
        return;
      }
    }

    try {
      final bytes =
          await pickWorkspaceImport();

      if (bytes == null ||
          !context.mounted) {
        return;
      }

      final manifest =
          const WorkspaceImportService()
              .apply(
        bytes,
        controller.workspace,
      );

      controller.runCode();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
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

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content:
              Text('导入失败：$error'),
        ),
      );
    }
  }

  Future<void> _exportWorkspace(
    BuildContext context,
  ) async {
    try {
      final bundle =
          const WorkspaceExportService()
              .build(
        controller.workspace,
      );

      await downloadWorkspaceExport(
        bundle.bytes,
        bundle.fileName,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
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

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content:
              Text('导出失败：$error'),
        ),
      );
    }
  }
}

class _ToolbarGroup
    extends StatelessWidget {
  const _ToolbarGroup({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(
                alpha: 0.55,
              ),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _ToolbarIconButton
    extends StatelessWidget {
  const _ToolbarIconButton({
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
    if (selected &&
        onPressed != null) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        visualDensity:
            VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 20,
        ),
      );
    }

    return IconButton(
      tooltip: tooltip,
      visualDensity:
          VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 20,
      ),
    );
  }
}

class _ToolbarTextButton
    extends StatelessWidget {
  const _ToolbarTextButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity:
              VisualDensity.compact,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 19,
        ),
        label: Text(label),
      ),
    );
  }
}

class _ToolbarIconSurface
    extends StatelessWidget {
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
        width: 38,
        height: 36,
        child: Center(
          child: Icon(
            icon,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PopupButtonSurface
    extends StatelessWidget {
  const _PopupButtonSurface({
    required this.enabled,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context)
            .colorScheme;

    final foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface
            .withValues(
              alpha: 0.38,
            );

    return Container(
      height: 40,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? colorScheme.outline
              : colorScheme
                  .outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 19,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foreground,
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            Icons
                .keyboard_arrow_down_rounded,
            size: 18,
            color: foreground,
          ),
        ],
      ),
    );
  }
}

class _BackendMenuItem
    extends StatelessWidget {
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
      width: 250,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 19,
            ),
        ],
      ),
    );
  }
}