import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late FileWorkspaceStore workspaceStore;
  late FileWorkspaceSecretStore secretStore;
  late _FakeCloneExecutor executor;
  late WorkspaceGitPullService pullService;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-pull-test-');
    workspaceStore = FileWorkspaceStore(temp);
    secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    executor = _FakeCloneExecutor();
    pullService = WorkspaceGitPullService(
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

  test('pull shallow-clones one Flutter root with a git-scoped vault secret', () async {
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_runtime_only',
      contexts: const <String>{'git'},
    );
    executor.populate = (root) async {
      await _write(
        root,
        'apps/mobile/pubspec.yaml',
        'name: pulled_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(
        root,
        'apps/mobile/lib/main.dart',
        'void main() {}\n',
      );
      await _write(root, 'apps/mobile/README.md', '# Pulled\n');
      await _write(root, 'apps/mobile/android/local.properties', 'ignored=true\n');
      await _write(root, 'tools/readme.txt', 'outside selected Flutter root\n');
    };

    final result = await pullService.pull(
      userId: 'alice',
      workspaceId: 'workspace-a',
      secretName: 'GITHUB_TOKEN',
    );

    expect(executor.repositoryUrl, 'https://github.com/team/private-app.git');
    expect(executor.branch, 'main');
    expect(executor.username, 'x-access-token');
    expect(executor.secret, 'github_pat_runtime_only');
    expect(result.projectName, 'pulled_app');
    expect(result.projectPath, 'apps/mobile');
    expect(result.toJson()['projectPath'], 'apps/mobile');
    expect(result.remoteHead, '0123456789abcdef');
    expect(result.files['lib/main.dart'], 'void main() {}\n');
    expect(result.files['README.md'], '# Pulled\n');
    expect(result.files, isNot(contains('android/local.properties')));
    expect(result.files, isNot(contains('tools/readme.txt')));
  });

  test('pull returns named candidates instead of guessing in a multi-app repo',
      () async {
    executor.populate = (root) async {
      await _write(
        root,
        'apps/customer/pubspec.yaml',
        'name: customer_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(root, 'apps/customer/lib/main.dart', 'void main() {}\n');
      await _write(
        root,
        'apps/driver/pubspec.yaml',
        'name: driver_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(root, 'apps/driver/lib/main.dart', 'void main() {}\n');
      await _write(root, 'apps/api/package.json', '{}\n');
    };

    try {
      await pullService.pull(
        userId: 'alice',
        workspaceId: 'workspace-a',
      );
      fail('Expected WorkspaceGitProjectSelectionRequired.');
    } on WorkspaceGitProjectSelectionRequired catch (error) {
      expect(error.candidates, hasLength(2));
      expect(error.candidates.first.projectName, 'customer_app');
      expect(error.candidates.first.projectPath, 'apps/customer');
      expect(error.candidates.last.projectName, 'driver_app');
      expect(error.candidates.last.projectPath, 'apps/driver');
    }
  });

  test('pull preserves binary portable assets with the binary envelope', () async {
    final logoBytes = <int>[137, 80, 78, 71, 0, 1, 2, 3, 255];
    executor.populate = (root) async {
      await _write(
        root,
        'pubspec.yaml',
        'name: binary_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(root, 'lib/main.dart', 'void main() {}\n');
      final asset = File(
        '${root.path}${Platform.pathSeparator}assets${Platform.pathSeparator}logo.png',
      );
      await asset.parent.create(recursive: true);
      await asset.writeAsBytes(logoBytes);
    };

    final result = await pullService.pull(
      userId: 'alice',
      workspaceId: 'workspace-a',
    );

    expect(result.projectPath, isNull);
    final payload = result.files['assets/logo.png'];
    expect(payload, isNotNull);
    expect(payload, startsWith(WorkspaceGitPullService.binaryFilePrefix));
    expect(
      base64Decode(
        payload!.substring(WorkspaceGitPullService.binaryFilePrefix.length),
      ),
      orderedEquals(logoBytes),
    );
  });
}

class _FakeCloneExecutor implements WorkspaceGitCloneExecutor {
  Future<void> Function(Directory root)? populate;
  String? repositoryUrl;
  String? branch;
  String? username;
  String? secret;

  @override
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  }) async {
    this.repositoryUrl = repositoryUrl;
    this.branch = branch;
    this.username = username;
    this.secret = secret;
    await targetDirectory.create(recursive: true);
    await populate?.call(targetDirectory);
    return const WorkspaceGitCloneResult(
      exitCode: 0,
      stderr: '',
      remoteHead: '0123456789abcdef',
    );
  }
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final platformPath = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$platformPath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
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
      'formatVersion': 3,
      'entries': <Object>[],
      'baseEntries': <Object>[],
      'openFiles': <Object>[],
      'activePath': '',
      'nextId': 1,
      'savedAt': '2026-09-03T00:00:00.000Z',
      'expandedDirectoryIds': <Object>[],
      'editorStates': <String, Object?>{},
    };
