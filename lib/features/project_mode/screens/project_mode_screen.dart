import 'package:flutter/material.dart';

import '../../export/services/workspace_import_picker.dart';
import '../../playground/screens/playground_screen.dart';
import '../../project_creation/services/flutter_project_scaffold_service.dart';
import '../../project_creation/widgets/create_flutter_project_dialog.dart';
import '../../project_import/services/flutter_project_directory_import_service.dart';
import '../../project_import/services/flutter_project_zip_import_service.dart';
import '../../workspace/models/workspace_identity.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/services/hive_workspace_persistence.dart';
import '../../workspace/services/workspace_cloud_runtime.dart';
import '../../workspace/services/workspace_project_library.dart';

enum _ProjectCardAction {
  rename,
  delete,
}

class ProjectModeScreen extends StatefulWidget {
  const ProjectModeScreen({
    super.key,
    this.projectLibrary,
    this.identity,
  });

  final WorkspaceProjectLibrary? projectLibrary;
  final WorkspaceIdentity? identity;

  @override
  State<ProjectModeScreen> createState() => _ProjectModeScreenState();
}

class _ProjectModeScreenState extends State<ProjectModeScreen> {
  static const _runnerApiUrl = String.fromEnvironment('RUNNER_API_URL');

  WorkspaceProjectLibrary? _library;

  WorkspaceIdentity? get _identity =>
      widget.identity ?? WorkspaceCloudRuntime.identity;

  @override
  void initState() {
    super.initState();
    _reloadLibrary();
  }

  void _reloadLibrary() {
    if (widget.projectLibrary != null) {
      _library = widget.projectLibrary;
      return;
    }

    final persistence = HiveWorkspacePersistence.tryFromOpenBoxes();
    _library = persistence == null
        ? null
        : WorkspaceProjectLibrary.fromPersistence(persistence);
  }

  List<WorkspaceProject> get _visibleProjects {
    final library = _library;
    if (library == null) return const <WorkspaceProject>[];

    return library.projects
        .where(
          (project) => project.id != WorkspaceProjectLibrary.defaultProjectId,
        )
        .toList(growable: false);
  }

