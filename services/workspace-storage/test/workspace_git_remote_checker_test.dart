import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late FileWorkspaceStore workspaceStore;
  late FileWorkspaceSecretStore secretStore;
  late _FakeGitExecutor executor;
  late WorkspaceGitRemoteChecker checker;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-test-');
    workspaceStore = FileWorkspaceStore(temp);
    secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    executor = _FakeGitExecutor();
    checker = WorkspaceGitRemoteChecker(
      workspaceStore: workspaceStore,
      secretStore: secretStore,
      executor: executor,
    );

    await workspaceStore.createWorkspace(
      userId: 'alice',
      project: _project(),
      snapshot: _snapshot(),
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('private Git remote check resolves vault secret only for git context', () async {
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_runtime_only',
      contexts: const <String>{'git'},
    );
    executor.next = const WorkspaceGitCommandResult(
      exitCode: 0,
      stdout: '0123456789abcdef\trefs/heads/main\n',
      stderr: '',
    );

    final result = await checker.check(
      userId: 'alice',
      workspaceId: 'workspace-a',
      secretName: 'GITHUB_TOKEN',
    );

    expect(executor.repositoryUrl, 'https://github.com/team/private-app.git');
    expect(executor.branch, 'main');
    expect(executor.username, 'x-access-token');
    expect(executor.secret, 'github_pat_runtime_only');
    expect(result.branchFound, isTrue);
    expect(result.remoteHead, '0123456789abcdef');
  });

  test('Git remote check cannot use a runner-only secret', () async {
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'RUNNER_KEY',
      value: 'not-for-git',
      contexts: const <String>{'runner'},
    );

    await expectLater(
      checker.check(
        userId: 'alice',
        workspaceId: 'workspace-a',
        secretName: 'RUNNER_KEY',
      ),
      throwsStateError,
    );
    expect(executor.calls, 0);
  });

  test('public Git remote check does not resolve or inject a secret', () async {
    executor.next = const WorkspaceGitCommandResult(
      exitCode: 0,
      stdout: '',
      stderr: '',
    );

    final result = await checker.check(
      userId: 'alice',
      workspaceId: 'workspace-a',
    );

    expect(executor.secret, isNull);
    expect(executor.username, isNull);
    expect(result.branchFound, isFalse);
  });
}

class _FakeGitExecutor implements WorkspaceGitCommandExecutor {
  WorkspaceGitCommandResult next = const WorkspaceGitCommandResult(
    exitCode: 0,
    stdout: '',
    stderr: '',
  );
  int calls = 0;
  String? repositoryUrl;
  String? branch;
  String? username;
  String? secret;

  @override
  Future<WorkspaceGitCommandResult> lsRemote({
    required String repositoryUrl,
    required String branch,
    String? username,
    String? secret,
  }) async {
    calls += 1;
    this.repositoryUrl = repositoryUrl;
    this.branch = branch;
    this.username = username;
    this.secret = secret;
    return next;
  }
}

Map<String, dynamic> _project() => <String, dynamic>{
      'id': 'workspace-a',
      'name': 'Workspace A',
      'storageKey': 'workspace:workspace-a',
      'kind': 'practice',
      'lifecycle': 'saved',
      'createdAt': '2026-09-03T00:00:00.000Z',
      'updatedAt': '2026-09-03T00:00:00.000Z',
      'gitRemote': <String, dynamic>{
        'repositoryUrl': 'https://github.com/team/private-app.git',
        'remoteName': 'origin',
        'branch': 'main',
        'provider': 'github',
      },
    };

Map<String, dynamic> _snapshot() => <String, dynamic>{
      'formatVersion': 2,
      'entries': <Object>[],
      'baseEntries': <Object>[],
      'openFiles': <Object>[],
      'activePath': '',
      'nextId': 1,
      'savedAt': '2026-09-03T00:00:00.000Z',
      'expandedDirectoryIds': <Object>[],
      'editorStates': <String, Object?>{},
    };
