import 'package:http/http.dart' as http;

import '../../workspace/models/workspace_git_pull.dart';
import '../../workspace/models/workspace_git_remote.dart';
import '../../workspace/models/workspace_identity.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../../workspace/services/http_workspace_git_remote_service.dart';
import '../../workspace/services/http_workspace_remote_persistence.dart';
import '../../workspace/services/keyed_workspace_snapshot_store.dart';
import '../../workspace/services/workspace_git_connection_runtime.dart';
import '../../workspace/services/workspace_persistence.dart';
import '../../workspace/services/workspace_project_library.dart';
import '../models/concept_project_context.dart';
import 'concept_project_projection_service.dart';

typedef ConceptGitProjectSelector =
    Future<WorkspaceGitFlutterProjectCandidate?> Function(
  List<WorkspaceGitFlutterProjectCandidate> candidates,
);

class ConceptGitImportRequest {
  const ConceptGitImportRequest({
    required this.repositoryUrl,
    this.branch = 'main',
    this.projectPath,
    this.secretName,
    this.secretValue,
    this.username,
  });

  final String repositoryUrl;
  final String branch;
  final String? projectPath;
  final String? secretName;
  final String? secretValue;
  final String? username;
}

class ConceptGitImportResult {
  const ConceptGitImportResult({
    required this.project,
    required this.projection,
    required this.workspaceStore,
    required this.importedFileCount,
    required this.ignoredFileCount,
  });

  final WorkspaceProject project;
  final ConceptProjectProjection projection;
  final KeyedWorkspaceSnapshotStore workspaceStore;
  final int importedFileCount;
  final int ignoredFileCount;
}

class ConceptGitImportService {
  const ConceptGitImportService();

  Future<ConceptGitImportResult?> import({
    required WorkspacePersistence persistence,
    required WorkspaceSnapshot seedSnapshot,
    required ConceptGitImportRequest request,
    ConceptGitProjectSelector? selectProject,
  }) async {
    final runtime = WorkspaceGitConnectionRuntime.tryFromEnvironment();
    if (runtime == null) {
      throw StateError(
        '直接从 Git 打开项目需要配置 WORKSPACE_STORAGE_API_URL 和 '
        'WORKSPACE_ACCESS_TOKEN。',
      );
    }

    final baseUri = Uri.tryParse(WorkspaceGitConnectionRuntime.apiUrl.trim());
    if (baseUri == null) {
      runtime.close();
      throw StateError('WORKSPACE_STORAGE_API_URL 无效。');
    }

    final library = WorkspaceProjectLibrary.fromPersistence(persistence);
    final initialRemote = WorkspaceGitRemote(
      repositoryUrl: request.repositoryUrl,
      branch: request.branch,
      projectPath: request.projectPath,
    );
    final placeholderName = _repositoryName(initialRemote.repositoryUrl);
    WorkspaceProject? created;
    final client = http.Client();

    try {
      created = await library.createImportedFlutter(
        name: placeholderName,
        snapshot: seedSnapshot,
      );
      await library.bindGitRemote(created.id, initialRemote);

      var boundProject = library.projectById(created.id)!;
      await runtime.coordinator.check(
        project: boundProject,
        snapshot: seedSnapshot,
        secretName: _clean(request.secretName),
        secretValue: _secretValue(request.secretValue),
        username: _clean(request.username),
      );

      final git = HttpWorkspaceGitRemoteService(
        baseUri: baseUri,
        accessToken: WorkspaceGitConnectionRuntime.accessToken,
        client: client,
      );

      WorkspaceGitPullResult pulled;
      try {
        pulled = await git.pullRepositoryRemote(
          workspaceId: created.id,
          secretName: _clean(request.secretName),
          username: _clean(request.username),
        );
      } on WorkspaceGitProjectSelectionRequired catch (selection) {
        if (selectProject == null) rethrow;

        final selected = await selectProject(selection.candidates);
        if (selected == null) {
          await _cleanupProject(
            library: library,
            projectId: created.id,
            baseUri: baseUri,
            client: client,
          );
          created = null;
          return null;
        }
        if (selected.projectPath == null) {
          throw StateError(
            'Repository-root Flutter selection is not supported when the same '
            'repository also contains nested runnable Flutter apps.',
          );
        }

        final selectedRemote = WorkspaceGitRemote(
          repositoryUrl: initialRemote.repositoryUrl,
          remoteName: initialRemote.remoteName,
          branch: initialRemote.branch,
          projectPath: selected.projectPath,
          provider: initialRemote.provider,
        );
        await library.bindGitRemote(created.id, selectedRemote);
        boundProject = library.projectById(created.id)!;

        await runtime.coordinator.check(
          project: boundProject,
          snapshot: seedSnapshot,
          secretName: _clean(request.secretName),
          username: _clean(request.username),
        );

        pulled = await git.pullRepositoryRemote(
          workspaceId: created.id,
          secretName: _clean(request.secretName),
          username: _clean(request.username),
        );
      }

      return _finalizeImport(
        persistence: persistence,
        library: library,
        runtime: runtime,
        created: created!,
        pulled: pulled,
        request: request,
      );
    } catch (_) {
      final project = created;
      if (project != null && library.projectById(project.id) != null) {
        await _cleanupProject(
          library: library,
          projectId: project.id,
          baseUri: baseUri,
          client: client,
        );
      }
      rethrow;
    } finally {
      client.close();
      runtime.close();
    }
  }

