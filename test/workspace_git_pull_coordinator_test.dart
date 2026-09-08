import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_pull.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_push.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote_check.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_pull_coordinator.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_remote_service.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  late _MemoryCatalogStore catalog;
  late _MemorySnapshotStore snapshots;
  late WorkspaceProjectLibrary projects;
  late WorkspaceController workspace;
  late _FakeGitRemoteService git;
  late WorkspaceGitPullCoordinator coordinator;

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
      ),
    );
    workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}\n',
    );
    git = _FakeGitRemoteService();
    coordinator = WorkspaceGitPullCoordinator(
      workspace: workspace,
      projects: projects,
      git: git,
    );
  });

  test('clean pull replaces Workspace and persists detected root and synced head', () async {
    git.pullResult = _result(
      projectPath: 'apps/mobile',
      files: const <String, String>{
        'pubspec.yaml': 'name: remote_app\n',
        'lib/main.dart': 'void main() => print("remote");\n',
        'lib/app.dart': 'class RemoteApp {}\n',
      },
    );

    final result = await coordinator.pullCurrent(secretName: 'GITHUB_TOKEN');

    expect(result.remoteHead, 'abcdef1234567890');
    expect(result.projectPath, 'apps/mobile');
    expect(git.lastWorkspaceId, WorkspaceProjectLibrary.defaultProjectId);
    expect(git.lastSecretName, 'GITHUB_TOKEN');
    expect(
      workspace.entryAt('lib/main.dart')?.content,
      'void main() => print("remote");\n',
    );
    expect(workspace.isDirty, isFalse);
    expect(
      projects.activeProject.gitRemote?.lastSyncedHead,
      'abcdef1234567890',
    );
    expect(
      projects.activeProject.gitRemote?.projectPath,
      'apps/mobile',
    );
    expect(
      catalog.projects.single.gitRemote?.projectPath,
      'apps/mobile',
    );
    final saved = snapshots.load(projects.activeProject.storageKey);
    expect(saved?.activePath, 'lib/main.dart');
    expect(
      saved?.entries.any((entry) => entry.path == 'lib/app.dart'),
      isTrue,
    );
  });

  test('dirty Workspace is protected from accidental pull overwrite', () async {
    workspace.updateFileContent(
      'lib/main.dart',
      'void main() => print("local change");\n',
    );
    git.pullResult = _result(
      files: const <String, String>{
        'pubspec.yaml': 'name: remote_app\n',
        'lib/main.dart': 'void main() => print("remote");\n',
      },
    );

    await expectLater(
      coordinator.pullCurrent(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('local changes'),
        ),
      ),
    );

    expect(git.pullCalls, 0);
    expect(
      workspace.entryAt('lib/main.dart')?.content,
      contains('local change'),
    );
  });

  test('pull refuses a result for another remote binding', () async {
    git.pullResult = WorkspaceGitPullResult(
      repositoryUrl: 'https://github.com/other/app.git',
      branch: 'main',
      provider: 'github',
      projectName: 'remote_app',
      projectPath: 'apps/mobile',
      remoteHead: 'abcdef1234567890',
      files: const <String, String>{
        'pubspec.yaml': 'name: remote_app\n',
        'lib/main.dart': 'void main() {}\n',
      },
      importedFileCount: 2,
      ignoredFileCount: 0,
    );

    await expectLater(
      coordinator.pullCurrent(),
      throwsA(isA<StateError>()),
    );
    expect(
      workspace.entryAt('lib/main.dart')?.content,
      'void main() {}\n',
    );
    expect(projects.activeProject.gitRemote?.projectPath, isNull);
    expect(projects.activeProject.gitRemote?.lastSyncedHead, isNull);
  });
}

WorkspaceGitPullResult _result({
  required Map<String, String> files,
  String? projectPath,
}) {
  return WorkspaceGitPullResult(
    repositoryUrl: 'https://github.com/team/app.git',
    branch: 'main',
    provider: 'github',
    projectName: 'remote_app',
    projectPath: projectPath,
    remoteHead: 'abcdef1234567890',
    files: files,
    importedFileCount: files.length,
    ignoredFileCount: 0,
  );
}

class _FakeGitRemoteService implements WorkspaceGitRemoteService {
  late WorkspaceGitPullResult pullResult;
  int pullCalls = 0;
  String? lastWorkspaceId;
  String? lastSecretName;

  @override
  Future<WorkspaceGitPullResult> pullRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) async {
    pullCalls += 1;
    lastWorkspaceId = workspaceId;
    lastSecretName = secretName;
    return pullResult;
  }

  @override
  Future<WorkspaceGitRemoteCheckResult> checkRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) {
    throw UnimplementedError();
  }

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
  }) {
    throw UnimplementedError();
  }
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
