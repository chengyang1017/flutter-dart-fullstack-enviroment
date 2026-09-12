import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late FileWorkspaceStore workspaceStore;
  late FileWorkspaceSecretStore secretStore;
  late _FakeCloneExecutor cloneExecutor;
  late _FakePushExecutor pushExecutor;
  late WorkspaceGitPushService pushService;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-push-test-');
    workspaceStore = FileWorkspaceStore(temp);
    secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    cloneExecutor = _FakeCloneExecutor();
    pushExecutor = _FakePushExecutor();
    pushService = WorkspaceGitPushService(
      workspaceStore: workspaceStore,
      secretStore: secretStore,
      cloneExecutor: cloneExecutor,
      pushExecutor: pushExecutor,
    );

    await workspaceStore.createWorkspace(
      userId: 'alice',
      project: _project(),
      snapshot: _snapshot(),
    );
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_push_only',
      contexts: const <String>{'git'},
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('push updates only the bound Flutter project after both guards match', () async {
    cloneExecutor.remoteHead = 'aaaaaaaaaaaaaaaa';
    cloneExecutor.populate = (root) async {
      await _write(
        root,
        'apps/mobile/pubspec.yaml',
        'name: old_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(
        root,
        'apps/mobile/lib/main.dart',
        'void main() => print("old");\n',
      );
      await _write(root, 'apps/mobile/lib/deleted.dart', 'class Deleted {}\n');
      await _write(root, 'apps/mobile/android/keep.txt', 'platform file\n');
      await _writeBytes(root, 'apps/mobile/assets/logo.png', <int>[1, 2, 3]);

      await _write(
        root,
        'apps/admin/pubspec.yaml',
        'name: admin_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(
        root,
        'apps/admin/lib/main.dart',
        'void main() => print("admin untouched");\n',
      );
      await _write(root, 'tools/release.txt', 'keep monorepo tooling\n');
    };
    pushExecutor.inspect = (root) async {
      expect(
        await _read(root, 'apps/mobile/lib/main.dart'),
        'void main() => print("new");\n',
      );
      expect(
        await _read(root, 'apps/mobile/lib/new_file.dart'),
        'class NewFile {}\n',
      );
      expect(await _exists(root, 'apps/mobile/lib/deleted.dart'), isFalse);
      expect(
        await _read(root, 'apps/mobile/android/keep.txt'),
        'platform file\n',
      );
      expect(
        await _readBytes(root, 'apps/mobile/assets/logo.png'),
        <int>[137, 80, 78, 71, 0, 1, 2, 3],
      );
      expect(
        await _read(root, 'apps/admin/lib/main.dart'),
        'void main() => print("admin untouched");\n',
      );
      expect(await _read(root, 'tools/release.txt'), 'keep monorepo tooling\n');
    };

    final result = await pushService.push(
      userId: 'alice',
      workspaceId: 'workspace-a',
      expectedWorkspaceRevision: 'r1',
      expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
      commitMessage: 'feat: sync workspace',
      authorName: 'Alice Developer',
      authorEmail: 'alice@example.com',
      secretName: 'GITHUB_TOKEN',
    );

    expect(cloneExecutor.secret, 'github_pat_push_only');
    expect(cloneExecutor.username, 'x-access-token');
    expect(pushExecutor.secret, 'github_pat_push_only');
    expect(pushExecutor.username, 'x-access-token');
    expect(pushExecutor.commitMessage, 'feat: sync workspace');
    expect(pushExecutor.authorName, 'Alice Developer');
    expect(pushExecutor.authorEmail, 'alice@example.com');
    expect(result.previousRemoteHead, 'aaaaaaaaaaaaaaaa');
    expect(result.newRemoteHead, 'bbbbbbbbbbbbbbbb');
    expect(result.committed, isTrue);
  });

  test('push refuses when remote HEAD changed after the last pull', () async {
    cloneExecutor.remoteHead = 'cccccccccccccccc';
    cloneExecutor.populate = _populateFlutterRoot;

    await expectLater(
      pushService.push(
        userId: 'alice',
        workspaceId: 'workspace-a',
        expectedWorkspaceRevision: 'r1',
        expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
        commitMessage: 'feat: should not push',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
        secretName: 'GITHUB_TOKEN',
      ),
      throwsA(
        isA<WorkspaceGitHeadMismatch>()
            .having(
              (error) => error.expectedRemoteHead,
              'expectedRemoteHead',
              'aaaaaaaaaaaaaaaa',
            )
            .having(
              (error) => error.actualRemoteHead,
              'actualRemoteHead',
              'cccccccccccccccc',
            ),
      ),
    );

    expect(pushExecutor.calls, 0);
  });

  test('push refuses stale Cloud Workspace revision before cloning', () async {
    await expectLater(
      pushService.push(
        userId: 'alice',
        workspaceId: 'workspace-a',
        expectedWorkspaceRevision: 'r0',
        expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
        commitMessage: 'feat: stale cloud source',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
      ),
      throwsA(isA<WorkspaceRevisionMismatch>()),
    );

    expect(cloneExecutor.calls, 0);
    expect(pushExecutor.calls, 0);
  });
}

