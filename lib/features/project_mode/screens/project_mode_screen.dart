import 'package:flutter/material.dart';

import '../../export/services/workspace_import_picker.dart';
import '../../playground/screens/playground_screen.dart';
import '../../project_creation/services/flutter_project_scaffold_service.dart';
import '../../project_creation/widgets/create_flutter_project_dialog.dart';
import '../../project_import/services/flutter_project_zip_import_service.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/services/hive_workspace_persistence.dart';
import '../../workspace/services/workspace_project_library.dart';

class ProjectModeScreen extends StatefulWidget {
  const ProjectModeScreen({
    super.key,
    this.projectLibrary,
  });

  /// Test/embedding seam. Normal app navigation resolves the browser project
  /// library from Hive so Project Mode opens as a project launcher instead of
  /// immediately exposing the legacy default Workspace template.
  final WorkspaceProjectLibrary? projectLibrary;

  @override
  State<ProjectModeScreen> createState() => _ProjectModeScreenState();
}

class _ProjectModeScreenState extends State<ProjectModeScreen> {
  static const _runnerApiUrl = String.fromEnvironment('RUNNER_API_URL');

  WorkspaceProjectLibrary? _library;

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

  Future<void> _importProject() async {
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

    return Scaffold(
      key: const ValueKey('project-mode-screen'),
      appBar: AppBar(
        title: const Text('项目模式'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: library == null
                  ? const _UnavailableProjectLibrary()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProjectModeHeader(
                          onCreate: _createProject,
                          onImport: supportsWorkspaceImportPicker
                              ? _importProject
                              : null,
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text(
                              '你的项目',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
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
                                  onImport: supportsWorkspaceImportPicker
                                      ? _importProject
                                      : null,
                                )
                              : ListView.separated(
                                  key: const ValueKey('project-mode-project-list'),
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
                                      onTap: () => _openProject(project),
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
    required this.onCreate,
    required this.onImport,
  });

  final VoidCallback onCreate;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择一个项目开始开发',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '项目模式不会再自动打开默认模板。创建新 Flutter 项目，或从下面的项目列表继续。',
              ),
            ],
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('project-mode-create'),
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('创建 Flutter 项目'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('project-mode-import'),
          onPressed: onImport,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('导入 Flutter ZIP'),
        ),
      ],
    );
  }
}

class _EmptyProjectList extends StatelessWidget {
  const _EmptyProjectList({
    required this.onCreate,
    required this.onImport,
  });

  final VoidCallback onCreate;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        key: const ValueKey('project-mode-empty'),
        width: 560,
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
              '创建一个新的 Flutter 项目，或导入你已有的 Flutter 项目。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('project-mode-empty-create'),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('创建项目'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('project-mode-empty-import'),
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('导入项目'),
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
    required this.onTap,
  });

  final WorkspaceProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _subtitle(project);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
      return '导入的 Flutter 项目';
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
