import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late HttpServer rawServer;
  late HttpClient client;
  late Uri baseUri;
  late _FakeCloneExecutor cloneExecutor;
  late _FakePushExecutor pushExecutor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-push-http-');
    final workspaceStore = FileWorkspaceStore(temp);
    final secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    cloneExecutor = _FakeCloneExecutor();
    pushExecutor = _FakePushExecutor();

    await workspaceStore.createWorkspace(
      userId: 'alice',
      project: _project(),
      snapshot: _snapshot(),
    );
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_http_push',
      contexts: const <String>{'git'},
    );

    final handler = WorkspaceStorageHttpServer(
      store: workspaceStore,
      secretStore: secretStore,
      gitPushService: WorkspaceGitPushService(
        workspaceStore: workspaceStore,
        secretStore: secretStore,
        cloneExecutor: cloneExecutor,
        pushExecutor: pushExecutor,
      ),
      authenticator: const StaticBearerWorkspaceAuthenticator(
        <String, String>{'alice-token': 'alice'},
      ),
    );
    rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rawServer.listen(handler.handle);
    client = HttpClient();
    baseUri = Uri.parse('http://127.0.0.1:${rawServer.port}/');
  });

  tearDown(() async {
    client.close(force: true);
    await rawServer.close(force: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('Git push route uses revision/head guards and never echoes secret', () async {
    final response = await _sendPush(
      client: client,
      baseUri: baseUri,
      expectedWorkspaceRevision: 'r1',
      expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
    );
    final text = await utf8.decoder.bind(response).join();
    final body = jsonDecode(text) as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.ok);
    expect(body['previousRemoteHead'], 'aaaaaaaaaaaaaaaa');
    expect(body['newRemoteHead'], 'bbbbbbbbbbbbbbbb');
    expect(body['committed'], isTrue);
    expect(text, isNot(contains('github_pat_http_push')));
    expect(cloneExecutor.secret, 'github_pat_http_push');
    expect(pushExecutor.secret, 'github_pat_http_push');
  });

  test('Git push route reports remote HEAD conflict as 409', () async {
    cloneExecutor.remoteHead = 'cccccccccccccccc';

    final response = await _sendPush(
      client: client,
      baseUri: baseUri,
      expectedWorkspaceRevision: 'r1',
      expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
    );
    final body = jsonDecode(
      await utf8.decoder.bind(response).join(),
    ) as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.conflict);
    expect(body['code'], 'git_remote_conflict');
    expect(body['expectedRemoteHead'], 'aaaaaaaaaaaaaaaa');
    expect(body['actualRemoteHead'], 'cccccccccccccccc');
    expect(pushExecutor.calls, 0);
  });
}

Future<HttpClientResponse> _sendPush({
  required HttpClient client,
  required Uri baseUri,
  required String expectedWorkspaceRevision,
  required String expectedRemoteHead,
}) async {
  final request = await client.postUrl(
    baseUri.resolve('workspaces/workspace-a/git/push'),
  );
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer alice-token',
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(<String, dynamic>{
    'expectedWorkspaceRevision': expectedWorkspaceRevision,
    'expectedRemoteHead': expectedRemoteHead,
    'commitMessage': 'feat: push from Workspace',
    'authorName': 'Alice Developer',
    'authorEmail': 'alice@example.com',
    'secretName': 'GITHUB_TOKEN',
  }));
  return request.close();
}

class _FakeCloneExecutor implements WorkspaceGitCloneExecutor {
  String remoteHead = 'aaaaaaaaaaaaaaaa';
  String? secret;

  @override
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  }) async {
    this.secret = secret;
    await targetDirectory.create(recursive: true);
    await _write(
      targetDirectory,
      'pubspec.yaml',
      'name: remote_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    await _write(targetDirectory, 'lib/main.dart', 'void main() {}\n');
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
    return const WorkspaceGitPushCommandResult(
      exitCode: 0,
      stderr: '',
      committed: true,
      newHead: 'bbbbbbbbbbbbbbbb',
    );
  }
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final path = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$path');
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
      'formatVersion': 2,
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
          'content': 'void main() => print("from cloud");\n',
        },
        <String, Object?>{
          'id': 'file-pubspec',
          'path': 'pubspec.yaml',
          'type': 'file',
          'content': 'name: cloud_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
        },
      ],
      'baseEntries': <Object>[],
      'openFiles': <Object>['lib/main.dart'],
      'activePath': 'lib/main.dart',
      'nextId': 4,
      'savedAt': '2026-09-03T00:00:00.000Z',
      'expandedDirectoryIds': <Object>['dir-lib'],
      'editorStates': <String, Object?>{},
    };
