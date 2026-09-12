import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_pull.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_push.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote_check.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_secret.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_connection_coordinator.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_git_remote_service.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_secret_service.dart';

void main() {
  late WorkspaceProject project;
  late WorkspaceSnapshot snapshot;
  late _FakeRemote remote;
  late _FakeSecrets secrets;
  late _FakeGit git;
  late WorkspaceGitConnectionCoordinator coordinator;

  setUp(() {
    final now = DateTime.utc(2026, 9, 3);
    project = WorkspaceProject(
      id: 'workspace-1',
      name: 'Flutter Practice',
      storageKey: 'workspace:1',
      kind: WorkspaceProjectKind.practice,
      lifecycle: WorkspaceLifecycle.saved,
      createdAt: now,
      updatedAt: now,
      gitRemote: WorkspaceGitRemote(
        repositoryUrl: 'https://github.com/team/app.git',
        branch: 'main',
      ),
    );
    final seed = PlaygroundController();
    snapshot = seed.workspace.createSnapshot();
    seed.dispose();

    remote = _FakeRemote();
    secrets = _FakeSecrets();
    git = _FakeGit();
    coordinator = WorkspaceGitConnectionCoordinator(
      remote: remote,
      secrets: secrets,
      git: git,
    );
  });

  test('check stages Workspace, saves Git secret, then checks remote', () async {
    final checked = await coordinator.check(
      project: project,
      snapshot: snapshot,
      secretName: 'GITHUB_TOKEN',
      secretValue: 'github_pat_example',
    );

    expect(remote.created, 1);
    expect(remote.saved, 0);
    expect(secrets.lastWorkspaceId, project.id);
    expect(secrets.lastName, 'GITHUB_TOKEN');
    expect(secrets.lastValue, 'github_pat_example');
    expect(secrets.lastContexts, {WorkspaceSecretContext.git});
    expect(git.lastWorkspaceId, project.id);
    expect(git.lastSecretName, 'GITHUB_TOKEN');
    expect(checked.savedSecret?.name, 'GITHUB_TOKEN');
    expect(checked.result.remoteHead, 'aaaaaaaaaaaaaaaa');
  });

  test('existing Workspace updates Git metadata without overwriting cloud source', () async {
    final cloudSeed = PlaygroundController();
    cloudSeed.workspace.updateFileContent(
      'lib/main.dart',
      'void main() => print("cloud source");\n',
    );
    final cloudSnapshot = cloudSeed.workspace.createSnapshot();
    cloudSeed.dispose();

    remote.document = WorkspaceRemoteDocument(
      project: project,
      snapshot: cloudSnapshot,
      revision: 'r7',
    );

    await coordinator.check(
      project: project,
      snapshot: snapshot,
    );

    expect(remote.created, 0);
    expect(remote.saved, 1);
    expect(remote.lastExpectedRevision, 'r7');
    expect(
      remote.lastSavedSnapshot?.entries
          .singleWhere((entry) => entry.path == 'lib/main.dart')
          .content,
      contains('cloud source'),
    );
    expect(git.lastSecretName, isNull);
  });

  test('Git secret name is required when a new value is supplied', () async {
    await expectLater(
      coordinator.check(
        project: project,
        snapshot: snapshot,
        secretValue: 'secret',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(secrets.putCalls, 0);
    expect(git.checkCalls, 0);
  });

  test('mismatched remote response is rejected', () async {
    git.repositoryUrl = 'https://github.com/other/repo.git';

    await expectLater(
      coordinator.check(project: project, snapshot: snapshot),
      throwsStateError,
    );
  });

  test('listGitSecrets filters non-Git secrets', () async {
    secrets.values = <WorkspaceSecretMetadata>[
      _secret('RUNNER_TOKEN', {WorkspaceSecretContext.runner}),
      _secret('GITHUB_TOKEN', {WorkspaceSecretContext.git}),
    ];

    final values = await coordinator.listGitSecrets(
      project: project,
      snapshot: snapshot,
    );

    expect(values.map((item) => item.name), ['GITHUB_TOKEN']);
  });
}

WorkspaceSecretMetadata _secret(
  String name,
  Set<WorkspaceSecretContext> contexts,
) {
  final now = DateTime.utc(2026, 9, 3);
  return WorkspaceSecretMetadata(
    name: name,
    contexts: contexts,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeRemote implements WorkspaceRemotePersistence {
  @override
  final WorkspaceIdentity identity = const WorkspaceIdentity(userId: 'user-1');

  WorkspaceRemoteDocument? document;
  WorkspaceSnapshot? lastSavedSnapshot;
  int created = 0;
  int saved = 0;
  String? lastExpectedRevision;

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async =>
      document;

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    created += 1;
    document = WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r1',
    );
    return document!;
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    saved += 1;
    lastExpectedRevision = expectedRevision;
    lastSavedSnapshot = snapshot;
    document = WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r8',
    );
    return document!;
  }

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() => throw UnimplementedError();

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) => throw UnimplementedError();
}

class _FakeSecrets implements WorkspaceSecretService {
  List<WorkspaceSecretMetadata> values = <WorkspaceSecretMetadata>[];
  int putCalls = 0;
  String? lastWorkspaceId;
  String? lastName;
  String? lastValue;
  Set<WorkspaceSecretContext>? lastContexts;

  @override
  Future<List<WorkspaceSecretMetadata>> listSecrets(String workspaceId) async =>
      List<WorkspaceSecretMetadata>.of(values);

  @override
  Future<WorkspaceSecretMetadata> putSecret({
    required String workspaceId,
    required String name,
    required String value,
    required Set<WorkspaceSecretContext> contexts,
  }) async {
    putCalls += 1;
    lastWorkspaceId = workspaceId;
    lastName = name;
    lastValue = value;
    lastContexts = contexts;
    final metadata = _secret(name, contexts);
    values = <WorkspaceSecretMetadata>[
      ...values.where((item) => item.name != name),
      metadata,
    ];
    return metadata;
  }

  @override
  Future<void> deleteSecret({
    required String workspaceId,
    required String name,
  }) => throw UnimplementedError();
}

class _FakeGit implements WorkspaceGitRemoteService {
  int checkCalls = 0;
  String repositoryUrl = 'https://github.com/team/app.git';
  String? lastWorkspaceId;
  String? lastSecretName;

  @override
  Future<WorkspaceGitRemoteCheckResult> checkRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) async {
    checkCalls += 1;
    lastWorkspaceId = workspaceId;
    lastSecretName = secretName;
    return WorkspaceGitRemoteCheckResult(
      repositoryUrl: repositoryUrl,
      branch: 'main',
      provider: 'github',
      reachable: true,
      branchFound: true,
      remoteHead: 'aaaaaaaaaaaaaaaa',
    );
  }

  @override
  Future<WorkspaceGitPullResult> pullRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();
}