  Future<void> _openProject(WorkspaceProject project) async {
    final library = _library;
    if (library == null) return;

    await library.selectProject(project.id);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlaygroundScreen(),
      ),
    );

    if (!mounted) return;
    _reloadLibrary();
    setState(() {});
  }

  Future<void> _createProject() async {
    final library = _library;
    if (library == null) return;

    if (_runnerApiUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('创建真实 Flutter 项目需要连接 Flutter Runner。'),
        ),
      );
      return;
    }

    final request = await showCreateFlutterProjectDialog(context);
    if (request == null || !mounted) return;

    final scaffoldService = FlutterProjectScaffoldService(
      baseUrl: _runnerApiUrl,
    );

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在创建 Flutter 项目 ${request.projectName}...')),
      );

      final snapshot = await scaffoldService.create(
        projectName: request.projectName,
        platforms: request.platforms,
      );
      if (!mounted) return;

      final project = await library.createGeneratedFlutter(
        name: request.projectName,
        snapshot: snapshot,
        platforms: request.platforms,
      );
      if (!mounted) return;

      await _openProject(project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建 Flutter 项目失败：$error')),
      );
    } finally {
      scaffoldService.close();
    }
  }

  Future<void> _openLocalFolder() async {
    final library = _library;
    if (library == null || !supportsWorkspaceDirectoryPicker) return;

    BuildContext? progressDialogContext;

    void closeProgressDialog() {
      final dialogContext = progressDialogContext;
      if (dialogContext == null || !dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      progressDialogContext = null;
    }

    try {
      final files = await pickWorkspaceDirectory();
      if (files == null || files.isEmpty || !mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressDialogContext = dialogContext;
          return const PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text('正在打开本地文件夹'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('正在读取项目文件并保存到 Workspace，请稍候…'),
                    SizedBox(height: 18),
                    LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // 先让弹窗真正绘制出来，再开始解析项目。
      await WidgetsBinding.instance.endOfFrame;

      final bundle = const FlutterProjectDirectoryImportService().parse(files);
      final project = await library.createImportedFlutter(
        name: bundle.projectName,
        snapshot: bundle.snapshot,
      );
      if (!mounted) return;

      closeProgressDialog();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            WorkspaceCloudRuntime.enabled
                ? '已打开 ${bundle.projectName}，${bundle.importedFileCount} 个文件已进入云端 Workspace。'
                : '已打开 ${bundle.projectName}，${bundle.importedFileCount} 个文件已保存到本地 Workspace。',
          ),
        ),
      );

      await _openProject(project);
    } catch (error) {
      closeProgressDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开本地 Flutter 文件夹失败：$error')),
      );
    } finally {
      closeProgressDialog();
    }
  }

  Future<void> _renameProject(WorkspaceProject project) async {
    final library = _library;
    if (library == null) return;

    final textController = TextEditingController(text: project.name);
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: project.name.length,
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名项目'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    textController.dispose();

    if (name == null || name.trim().isEmpty || !mounted) return;

    try {
      await library.renameProject(project.id, name.trim());
      if (!mounted) return;
      _reloadLibrary();
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名项目失败：$error')),
      );
    }
  }

  Future<void> _deleteProject(WorkspaceProject project) async {
    final library = _library;
    if (library == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除 ${project.name}？'),
        content: const Text('这个项目会从 Workspace 中删除。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await library.deleteProject(project.id);
      if (!mounted) return;

      _reloadLibrary();
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${project.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除项目失败：$error')),
      );
    }
  }

  Future<void> _importProjectZip() async {
    final library = _library;
    if (library == null || !supportsWorkspaceImportPicker) return;

    try {
      final bytes = await pickWorkspaceImport();
      if (bytes == null || !mounted) return;

      final bundle = const FlutterProjectZipImportService().parse(bytes);
      final project = await library.createImportedFlutter(
        name: bundle.projectName,
        snapshot: bundle.snapshot,
      );
      if (!mounted) return;

      await _openProject(project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Flutter ZIP 导入失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final projects = _visibleProjects;
    final accountUsername = _identity?.username;

    return Scaffold(
      key: const ValueKey('project-mode-screen'),
      appBar: AppBar(
        title: const Text('开始项目'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: library == null
                  ? const _UnavailableProjectLibrary()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProjectModeHeader(
                          accountUsername: accountUsername,
                          onCreate: _createProject,
                          onOpenFolder: supportsWorkspaceDirectoryPicker
                              ? _openLocalFolder
                              : null,
                          onImportZip: supportsWorkspaceImportPicker
                              ? _importProjectZip
                              : null,
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text(
                              '你的项目',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Text(
                              '${projects.length} 个项目',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: projects.isEmpty
                              ? _EmptyProjectList(
                                  onCreate: _createProject,
                                  onOpenFolder: supportsWorkspaceDirectoryPicker
                                      ? _openLocalFolder
                                      : null,
                                  onImportZip: supportsWorkspaceImportPicker
                                      ? _importProjectZip
                                      : null,
                                )
                              : ListView.separated(
                                  key: const ValueKey(
                                    'project-mode-project-list',
                                  ),
                                  itemCount: projects.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final project = projects[index];
                                    return _ProjectCard(
                                      key: ValueKey(
                                        'project-mode-project-${project.id}',
                                      ),
                                      project: project,
                                      accountUsername: accountUsername,
                                      onTap: () => _openProject(project),
                                      onRename: () => _renameProject(project),
                                      onDelete: () => _deleteProject(project),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectModeHeader extends StatelessWidget {
  const _ProjectModeHeader({
    required this.accountUsername,
    required this.onCreate,
    required this.onOpenFolder,
    required this.onImportZip,
  });

  final String? accountUsername;
  final VoidCallback onCreate;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onImportZip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 390,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择一个项目开始',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '创建、打开或导入 Flutter 项目。进入 Workspace 后可随时在项目视角和概念视角之间切换。',
              ),
              if (accountUsername != null) ...[
                const SizedBox(height: 10),
                Chip(
                  key: const ValueKey('project-mode-account-namespace'),
                  avatar: const Icon(Icons.account_circle_outlined, size: 18),
                  label: Text(accountUsername!),
                ),
              ],
            ],
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('project-mode-open-folder'),
          onPressed: onOpenFolder,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('打开本地文件夹'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('project-mode-create'),
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('创建 Flutter 项目'),
        ),
        TextButton.icon(
          key: const ValueKey('project-mode-import'),
          onPressed: onImportZip,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('导入 ZIP'),
        ),
      ],
    );
  }
}

class _EmptyProjectList extends StatelessWidget {
  const _EmptyProjectList({
    required this.onCreate,
    required this.onOpenFolder,
    required this.onImportZip,
  });

  final VoidCallback onCreate;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onImportZip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        key: const ValueKey('project-mode-empty'),
        width: 600,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 52,
              color: scheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有项目',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              '直接打开电脑里的 Flutter 根目录，或者创建/导入一个项目。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('project-mode-empty-open-folder'),
                  onPressed: onOpenFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('打开本地文件夹'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('project-mode-empty-create'),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('创建项目'),
                ),
                TextButton.icon(
                  key: const ValueKey('project-mode-empty-import'),
                  onPressed: onImportZip,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('导入 ZIP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    super.key,
    required this.project,
    required this.accountUsername,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final WorkspaceProject project;
  final String? accountUsername;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _subtitle(project);
    final namespace = accountUsername == null
        ? project.slug
        : '$accountUsername / ${project.slug}';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.flutter_dash_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            namespace,
                            key: ValueKey(
                              'project-mode-project-namespace-${project.id}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<_ProjectCardAction>(
            key: ValueKey('project-mode-project-menu-${project.id}'),
            tooltip: '项目操作',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              switch (action) {
                case _ProjectCardAction.rename:
                  onRename();
                  break;
                case _ProjectCardAction.delete:
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ProjectCardAction.rename,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('重命名'),
                ),
              ),
              PopupMenuItem(
                value: _ProjectCardAction.delete,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: scheme.error,
                  ),
                  title: Text(
                    '删除项目',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _subtitle(WorkspaceProject project) {
    final remote = project.gitRemote;
    if (remote != null) {
      final path = remote.projectPath;
      return path == null
          ? 'Git · ${remote.repositoryUrl}'
          : 'Git · ${remote.repositoryUrl} · $path';
    }

    if (project.kind == WorkspaceProjectKind.generatedFlutter) {
      final platforms = project.flutterPlatforms.map(_platformLabel).join(' · ');
      return platforms.isEmpty ? 'Flutter 项目' : 'Flutter · $platforms';
    }
    if (project.kind == WorkspaceProjectKind.importedFlutter) {
      return '本地打开 / 导入的 Flutter 项目';
    }
    return 'Workspace 项目';
  }

  String _platformLabel(String platform) => switch (platform) {
        'android' => 'Android',
        'ios' => 'iOS',
        'web' => 'Web',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'linux' => 'Linux',
        _ => platform,
      };
}

class _UnavailableProjectLibrary extends StatelessWidget {
  const _UnavailableProjectLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('当前环境没有可用的项目库。'),
    );
  }
}