  Future<ConceptGitImportResult> _finalizeImport({
    required WorkspacePersistence persistence,
    required WorkspaceProjectLibrary library,
    required WorkspaceGitConnectionRuntime runtime,
    required WorkspaceProject created,
    required WorkspaceGitPullResult pulled,
    required ConceptGitImportRequest request,
  }) async {
    final repositorySnapshot = pulled.toSnapshot();
    const projectionService = ConceptProjectProjectionService();
    final flutterProjects =
        projectionService.detectFlutterProjects(repositorySnapshot);
    final selectedRoot = pulled.repositoryRelativePaths
        ? (pulled.projectPath ?? '')
        : '';
    final selected = flutterProjects.where(
      (candidate) => candidate.projectRoot == selectedRoot,
    );
    if (selected.length != 1) {
      throw StateError(
        'Unable to resolve the selected Flutter app inside the imported repository.',
      );
    }

    final projection = projectionService.project(
      repositorySnapshot: repositorySnapshot,
      repositoryName: _repositoryDisplayName(pulled.repositoryUrl),
      candidate: selected.single,
    );
    final snapshot = projection.snapshot;

    await library.snapshotStore.save(created.storageKey, snapshot);
    await library.renameProject(created.id, pulled.projectName);
    await library.markGitPullSynced(
      created.id,
      remoteHead: pulled.remoteHead,
      projectPath: pulled.projectPath,
    );

    final savedProject = library.projectById(created.id)!;
    await runtime.coordinator.check(
      project: savedProject,
      snapshot: snapshot,
      secretName: _clean(request.secretName),
      username: _clean(request.username),
    );

    final store = KeyedWorkspaceSnapshotStore(
      delegate: persistence.snapshotStore,
      storageKey: savedProject.storageKey,
    );

    return ConceptGitImportResult(
      project: savedProject,
      projection: projection,
      workspaceStore: store,
      importedFileCount: pulled.importedFileCount,
      ignoredFileCount: pulled.ignoredFileCount,
    );
  }

  Future<void> _cleanupProject({
    required WorkspaceProjectLibrary library,
    required String projectId,
    required Uri baseUri,
    required http.Client client,
  }) async {
    try {
      final remote = HttpWorkspaceRemotePersistence(
        identity: WorkspaceIdentity(
          userId: WorkspaceGitConnectionRuntime.userId,
        ),
        baseUri: baseUri,
        accessToken: WorkspaceGitConnectionRuntime.accessToken,
        client: client,
      );
      final document = await remote.loadWorkspace(projectId);
      if (document != null) {
        await remote.deleteWorkspace(
          workspaceId: projectId,
          expectedRevision: document.revision,
        );
      }
    } catch (_) {}

    if (library.projectById(projectId) != null) {
      try {
        await library.deleteProject(projectId);
      } catch (_) {}
    }
  }

  String? _clean(String? value) {
    if (value == null) return null;
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  String? _secretValue(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String _repositoryName(String repositoryUrl) {
    final display = _repositoryDisplayName(repositoryUrl);
    final parts = display.split('/');
    return parts.isEmpty ? 'Git Flutter Project' : parts.last;
  }

  String _repositoryDisplayName(String repositoryUrl) {
    final scp = RegExp(r'^[^@]+@[^:]+:(.+)$').firstMatch(repositoryUrl);
    var path = scp?.group(1);
    if (path == null) {
      final uri = Uri.tryParse(repositoryUrl);
      if (uri != null && uri.host.isNotEmpty) path = uri.path;
    }
    if (path == null) return repositoryUrl;

    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 2) return repositoryUrl;
    final owner = segments[segments.length - 2];
    final repo = segments.last.replaceFirst(RegExp(r'\.git$'), '');
    return '$owner/$repo';
  }
}
