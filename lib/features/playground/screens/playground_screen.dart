import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../export/services/workspace_import_picker.dart';
import '../../project_creation/services/flutter_project_scaffold_service.dart';
import '../../project_creation/widgets/create_flutter_project_dialog.dart';
import '../../project_import/services/flutter_project_directory_import_service.dart';
import '../../project_import/services/flutter_project_zip_import_service.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/models/run_session.dart';
import '../../runner/models/runner_preview_target.dart';
import '../../runner/services/http_flutter_runner_client.dart';
import '../../runner/services/mock_flutter_runner_client.dart';
import '../../runner/services/runner_preview_tab.dart';
import '../../runner/widgets/runner_target_dialog.dart';
import '../../workspace/services/hive_workspace_persistence.dart';
import '../../workspace/services/keyed_workspace_snapshot_store.dart';
import '../../workspace/services/workspace_persistence.dart';
import '../../workspace/services/workspace_project_library.dart';
import '../../workspace/services/workspace_share_service.dart';
import '../../workspace/services/workspace_snapshot_store.dart';
import '../../workspace/widgets/workspace_project_bar.dart';
import '../controllers/playground_controller.dart';
import '../models/workspace_view_mode.dart';
import '../widgets/compact_playground_layout.dart';
import '../widgets/playground_toolbar.dart';
import '../widgets/tablet_playground_layout.dart';
import '../widgets/wide_playground_layout.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  static const _runnerApiUrl = String.fromEnvironment(
    'RUNNER_API_URL',
  );

  late PlaygroundController controller;
  late FlutterRunnerController runner;

  WorkspacePersistence? _workspacePersistence;
  WorkspaceProjectLibrary? _projectLibrary;
  KeyedWorkspaceSnapshotStore? _activeProjectStore;
  RunnerPreviewTabHandle? _pendingWebPreviewTab;
  WorkspaceViewMode _viewMode = WorkspaceViewMode.project;

  @override
  void initState() {
    super.initState();
    _initializeProjectLibrary();
    _createControllers();
  }

  void _initializeProjectLibrary() {
    final persistence = HiveWorkspacePersistence.tryFromOpenBoxes();

    if (persistence == null) return;

    _workspacePersistence = persistence;

    _projectLibrary = WorkspaceProjectLibrary.fromPersistence(
      persistence,
    );
  }

  void _createControllers() {
    final project = _projectLibrary?.activeProject;

    final snapshotStore = _workspacePersistence?.snapshotStore;

    WorkspaceSnapshotStore? workspaceStore = snapshotStore;

    if (project != null && snapshotStore != null) {
      final projectStore = KeyedWorkspaceSnapshotStore(
        delegate: snapshotStore,
        storageKey: project.storageKey,
      );

      _activeProjectStore = projectStore;
      workspaceStore = projectStore;
    } else {
      _activeProjectStore = null;
    }

    controller = PlaygroundController(
      workspaceStore: workspaceStore,
    )..addListener(_refresh);

    runner = FlutterRunnerController(
      workspace: controller.workspace,
      client: _runnerApiUrl.isEmpty
          ? MockFlutterRunnerClient()
          : HttpFlutterRunnerClient(
              baseUrl: _runnerApiUrl,
            ),
    )..addListener(_refresh);

    if (_viewMode.isConcept) {
      _ensureConceptActiveFile();
    }
  }

  void _disposeControllers() {
    _closePendingWebPreviewTab();

    runner.removeListener(_refresh);
    runner.dispose();

    controller.removeListener(_refresh);
    controller.dispose();

    _activeProjectStore = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _refresh() {
    final pendingTab = _pendingWebPreviewTab;

    if (pendingTab != null) {
      final previewUrl = runner.previewUrl;

      if (runner.canHotReload && previewUrl != null) {
        pendingTab.navigate(
          previewUrl,
        );

        _pendingWebPreviewTab = null;
      } else if (runner.status == RunnerStatus.error ||
          runner.status == RunnerStatus.stopped) {
        pendingTab.close();

        _pendingWebPreviewTab = null;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _closePendingWebPreviewTab() {
    _pendingWebPreviewTab?.close();
    _pendingWebPreviewTab = null;
  }

  void _changeViewMode(WorkspaceViewMode mode) {
    if (_viewMode == mode) return;

    _viewMode = mode;

    if (mode.isConcept) {
      _ensureConceptActiveFile();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _ensureConceptActiveFile() {
    final activePath = controller.activeFilePath;

    if (WorkspaceViewMode.concept.allowsPath(activePath)) {
      return;
    }

    final mainFile = controller.workspace.entryAt('lib/main.dart');
    if (mainFile != null && mainFile.isFile) {
      controller.selectWorkspaceFile('lib/main.dart');
      return;
    }

    for (final entry in controller.workspace.entries) {
      if (!entry.isFile) continue;
      if (!WorkspaceViewMode.concept.allowsPath(entry.path)) continue;

      controller.selectWorkspaceFile(entry.path);
      return;
    }
  }

  void _showRunTargetDialog(
    BuildContext dialogContext, {
    TabController? compactTabs,
  }) {
    if (!runner.canRun) return;

    showDialog<void>(
      context: dialogContext,
      builder: (_) => RunnerTargetDialog(
        onSelected: (target) {
          unawaited(
            _runTarget(
              target,
              compactTabs: compactTabs,
            ),
          );
        },
      ),
    );
  }

  Future<void> _runTarget(
    RunnerPreviewTarget target, {
    TabController? compactTabs,
  }) async {
    if (!runner.canRun) return;

    if (target.opensExternalTab && !runner.isMock) {
      _closePendingWebPreviewTab();

      final tab = openRunnerPreviewTab();

      if (tab.opened) {
        _pendingWebPreviewTab = tab;
      } else {
        scheduleMicrotask(() {
          if (!mounted) return;

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(
              content: Text(
                '浏览器阻止了网页预览标签页。请允许本站打开弹窗后重新运行。',
              ),
            ),
          );
        });
      }
    } else if (target.opensExternalTab && runner.isMock) {
      scheduleMicrotask(() {
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Mock Runner 没有真实网页 Preview URL。请连接真实 Runner 后使用网页运行。',
            ),
          ),
        );
      });
    }

    runner.selectPreviewTarget(
      target,
    );

    await runner.run();

    if (!mounted || target.opensExternalTab) {
      return;
    }

    compactTabs?.animateTo(1);
  }

  Future<void> _switchProject(
    String projectId,
  ) async {
    final library = _projectLibrary;

    if (library == null || projectId == library.activeProjectId) {
      return;
    }

    final previousId = library.activeProjectId;

    await controller.flushWorkspacePersistence();

    await library.touchProject(
      previousId,
    );

    await library.selectProject(
      projectId,
    );

    await library.touchProject(
      projectId,
    );

    _disposeControllers();
    _createControllers();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _createProject() async {
    final library = _projectLibrary;

    if (library == null) return;

    if (_runnerApiUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            '创建真实 Flutter 项目需要连接 Flutter Runner。',
          ),
        ),
      );

      return;
    }

    final request = await showCreateFlutterProjectDialog(
      context,
    );

    if (request == null || !mounted) {
      return;
    }

    final scaffoldService = FlutterProjectScaffoldService(
      baseUrl: _runnerApiUrl,
    );

    try {
      await controller.flushWorkspacePersistence();

      await library.touchProject(
        library.activeProjectId,
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '正在创建 Flutter 项目 ${request.projectName}...',
          ),
        ),
      );

      final snapshot = await scaffoldService.create(
        projectName: request.projectName,
        platforms: request.platforms,
      );

      if (!mounted) return;

      await library.createGeneratedFlutter(
        name: request.projectName,
        snapshot: snapshot,
        platforms: request.platforms,
      );

      _disposeControllers();
      _createControllers();

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '${request.projectName} 创建完成',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '创建 Flutter 项目失败：$error',
          ),
        ),
      );
    } finally {
      scaffoldService.close();
    }
  }

  Future<void> _openLocalFlutterProjectFolder() async {
    final library = _projectLibrary;

    if (library == null || !supportsWorkspaceDirectoryPicker) {
      return;
    }

    try {
      final files = await pickWorkspaceDirectory();

      if (files == null || files.isEmpty || !mounted) {
        return;
      }

      final bundle = const FlutterProjectDirectoryImportService().parse(files);

      await controller.flushWorkspacePersistence();

      await library.touchProject(
        library.activeProjectId,
      );

      await library.createImportedFlutter(
        name: bundle.projectName,
        snapshot: bundle.snapshot,
      );

      _disposeControllers();
      _createControllers();

      if (!mounted) return;

      setState(() {});

      final ignored = bundle.ignoredFileCount == 0
          ? ''
          : '，忽略 ${bundle.ignoredFileCount} 个生成/缓存文件';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '已打开 ${bundle.projectName}：${bundle.importedFileCount} 个文件$ignored。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '打开 Flutter 项目文件夹失败：$error',
          ),
        ),
      );
    }
  }

  Future<void> _importExistingFlutterProject() async {
    final library = _projectLibrary;

    if (library == null || !supportsWorkspaceImportPicker) {
      return;
    }

    try {
      final bytes = await pickWorkspaceImport();

      if (bytes == null || !mounted) {
        return;
      }

      final bundle = const FlutterProjectZipImportService().parse(bytes);

      await controller.flushWorkspacePersistence();

      await library.touchProject(
        library.activeProjectId,
      );

      await library.createImportedFlutter(
        name: bundle.projectName,
        snapshot: bundle.snapshot,
      );

      _disposeControllers();
      _createControllers();

      if (!mounted) return;

      setState(() {});

      final ignored = bundle.ignoredFileCount == 0
          ? ''
          : '，忽略 ${bundle.ignoredFileCount} 个生成/平台文件';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${bundle.projectName}：${bundle.importedFileCount} 个文本文件$ignored。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Flutter ZIP 导入失败：$error',
          ),
        ),
      );
    }
  }

  Future<void> _renameProject() async {
    final library = _projectLibrary;

    if (library == null) return;

    final project = library.activeProject;

    final name = await _askProjectName(
      title: '重命名练习',
      initialValue: project.name,
    );

    if (name == null || !mounted) {
      return;
    }

    try {
      await library.renameProject(
        project.id,
        name,
      );

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '重命名失败：$error',
          ),
        ),
      );
    }
  }

  Future<void> _keepProject() async {
    final library = _projectLibrary;

    if (library == null) return;

    final project = library.activeProject;

    try {
      await library.keepProject(
        project.id,
      );

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '已保留 ${project.name}，不会再作为临时练习处理。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '保留 Workspace 失败：$error',
          ),
        ),
      );
    }
  }

  Future<void> _deleteProject([String? projectId]) async {
    final library = _projectLibrary;

    if (library == null || library.projects.length <= 1) {
      return;
    }

    final project = projectId == null
        ? library.activeProject
        : library.projectById(projectId);
    if (project == null) return;

    final deletingActiveProject = project.id == library.activeProjectId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(
            Icons.delete_forever_outlined,
            color: scheme.error,
          ),
          title: Text(
            '删除 ${project.name}？',
          ),
          content: const Text(
            '这会永久删除这个项目的 Workspace 数据和快照。'
            '如果当前使用云端 Workspace，对应云端数据也会一起删除。'
            '此操作无法撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                false,
              ),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(
                dialogContext,
                true,
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('永久删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    var controllersDisposed = false;

    try {
      if (deletingActiveProject) {
        await controller.flushWorkspacePersistence();

        _activeProjectStore?.disableWrites();
        _disposeControllers();
        controllersDisposed = true;
      }

      await library.deleteProject(
        project.id,
      );
    } catch (error) {
      if (controllersDisposed) {
        _createControllers();
      }

      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              '删除失败：$error',
            ),
          ),
        );
      }

      return;
    }

    if (controllersDisposed) {
      _createControllers();
    }

    if (mounted) {
      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '已删除 ${project.name}',
          ),
        ),
      );
    }
  }

  Future<void> _shareCurrentProject() async {
    final library = _projectLibrary;
    if (library == null) return;

    final project = library.activeProject;
    try {
      // The server snapshots the durable cloud Workspace. Flush local edits
      // first so the generated link always points at what the user currently
      // sees in the editor.
      await controller.flushWorkspacePersistence();

      final share = await WorkspaceShareService().createShare(project.id);
      await Clipboard.setData(ClipboardData(text: share.url.toString()));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '只读分享链接已复制 · ${share.revision}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('创建只读分享失败：$error'),
        ),
      );
    }
  }

  Future<void> _commitWorkspace() async {
    final staged = controller.workspace.stagedChanges;
    if (staged.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('先在 Git 视角 Stage 至少一个修改。'),
          ),
        );
      }
      return;
    }

    final message = await _askCommitMessage();
    if (message == null || !mounted) return;

    final beforeCommit = controller.workspace.createSnapshot();
    final stagedPaths =
        staged.map((change) => change.path).toSet().toList(growable: false);
    final committed = controller.workspace.commitStagedChanges();
    if (!committed) return;

    try {
      await controller.flushWorkspacePersistence();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已 Commit ${stagedPaths.length} 个文件 · $message'),
        ),
      );
    } catch (error) {
      controller.workspace.restoreSnapshot(beforeCommit);
      for (final path in stagedPaths) {
        controller.workspace.stagePath(path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commit 失败：$error'),
        ),
      );
    }
  }

  Future<String?> _askCommitMessage() async {
    final changes = controller.workspace.stagedChanges;
    if (changes.isEmpty) return null;

    final messageController = TextEditingController();
    var canCommit = false;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xff15191f),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xff2b333e)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.commit_rounded,
                            size: 19,
                            color: Color(0xff82aaff),
                          ),
                          SizedBox(width: 9),
                          Text(
                            'Commit Workspace',
                            style: TextStyle(
                              color: Color(0xffd7dde8),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${changes.length} 个已 Stage 修改将写入云端 Workspace 版本基线。不会执行 Push。',
                        style: const TextStyle(
                          color: Color(0xff8f98a8),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 126),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff111318),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xff272d36),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final change in changes.take(8))
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '• ${change.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xffb8c0cc),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              if (changes.length > 8)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '还有 ${changes.length - 8} 个修改…',
                                    style: const TextStyle(
                                      color: Color(0xff707988),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextField(
                        controller: messageController,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 240,
                        style: const TextStyle(
                          color: Color(0xffd7dde8),
                          fontSize: 13,
                        ),
                        cursorColor: const Color(0xff82aaff),
                        decoration: InputDecoration(
                          labelText: 'Commit message',
                          hintText: '例如：完成商城结账流程',
                          labelStyle: const TextStyle(
                            color: Color(0xff9da5b4),
                          ),
                          hintStyle: const TextStyle(
                            color: Color(0xff66707f),
                          ),
                          counterStyle: const TextStyle(
                            color: Color(0xff66707f),
                            fontSize: 10.5,
                          ),
                          filled: true,
                          fillColor: const Color(0xff111318),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xff2b333e),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xff2b333e),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xff82aaff),
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          final next = value.trim().isNotEmpty;
                          if (next == canCommit) return;
                          setDialogState(() => canCommit = next);
                        },
                        onSubmitted: (_) {
                          if (!canCommit) return;
                          Navigator.pop(
                            dialogContext,
                            messageController.text.trim(),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xffaab2bf),
                            ),
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 7),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xff3f74a6),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xff25303b),
                              disabledForegroundColor: const Color(0xff66707f),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            onPressed: canCommit
                                ? () => Navigator.pop(
                                      dialogContext,
                                      messageController.text.trim(),
                                    )
                                : null,
                            icon: const Icon(Icons.commit_rounded, size: 17),
                            label: const Text('Commit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    messageController.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  Future<String?> _askProjectName({
    required String title,
    required String initialValue,
  }) async {
    final textController = TextEditingController(
      text: initialValue,
    );

    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialValue.length,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.pop(
            context,
            value.trim(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              textController.text.trim(),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    textController.dispose();

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
  }

  Widget _buildToolbar({
    required bool compact,
    VoidCallback? onRun,
    VoidCallback? onQuickPreview,
  }) {
    final library = _projectLibrary;

    final projectControls = library == null
        ? null
        : WorkspaceProjectBar(
            projects: library.projects,
            activeProject: library.activeProject,
            onSelect: (id) => unawaited(
              _switchProject(id),
            ),
            onCreate: () => unawaited(
              _createProject(),
            ),
            onOpenFolder: supportsWorkspaceDirectoryPicker
                ? () => unawaited(
                      _openLocalFlutterProjectFolder(),
                    )
                : null,
            onImportZip: supportsWorkspaceImportPicker
                ? () => unawaited(
                      _importExistingFlutterProject(),
                    )
                : null,
            onCommit: controller.workspace.hasStagedChanges
                ? () => unawaited(
                      _commitWorkspace(),
                    )
                : null,
            onShare: () => unawaited(
              _shareCurrentProject(),
            ),
            onKeep: () => unawaited(
              _keepProject(),
            ),
            onRename: () => unawaited(
              _renameProject(),
            ),
            onDelete: () => unawaited(
              _deleteProject(),
            ),
          );

    return PlaygroundToolbar(
      controller: controller,
      runner: runner,
      compact: compact,
      projectControls: projectControls,
      onRun: onRun,
      onQuickPreview: onQuickPreview,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) =>
      Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isAndroidTablet = !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android &&
                  constraints.maxWidth >= 600 &&
                  constraints.maxHeight >= 600;
              final isCompact = constraints.maxWidth < 700;

              if (isAndroidTablet) {
                final library = _projectLibrary;

                return TabletPlaygroundLayout(
                  controller: controller,
                  runner: runner,
                  viewMode: _viewMode,
                  onViewModeChanged: _changeViewMode,
                  onRun: () => _showRunTargetDialog(context),
                  projects: library?.projects,
                  activeProject: library?.activeProject,
                  onSelectProject: library == null
                      ? null
                      : (id) => unawaited(
                            _switchProject(id),
                          ),
                  onCreateProject: library == null
                      ? null
                      : () => unawaited(
                            _createProject(),
                          ),
                  onOpenFolder:
                      library != null && supportsWorkspaceDirectoryPicker
                          ? () => unawaited(
                                _openLocalFlutterProjectFolder(),
                              )
                          : null,
                  onImportZip: library != null && supportsWorkspaceImportPicker
                      ? () => unawaited(
                            _importExistingFlutterProject(),
                          )
                      : null,
                  onCommit:
                      library != null && controller.workspace.hasStagedChanges
                          ? () => unawaited(
                                _commitWorkspace(),
                              )
                          : null,
                  onShare: library == null
                      ? null
                      : () => unawaited(
                            _shareCurrentProject(),
                          ),
                  onKeep: library == null
                      ? null
                      : () => unawaited(
                            _keepProject(),
                          ),
                  onRename: library == null
                      ? null
                      : () => unawaited(
                            _renameProject(),
                          ),
                  onDeleteProject:
                      library == null || library.projects.length <= 1
                          ? null
                          : (id) => unawaited(
                                _deleteProject(id),
                              ),
                );
              }

              if (isCompact) {
                return DefaultTabController(
                  length: 4,
                  child: Builder(
                    builder: (tabContext) {
                      final tabs = DefaultTabController.of(
                        tabContext,
                      );

                      return CompactPlaygroundLayout(
                        controller: controller,
                        runner: runner,
                        viewMode: _viewMode,
                        onViewModeChanged: _changeViewMode,
                        toolbar: _buildToolbar(
                          compact: true,
                          onRun: () => _showRunTargetDialog(
                            tabContext,
                            compactTabs: tabs,
                          ),
                          onQuickPreview: () {
                            controller.runCode();

                            tabs.animateTo(
                              1,
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              }

              return WidePlaygroundLayout(
                controller: controller,
                runner: runner,
                viewMode: _viewMode,
                onViewModeChanged: _changeViewMode,
                toolbar: _buildToolbar(
                  compact: false,
                  onRun: () => _showRunTargetDialog(
                    context,
                  ),
                ),
              );
            },
          ),
        ),
      );
}
