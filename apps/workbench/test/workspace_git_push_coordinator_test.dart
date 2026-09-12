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
  late _MemoryCatalogStore catalog;
  late _MemorySnapshotStore snapshots;
  late WorkspaceProjectLibrary projects;
  late WorkspaceController workspace;
  late _FakeRemotePersistence remote;
  late _FakeGitRemoteService git;
  late WorkspaceGitPushCoordinator coordinator;

  setUp(() async {
    catalog = _MemoryCatalogStore();
    snapshots = _MemorySnapshotStore();
    projects = WorkspaceProjectLibrary(
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
    workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}\n',
    );
    workspace.updateFileContent(
      'lib/main.dart',
      'void main() => print("local change");\n',
    );
    remote = _FakeRemotePersistence();
    git = _FakeGitRemoteService();
    coordinator = WorkspaceGitPushCoordinator(
      workspace: workspace,
      projects: projects,
      remote: remote,
      git: git,
      initialCloudRevision: 'r4',
    );
  });

  test('push stages exact Cloud revision then marks Git head and Workspace clean', () async {
    final result = await coordinator.pushCurrent(
      commitMessage: 'feat: sync workspace',
      authorName: 'Alice Developer',
      authorEmail: 'alice@example.com',
      secretName: 'GITHUB_TOKEN',
    );

    expect(remote.lastExpectedRevision, 'r4');
    expect(remote.lastSnapshot?.entries
        .singleWhere((entry) => entry.path == 'lib/main.dart')
        .content, contains('local change'));
    expect(git.lastExpectedWorkspaceRevision, 'r5');
    expect(git.lastExpectedRemoteHead, 'aaaaaaaaaaaaaaaa');
    expect(git.lastSecretName, 'GITHUB_TOKEN');
    expect(result.newRemoteHead, 'bbbbbbbbbbbbbbbb');
    expect(coordinator.cloudRevision, 'r5');
    expect(projects.activeProject.gitRemote?.lastSyncedHead, 'bbbbbbbbbbbbbbbb');
    expect(workspace.isDirty, isFalse);
    expect(snapshots.load(projects.activeProject.storageKey)?.baseEntries,
        hasLength(workspace.entries.length));
  });

  test('stale Cloud revision blocks Git push', () async {
    remote.conflict = const WorkspaceRevisionConflict(
      workspaceId: WorkspaceProjectLibrary.defaultProjectId,
      expectedRevision: 'r4',
      actualRevision: 'r5',
    );

    await expectLater(
      coordinator.pushCurrent(
        commitMessage: 'feat: should not push',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
      ),
      throwsA(isA<WorkspaceRevisionConflict>()),
    );

    expect(git.pushCalls, 0);
    expect(workspace.isDirty, isTrue);
    expect(coordinator.cloudRevision, 'r4');
  });

  test('remote HEAD conflict keeps local changes dirty but cloud draft staged', () async {
    git.conflict = const WorkspaceGitRemoteHeadConflict(
      workspaceId: WorkspaceProjectLibrary.defaultProjectId,
      expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
      actualRemoteHead: 'cccccccccccccccc',
    );

    await expectLater(
      coordinator.pushCurrent(
        commitMessage: 'feat: conflict',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
      ),
      throwsA(isA<WorkspaceGitRemoteHeadConflict>()),
    );

    expect(coordinator.cloudRevision, 'r5');
    expect(workspace.isDirty, isTrue);
    expect(projects.activeProject.gitRemote?.lastSyncedHead, 'aaaaaaaaaaaaaaaa');
  });
}

class _FakeRemotePersistence implements WorkspaceRemotePersistence {
  @override
  final WorkspaceIdentity identity = const WorkspaceIdentity(userId: 'alice');

  WorkspaceRevisionConflict? conflict;
  String? lastExpectedRevision;
  WorkspaceSnapshot? lastSnapshot;

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    final failure = conflict;
    if (failure != null) throw failure;
    lastExpectedRevision = expectedRevision;
    lastSnapshot = snapshot;
    return WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r5',
    );
  }

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() => throw UnimplementedError();

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) => throw UnimplementedError();

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) => throw UnimplementedError();
}

class _FakeGitRemoteService implements WorkspaceGitRemoteService {
  int pushCalls = 0;
  WorkspaceGitRemoteHeadConflict? conflict;
  String? lastExpectedWorkspaceRevision;
  String? lastExpectedRemoteHead;
  String? lastSecretName;

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
    pushCalls += 1;
    final failure = conflict;
    if (failure != null) throw failure;
    lastExpectedWorkspaceRevision = expectedWorkspaceRevision;
    lastExpectedRemoteHead = expectedRemoteHead;
    lastSecretName = secretName;
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