class _FakeCloneExecutor implements WorkspaceGitCloneExecutor {
  int calls = 0;
  String remoteHead = 'aaaaaaaaaaaaaaaa';
  String? secret;
  String? username;
  Future<void> Function(Directory root)? populate;

  @override
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  }) async {
    calls += 1;
    this.username = username;
    this.secret = secret;
    await targetDirectory.create(recursive: true);
    await (populate ?? _populateFlutterRoot)(targetDirectory);
    return WorkspaceGitCloneResult(
      exitCode: 0,
      stderr: '',
      remoteHead: remoteHead,
    );
  }
}

class _FakePushExecutor implements WorkspaceGitPushCommandExecutor {
  int calls = 0;
  String? secret;
  String? username;
  String? commitMessage;
  String? authorName;
  String? authorEmail;
  Future<void> Function(Directory root)? inspect;

  @override
  Future<WorkspaceGitPushCommandResult> commitAndPush({
    required Directory checkoutDirectory,
    required String branch,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? username,
    String? secret,
  }) async {
    calls += 1;
    this.secret = secret;
    this.username = username;
    this.commitMessage = commitMessage;
    this.authorName = authorName;
    this.authorEmail = authorEmail;
    await inspect?.call(checkoutDirectory);
    return const WorkspaceGitPushCommandResult(
      exitCode: 0,
      stderr: '',
      committed: true,
      newHead: 'bbbbbbbbbbbbbbbb',
    );
  }
}

Future<void> _populateFlutterRoot(Directory root) async {
  await _write(
    root,
    'apps/mobile/pubspec.yaml',
    'name: old_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
  );
  await _write(root, 'apps/mobile/lib/main.dart', 'void main() {}\n');
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<void> _writeBytes(
  Directory root,
  String relativePath,
  List<int> bytes,
) async {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$path');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

Future<String> _read(Directory root, String relativePath) {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  return File('${root.path}${Platform.pathSeparator}$path').readAsString();
}

Future<List<int>> _readBytes(Directory root, String relativePath) async {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  return File('${root.path}${Platform.pathSeparator}$path').readAsBytes();
}

Future<bool> _exists(Directory root, String relativePath) {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  return File('${root.path}${Platform.pathSeparator}$path').exists();
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
        'projectPath': 'apps/mobile',
        'provider': 'github',
      },
    };

Map<String, dynamic> _snapshot() => <String, dynamic>{
      'formatVersion': 3,
      'entries': <Object>[
        <String, Object?>{
          'id': 'dir-lib',
          'path': 'lib',
          'type': 'directory',
          'content': '',
        },
        <String, Object?>{
          'id': 'file-main',
          'path': 'lib/main.dart',
          'type': 'file',
          'content': 'void main() => print("new");\n',
          'encoding': 'utf8',
        },
        <String, Object?>{
          'id': 'file-new',
          'path': 'lib/new_file.dart',
          'type': 'file',
          'content': 'class NewFile {}\n',
          'encoding': 'utf8',
        },
        <String, Object?>{
          'id': 'file-logo',
          'path': 'assets/logo.png',
          'type': 'file',
          'content': base64Encode(<int>[137, 80, 78, 71, 0, 1, 2, 3]),
          'encoding': 'base64',
        },
        <String, Object?>{
          'id': 'file-pubspec',
          'path': 'pubspec.yaml',
          'type': 'file',
          'content': 'name: new_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
          'encoding': 'utf8',
        },
      ],
      'baseEntries': <Object>[],
      'openFiles': <Object>['lib/main.dart'],
      'activePath': 'lib/main.dart',
      'nextId': 6,
      'savedAt': '2026-09-03T00:00:00.000Z',
      'expandedDirectoryIds': <Object>['dir-lib'],
      'editorStates': <String, Object?>{},
    };
