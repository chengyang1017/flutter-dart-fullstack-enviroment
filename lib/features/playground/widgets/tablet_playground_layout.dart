import 'dart:async';

import 'package:flutter/material.dart';

import '../../assets/widgets/asset_manager_dialog.dart';
import '../../concept/widgets/concept_lib_explorer.dart';
import '../../export/services/workspace_export_download.dart';
import '../../export/services/workspace_export_service.dart';
import '../../export/services/workspace_import_picker.dart';
import '../../export/services/workspace_import_service.dart';
import '../../packages/widgets/package_manager_dialog.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/dart_frog_api_lab_dialog.dart';
import '../../runner/widgets/runner_console_panel.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/services/dart_frog_workspace_service.dart';
import '../../workspace/services/serverpod_workspace_service.dart';
import '../../workspace/widgets/workspace_file_explorer.dart';
import '../controllers/playground_controller.dart';
import '../models/workspace_view_mode.dart';
import 'code_flow_panel.dart';
import 'error_panel.dart';
import 'monaco_code_editor_panel.dart';
import 'source_control_panel.dart';
import 'supported_widgets_dialog.dart';

enum _TabletDestination {
  code,
  files,
  preview,
  wire,
  terminal,
}

/// Android-tablet shell for the playground.
///
/// This intentionally does not shrink the desktop workbench. It follows an
/// Android large-screen structure instead:
/// - Material 3 top app bar
/// - NavigationRail for 3-7 top-level destinations
/// - touch-sized controls
/// - a supporting preview pane beside the editor on expanded landscape windows
/// - modal bottom sheets for project and workspace actions
class TabletPlaygroundLayout extends StatefulWidget {
  const TabletPlaygroundLayout({
    super.key,
    required this.controller,
    required this.runner,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onRun,
    this.projects,
    this.activeProject,
    this.onSelectProject,
    this.onCreateProject,
    this.onOpenFolder,
    this.onImportZip,
    this.onCommit,
    this.onShare,
    this.onKeep,
    this.onRename,
    this.onDeleteProject,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final WorkspaceViewMode viewMode;
  final ValueChanged<WorkspaceViewMode> onViewModeChanged;
  final VoidCallback onRun;

  final List<WorkspaceProject>? projects;
  final WorkspaceProject? activeProject;
  final ValueChanged<String>? onSelectProject;
  final VoidCallback? onCreateProject;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onImportZip;
  final VoidCallback? onCommit;
  final VoidCallback? onShare;
  final VoidCallback? onKeep;
  final VoidCallback? onRename;
  final ValueChanged<String>? onDeleteProject;

  @override
  State<TabletPlaygroundLayout> createState() => _TabletPlaygroundLayoutState();
}

class _TabletPlaygroundLayoutState extends State<TabletPlaygroundLayout> {
  _TabletDestination _destination = _TabletDestination.code;

  @override
  void didUpdateWidget(covariant TabletPlaygroundLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _destination = _TabletDestination.code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff6f9cff),
      brightness: Brightness.dark,
    );
    final tabletTheme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.standard,
    );

