import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_pull.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_push.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote_check.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_push_coordinator.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_remote_service.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  test('first guarded push loads Cloud revision before staging local snapshot', () async {
    final catalog = _MemoryCatalogStore();
    final snapshots = _MemorySnapshotStore();
    final projects = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );
    await projects.bindGitRemote(
      projects.activeProject.id,
      WorkspaceGitRemote(
        repositoryUrl: 'https://github.com/team/app.git',
        branch: 'main',
        lastSyncedHead: 'aaaaaaaaaaaaaaaa',
      ),
    );

    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}\n',
    );
    addTearDown(workspace.dispose);
    workspace.updateFileContent(
      'lib/main.dart',
      'void main() => print("first push");\n',
    );

    final remote = _ResolvingRemote(projects.activeProject);
    final git = _RecordingGit();
    final coordinator = WorkspaceGitPushCoordinator(
      workspace: workspace,
      projects: projects,
      remote: remote,
      git: git,
    );

    await coordinator.pushCurrent(
      commitMessage: 'feat: first guarded push',
      authorName: 'Alice Developer',
      authorEmail: 'alice@example.com',
    );

    expect(remote.loadedWorkspaceId, projects.activeProject.id);
    expect(remote.lastExpectedRevision, 'r7');
    expect(git.expectedWorkspaceRevision, 'r8');
    expect(coordinator.cloudRevision, 'r8');
    expect(workspace.isDirty, isFalse);
  });
}

class _ResolvingRemote implements WorkspaceRemotePersistence {
  _ResolvingRemote(this.project);

  final WorkspaceProject project;

  @override
  final WorkspaceIdentity identity = const WorkspaceIdentity(userId: 'alice');

  String? loadedWorkspaceId;
  String? lastExpectedRevision;

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async {
    loadedWorkspaceId = workspaceId;
    return WorkspaceRemoteDocument(
      project: project,
      snapshot: WorkspaceController.flutterPlayground(
        mainDartContent: 'void main() {}\n',
      ).createSnapshot(),
      revision: 'r7',
    );
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    lastExpectedRevision = expectedRevision;
    return WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r8',
    );
  }

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) => throw StateError('existing Cloud Workspace should be reused');

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() => throw UnimplementedError();

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) => throw UnimplementedError();
}

class _RecordingGit implements WorkspaceGitRemoteService {
  String? expectedWorkspaceRevision;

  @override
  Future<WorkspaceGitPushResult> pushRemote({
    required String workspaceId,
    required String expectedWorkspaceRevision,
    required String expectedRemoteHead,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? secretName,
    String? username,
  }) async {
    this.expectedWorkspaceRevision = expectedWorkspaceRevision;
    return const WorkspaceGitPushResult(
      repositoryUrl: 'https://github.com/team/app.git',
      branch: 'main',
      provider: 'github',
      previousRemoteHead: 'aaaaaaaaaaaaaaaa',
      newRemoteHead: 'bbbbbbbbbbbbbbbb',
      committed: true,
    );
  }

  @override
  Future<WorkspaceGitRemoteCheckResult> checkRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) => throw UnimplementedError();

  @override
  Future<WorkspaceGitPullResult> pullRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) => throw UnimplementedError();
}

class _MemoryCatalogStore implements WorkspaceProjectCatalogStore {
  List<WorkspaceProject> projects = <WorkspaceProject>[];
  String? activeProjectId;

  @override
  List<WorkspaceProject> loadProjects() => projects
      .map((project) => WorkspaceProject.fromJson(project.toJson()))
      .toList(growable: false);

  @override
  String? loadActiveProjectId() => activeProjectId;

  @override
  Future<void> saveProjects(List<WorkspaceProject> next) async {
    projects = next
        .map((project) => WorkspaceProject.fromJson(project.toJson()))
        .toList(growable: false);
  }

  @override
  Future<void> saveActiveProjectId(String projectId) async {
    activeProjectId = projectId;
  }
}

class _MemorySnapshotStore implements WorkspaceSnapshotStore {
  final Map<String, WorkspaceSnapshot> values = <String, WorkspaceSnapshot>{};

  @override
  WorkspaceSnapshot? load(String key) => values[key];

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    values[key] = snapshot;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
