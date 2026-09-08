import 'package:http/http.dart' as http;

import '../../workspace/models/workspace_git_remote.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../../workspace/services/http_workspace_git_remote_service.dart';
import '../../workspace/services/keyed_workspace_snapshot_store.dart';
import '../../workspace/services/workspace_git_connection_runtime.dart';
import '../../workspace/services/workspace_persistence.dart';
import '../../workspace/services/workspace_project_library.dart';
import '../models/concept_project_context.dart';

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

  Future<ConceptGitImportResult> import({
    required WorkspacePersistence persistence,
    required WorkspaceSnapshot seedSnapshot,
    required ConceptGitImportRequest request,
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
    final remote = WorkspaceGitRemote(
      repositoryUrl: request.repositoryUrl,
      branch: request.branch,
      projectPath: request.projectPath,
    );
    final placeholderName = _repositoryName(remote.repositoryUrl);
    WorkspaceProject? created;
    final gitClient = http.Client();

    try {
      created = await library.createImportedFlutter(
        name: placeholderName,
        snapshot: seedSnapshot,
      );
      await library.bindGitRemote(created.id, remote);

      final boundProject = library.projectById(created.id)!;
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
        client: gitClient,
      );
      final pulled = await git.pullRemote(
        workspaceId: created.id,
        secretName: _clean(request.secretName),
        username: _clean(request.username),
      );
      final snapshot = pulled.toSnapshot();

      await library.snapshotStore.save(created.storageKey, snapshot);
      await library.renameProject(created.id, pulled.projectName);
      await library.markGitSyncedHead(created.id, pulled.remoteHead);

      final savedProject = library.projectById(created.id)!;
      final projectRoot = savedProject.gitRemote?.projectPath ?? '';
      final projection = ConceptProjectProjection(
        context: ConceptProjectContext(
          repositoryName: _repositoryDisplayName(pulled.repositoryUrl),
          projectName: pulled.projectName,
          projectRoot: projectRoot,
        ),
        snapshot: snapshot,
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
    } catch (_) {
      if (created != null && library.projectById(created.id) != null) {
        await library.deleteProject(created.id);
      }
      rethrow;
    } finally {
      gitClient.close();
      runtime.close();
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