    return Theme(
      data: tabletTheme,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extendedRail = constraints.maxWidth >= 1200;
          final showSupportingPreview = constraints.maxWidth >= 1050 &&
              constraints.maxWidth > constraints.maxHeight &&
              _destination == _TabletDestination.code;

          return ColoredBox(
            color: scheme.surface,
            child: Row(
              children: [
                _buildNavigationRail(
                  context,
                  extended: extendedRail,
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopAppBar(
                        context,
                        compact: constraints.maxWidth < 900,
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildDestination(
                            context,
                            showSupportingPreview: showSupportingPreview,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavigationRail(
    BuildContext context, {
    required bool extended,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return NavigationRail(
      selectedIndex: _destination.index,
      onDestinationSelected: (index) {
        setState(() {
          _destination = _TabletDestination.values[index];
        });
      },
      extended: extended,
      minWidth: 82,
      minExtendedWidth: 188,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      useIndicator: true,
      groupAlignment: -1,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Tooltip(
          message: '运行 Flutter 项目',
          child: FloatingActionButton.small(
            heroTag: 'tablet-run-fab',
            onPressed: widget.runner.canRun ? widget.onRun : null,
            child: const Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.code_outlined),
          selectedIcon: Icon(Icons.code_rounded),
          label: Text('代码'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: Text('文件'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.phone_android_outlined),
          selectedIcon: Icon(Icons.phone_android_rounded),
          label: Text('预览'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_tree_outlined),
          selectedIcon: Icon(Icons.account_tree_rounded),
          label: Text('电线'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.terminal_outlined),
          selectedIcon: Icon(Icons.terminal_rounded),
          label: Text('终端'),
        ),
      ],
    );
  }

  Widget _buildTopAppBar(
    BuildContext context, {
    required bool compact,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final project = widget.activeProject;

    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: project == null
                        ? null
                        : () => _showProjectSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            project == null
                                ? Icons.flutter_dash_rounded
                                : _projectIcon(project),
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project?.name ?? 'Flutter Workspace',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _topBarSubtitle(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (project != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ViewModeMenu(
                value: widget.viewMode,
                onChanged: widget.onViewModeChanged,
              ),
              const SizedBox(width: 6),
              if (!compact) ...[
                IconButton(
                  tooltip: 'Hot Reload',
                  onPressed: widget.runner.canHotReload
                      ? widget.runner.hotReload
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Hot Restart',
                  onPressed: widget.runner.canHotRestart
                      ? widget.runner.hotRestart
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
                IconButton(
                  tooltip: '停止',
                  onPressed: widget.runner.canStop ? widget.runner.stop : null,
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
              const SizedBox(width: 2),
              IconButton(
                tooltip: '工作区工具',
                onPressed: () => _showWorkspaceToolsSheet(context),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _topBarSubtitle() {
    final destination = switch (_destination) {
      _TabletDestination.code => '代码 · ${widget.controller.activeFilePath}',
      _TabletDestination.files => '项目文件 · ${widget.viewMode.label}',
      _TabletDestination.preview => '设备预览',
      _TabletDestination.wire => '函数调用关系',
      _TabletDestination.terminal => 'Flutter Runner 终端',
    };
    return destination;
  }

  Widget _buildDestination(
    BuildContext context, {
    required bool showSupportingPreview,
  }) {
    return switch (_destination) {
      _TabletDestination.code => _buildCodeWorkspace(
          context,
          showSupportingPreview: showSupportingPreview,
        ),
      _TabletDestination.files => _TabletPane(
          child: _TabletWorkspaceFiles(
            controller: widget.controller,
            runner: widget.runner,
            viewMode: widget.viewMode,
            onViewModeChanged: widget.onViewModeChanged,
          ),
        ),
      _TabletDestination.preview => _TabletPane(
          child: RunnerPreviewPanel(
            playground: widget.controller,
            runner: widget.runner,
          ),
        ),
      _TabletDestination.wire => _TabletPane(
          child: CodeFlowPanel(
            controller: widget.controller,
            onNavigate: () {
              setState(() {
                _destination = _TabletDestination.code;
              });
            },
          ),
        ),
      _TabletDestination.terminal => _TabletPane(
          child: RunnerConsolePanel(runner: widget.runner),
        ),
    };
  }

  Widget _buildCodeWorkspace(
    BuildContext context, {
    required bool showSupportingPreview,
  }) {
    final editor = _TabletPane(
      child: Column(
        children: [
          _TabletEditorTabs(
            controller: widget.controller,
            viewMode: widget.viewMode,
          ),
          Expanded(
            child: MonacoCodeEditorPanel(
              controller: widget.controller,
            ),
          ),
          ErrorPanel(
            controller: widget.controller,
            maxHeight: 150,
          ),
        ],
      ),
    );

    if (!showSupportingPreview) {
      return editor;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: editor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TabletPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PaneHeader(
                  icon: Icons.phone_android_rounded,
                  title: '运行预览',
                  trailing: IconButton(
                    tooltip: '打开完整预览',
                    onPressed: () {
                      setState(() {
                        _destination = _TabletDestination.preview;
                      });
                    },
                    icon: const Icon(Icons.open_in_full_rounded),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RunnerPreviewPanel(
                    playground: widget.controller,
                    runner: widget.runner,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showProjectSheet(BuildContext context) async {
    final project = widget.activeProject;
    final projects = widget.projects;
    if (project == null || projects == null) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final canDelete = projects.length > 1 && widget.onDeleteProject != null;

        void closeThen(VoidCallback? callback) {
          Navigator.of(sheetContext).pop();
          callback?.call();
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '项目',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '选择 Workspace 或管理当前项目',
                    style:
                        Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                  ),
                  const SizedBox(height: 18),
                  for (final item in projects)
                    ListTile(
                      minTileHeight: 56,
                      selected: item.id == project.id,
                      selectedTileColor: scheme.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(_projectIcon(item)),
                      title: Text(item.name),
                      subtitle: Text(_projectSubtitle(item)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.id == project.id)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.check_rounded),
                            ),
                          IconButton(
                            tooltip: '删除 ${item.name}',
                            onPressed: canDelete
                                ? () {
                                    Navigator.of(sheetContext).pop();
                                    widget.onDeleteProject?.call(item.id);
                                  }
                                : null,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: canDelete ? scheme.error : null,
                            ),
                          ),
                        ],
                      ),
                      onTap: item.id == project.id
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              widget.onSelectProject?.call(item.id);
                            },
                    ),
                  const SizedBox(height: 18),
                  Text(
                    '项目操作',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SheetActionButton(
                        icon: Icons.add_rounded,
                        label: '新建',
                        onPressed: widget.onCreateProject == null
                            ? null
                            : () => closeThen(widget.onCreateProject),
                      ),
                      _SheetActionButton(
                        icon: Icons.folder_open_rounded,
                        label: '打开文件夹',
                        onPressed: widget.onOpenFolder == null
                            ? null
                            : () => closeThen(widget.onOpenFolder),
                      ),
                      _SheetActionButton(
                        icon: Icons.archive_outlined,
                        label: '导入 ZIP',
                        onPressed: widget.onImportZip == null
                            ? null
                            : () => closeThen(widget.onImportZip),
                      ),
                      _SheetActionButton(
                        icon: Icons.commit_rounded,
                        label: 'Commit',
                        onPressed: widget.onCommit == null
                            ? null
                            : () => closeThen(widget.onCommit),
                      ),
                      _SheetActionButton(
                        icon: Icons.ios_share_rounded,
                        label: '分享',
                        onPressed: widget.onShare == null
                            ? null
                            : () => closeThen(widget.onShare),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.bookmark_add_outlined),
                    title: const Text('保留项目'),
                    subtitle: const Text('把临时 Workspace 标记为长期保留'),
                    enabled: widget.onKeep != null,
                    onTap: widget.onKeep == null
                        ? null
                        : () => closeThen(widget.onKeep),
                  ),
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('重命名'),
                    enabled: widget.onRename != null,
                    onTap: widget.onRename == null
                        ? null
                        : () => closeThen(widget.onRename),
                  ),
                  ListTile(
                    minTileHeight: 56,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: canDelete ? scheme.error : null,
                    ),
                    title: Text(
                      '删除当前项目',
                      style: TextStyle(
                        color: canDelete ? scheme.error : null,
                      ),
                    ),
                    subtitle: projects.length <= 1
                        ? const Text('至少需要保留一个 Workspace')
                        : const Text('删除项目数据与 Workspace 快照'),
                    enabled: canDelete,
                    onTap: canDelete
                        ? () => closeThen(
                              () => widget.onDeleteProject?.call(project.id),
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showWorkspaceToolsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 720),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                widget.controller,
                widget.runner,
              ]),
              builder: (context, _) {
                const dartFrog = DartFrogWorkspaceService();
                const serverpod = ServerpodWorkspaceService();
                final dartFrogEnabled =
                    dartFrog.isEnabled(widget.controller.workspace);
                final serverpodEnabled =
                    serverpod.isEnabled(widget.controller.workspace);
                final canExport = widget.controller.workspace.isDirty &&
                    supportsWorkspaceExportDownload;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    Text(
                      '工作区工具',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _ToolSectionLabel(label: '运行与预览'),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.refresh_rounded),
                      title: const Text('Hot Reload'),
                      enabled: widget.runner.canHotReload,
                      onTap: widget.runner.canHotReload
                          ? widget.runner.hotReload
                          : null,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.restart_alt_rounded),
                      title: const Text('Hot Restart'),
                      enabled: widget.runner.canHotRestart,
                      onTap: widget.runner.canHotRestart
                          ? widget.runner.hotRestart
                          : null,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.stop_rounded),
                      title: const Text('停止 Runner'),
                      enabled: widget.runner.canStop,
                      onTap: widget.runner.canStop ? widget.runner.stop : null,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.bolt_rounded),
                      title: const Text('快速预览'),
                      subtitle: const Text('运行轻量预览并切换到预览页'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        widget.controller.runCode();
                        setState(() {
                          _destination = _TabletDestination.preview;
                        });
                      },
                    ),
                    SwitchListTile(
                      minTileHeight: 56,
                      secondary: const Icon(Icons.flash_auto_rounded),
                      title: const Text('自动预览'),
                      value: widget.controller.autoRun,
                      onChanged: (_) => widget.controller.toggleAutoRun(),
                    ),
                    SwitchListTile(
                      minTileHeight: 56,
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: const Text('深色预览'),
                      value: widget.controller.darkPreview,
                      onChanged: (_) => widget.controller.togglePreviewTheme(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '预览设备',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<PreviewDevice>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PreviewDevice.androidPhone,
                          icon: Icon(Icons.phone_android_rounded),
                          label: Text('手机'),
                        ),
                        ButtonSegment(
                          value: PreviewDevice.smallPhone,
                          icon: Icon(Icons.smartphone_rounded),
                          label: Text('小屏'),
                        ),
                        ButtonSegment(
                          value: PreviewDevice.tablet,
                          icon: Icon(Icons.tablet_android_rounded),
                          label: Text('平板'),
                        ),
                        ButtonSegment(
                          value: PreviewDevice.responsive,
                          icon: Icon(Icons.devices_rounded),
                          label: Text('响应式'),
                        ),
                      ],
                      selected: {widget.controller.device},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        widget.controller.changeDevice(selection.first);
                      },
                    ),
                    const SizedBox(height: 22),
                    _ToolSectionLabel(label: '后端'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.api_rounded, size: 18),
                          label: const Text('Dart Frog'),
                          selected: dartFrogEnabled,
                          onSelected: widget.runner.canRun
                              ? (_) => _enableDartFrog(
                                    sheetContext,
                                    dartFrog,
                                    serverpodEnabled: serverpodEnabled,
                                  )
                              : null,
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.hub_outlined, size: 18),
                          label: const Text('Serverpod'),
                          selected: serverpodEnabled,
                          onSelected: widget.runner.canRun
                              ? (_) => _enableServerpod(
                                    sheetContext,
                                    serverpod,
                                    dartFrogEnabled: dartFrogEnabled,
                                  )
                              : null,
                        ),
                      ],
                    ),
                    if (dartFrogEnabled) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        minTileHeight: 56,
                        leading: const Icon(Icons.http_rounded),
                        title: const Text('Dart Frog API Lab'),
                        subtitle: Text(
                          widget.runner.session?.backendUrl == null
                              ? 'Runner 尚未提供后端 URL'
                              : widget.runner.session!.backendUrl!,
                        ),
                        enabled: widget.runner.canHotReload &&
                            widget.runner.session?.backendUrl != null,
                        onTap: widget.runner.canHotReload &&
                                widget.runner.session?.backendUrl != null
                            ? () {
                                final url = widget.runner.session!.backendUrl!;
                                showDialog<void>(
                                  context: sheetContext,
                                  builder: (_) => DartFrogApiLabDialog(
                                    baseUrl: url,
                                  ),
                                );
                              }
                            : null,
                      ),
                    ],
                    const SizedBox(height: 22),
                    _ToolSectionLabel(label: 'Workspace'),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('导入 ApplyKit'),
                      enabled: supportsWorkspaceImportPicker,
                      onTap: supportsWorkspaceImportPicker
                          ? () => unawaited(_importWorkspace(sheetContext))
                          : null,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('导出 ApplyKit'),
                      enabled: canExport,
                      onTap: canExport
                          ? () => unawaited(_exportWorkspace(sheetContext))
                          : null,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.perm_media_outlined),
                      title: const Text('Assets'),
                      onTap: () {
                        showAssetManagerDialog(
                          sheetContext,
                          workspace: widget.controller.workspace,
                        );
                      },
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('依赖管理'),
                      onTap: () {
                        showPackageManagerDialog(
                          sheetContext,
                          runner: widget.runner,
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.clear_rounded),
                      title: const Text('清空代码'),
                      onTap: widget.controller.clearCode,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.restore_rounded),
                      title: const Text('恢复示例'),
                      onTap: widget.controller.resetExample,
                    ),
                    ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.help_outline_rounded),
                      title: const Text('Quick Preview 支持组件'),
                      onTap: () {
                        showDialog<void>(
                          context: sheetContext,
                          builder: (_) => const SupportedWidgetsDialog(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
      service.ensureEnabled(widget.controller.workspace);
      widget.controller.selectWorkspaceFile(
        DartFrogWorkspaceService.backendRoutePath,
      );
      setState(() {
        _destination = _TabletDestination.code;
      });
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
      service.ensureEnabled(widget.controller.workspace);
      widget.controller.selectWorkspaceFile(
        ServerpodWorkspaceService.greetingEndpointPath,
      );
      setState(() {
        _destination = _TabletDestination.code;
      });
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
          '当前 Workspace 已启用 $current。请新建或重置练习后再启用 $requested。',
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
    if (widget.controller.workspace.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入新的 ApplyKit？'),
          content: const Text(
            '当前 Workspace 有未导出的修改。导入会恢复基线后应用 ApplyKit 中的修改。',
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

      if (confirmed != true || !context.mounted) return;
    }

    try {
      final bytes = await pickWorkspaceImport();
      if (bytes == null || !context.mounted) return;

      final manifest = const WorkspaceImportService().apply(
        bytes,
        widget.controller.workspace,
      );
      widget.controller.runCode();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${manifest.changes.length} 个 Workspace 修改。',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
    }
  }

  Future<void> _exportWorkspace(BuildContext context) async {
    try {
      final bundle = const WorkspaceExportService().build(
        widget.controller.workspace,
      );

      await downloadWorkspaceExport(
        bundle.bytes,
        bundle.fileName,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${bundle.manifest.changes.length} 个修改：${bundle.fileName}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$error')),
      );
    }
  }

  IconData _projectIcon(WorkspaceProject project) {
    return switch (project.kind) {
      WorkspaceProjectKind.generatedFlutter => Icons.flutter_dash_rounded,
      WorkspaceProjectKind.importedFlutter => Icons.folder_zip_outlined,
      WorkspaceProjectKind.practice => Icons.folder_copy_outlined,
    };
  }

  String _projectSubtitle(WorkspaceProject project) {
    if (project.kind == WorkspaceProjectKind.generatedFlutter) {
      final platforms = project.flutterPlatforms.join(' · ');
      return platforms.isEmpty ? 'Flutter 项目' : 'Flutter · $platforms';
    }
    if (project.kind == WorkspaceProjectKind.importedFlutter) {
      return '导入的 Flutter 项目';
    }
    return project.lifecycle == WorkspaceLifecycle.temporary
        ? '临时 Workspace'
        : 'Workspace';
  }
}

class _TabletWorkspaceFiles extends StatelessWidget {
  const _TabletWorkspaceFiles({
    required this.controller,
    required this.runner,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final WorkspaceViewMode viewMode;
  final ValueChanged<WorkspaceViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<WorkspaceViewMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: WorkspaceViewMode.project,
                    icon: Icon(Icons.account_tree_outlined),
                    label: Text('项目'),
                  ),
                  ButtonSegment(
                    value: WorkspaceViewMode.concept,
                    icon: Icon(Icons.hub_outlined),
                    label: Text('概念'),
                  ),
                  ButtonSegment(
                    value: WorkspaceViewMode.sourceControl,
                    icon: Icon(Icons.commit_rounded),
                    label: Text('Git'),
                  ),
                ],
                selected: {viewMode},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  onViewModeChanged(selection.first);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      viewMode.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  if (viewMode.isSourceControl) ...[
                    TextButton.icon(
                      onPressed: controller.workspace.stageAll,
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Stage All'),
                    ),
                    TextButton.icon(
                      onPressed: controller.workspace.unstageAll,
                      icon: const Icon(Icons.remove_done_rounded),
                      label: const Text('Unstage'),
                    ),
                  ] else ...[
                    TextButton.icon(
                      onPressed: () {
                        showAssetManagerDialog(
                          context,
                          workspace: controller.workspace,
                        );
                      },
                      icon: const Icon(Icons.perm_media_outlined),
                      label: const Text('Assets'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        showPackageManagerDialog(
                          context,
                          runner: runner,
                        );
                      },
                      icon: const Icon(Icons.extension_outlined),
                      label: const Text('依赖'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: scheme.outlineVariant,
        ),
        Expanded(
          child: viewMode.isSourceControl
              ? SourceControlPanel(
                  workspace: controller.workspace,
                  onShowDiff: controller.selectWorkspaceFile,
                )
              : viewMode.isConcept
                  ? ConceptLibExplorer(
                      workspace: controller.workspace,
                      onOpenFile: controller.selectWorkspaceFile,
                    )
                  : WorkspaceFileExplorer(
                      workspace: controller.workspace,
                      onOpenFile: controller.selectWorkspaceFile,
                    ),
        ),
      ],
    );
  }
}

class _TabletEditorTabs extends StatelessWidget {
  const _TabletEditorTabs({
    required this.controller,
    required this.viewMode,
  });

  final PlaygroundController controller;
  final WorkspaceViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: controller.workspace,
      builder: (context, _) {
        final openFiles = controller.workspace.openFiles
            .where(
              (path) =>
                  controller.workspace.entryAt(path) != null &&
                  (!viewMode.isConcept || viewMode.allowsPath(path)),
            )
            .toList(growable: false);

        return Material(
          color: scheme.surfaceContainer,
          child: SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              itemCount: openFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final path = openFiles[index];
                final entry = controller.workspace.entryAt(path)!;
                final selected = path == controller.workspace.activePath;
                final dirty = controller.workspace.isFileDirty(path);

                return Material(
                  color: selected
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => controller.selectWorkspaceFile(path),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 112,
                        maxWidth: 240,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _fileIcon(entry.name),
                              size: 18,
                              color: selected
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (dirty) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.circle,
                                size: 7,
                                color: scheme.primary,
                              ),
                            ],
                            IconButton(
                              tooltip: '关闭 ${entry.name}',
                              iconSize: 18,
                              onPressed: () =>
                                  controller.closeWorkspaceFile(path),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.code_rounded;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) {
      return Icons.tune_rounded;
    }
    if (name.endsWith('.json')) return Icons.data_object_rounded;
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.description_outlined;
  }
}

class _ViewModeMenu extends StatelessWidget {
  const _ViewModeMenu({
    required this.value,
    required this.onChanged,
  });

  final WorkspaceViewMode value;
  final ValueChanged<WorkspaceViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<WorkspaceViewMode>(
      initialValue: value,
      tooltip: 'Workspace 视角',
      onSelected: onChanged,
      itemBuilder: (context) => WorkspaceViewMode.values
          .map(
            (mode) => PopupMenuItem(
              value: mode,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _iconFor(mode),
                  color: mode == value ? scheme.primary : null,
                ),
                title: Text(mode.label),
                subtitle: Text(mode.description),
                trailing:
                    mode == value ? const Icon(Icons.check_rounded) : null,
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(value),
              size: 19,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              value.label,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: scheme.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(WorkspaceViewMode mode) {
    return switch (mode) {
      WorkspaceViewMode.project => Icons.account_tree_outlined,
      WorkspaceViewMode.concept => Icons.hub_outlined,
      WorkspaceViewMode.sourceControl => Icons.commit_rounded,
    };
  }
}

class _TabletPane extends StatelessWidget {
  const _TabletPane({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: child,
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ToolSectionLabel extends StatelessWidget {
  const _ToolSectionLabel({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}
