import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late HttpServer rawServer;
  late HttpClient client;
  late Uri baseUri;
  late _FakeGitExecutor executor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-http-test-');
    final workspaceStore = FileWorkspaceStore(temp);
    final secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    executor = _FakeGitExecutor();

    await workspaceStore.createWorkspace(
      userId: 'alice',
      project: _project(),
      snapshot: _snapshot(),
    );
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_not_for_response',
      contexts: const <String>{'git'},
    );

    final handler = WorkspaceStorageHttpServer(
      store: workspaceStore,
      secretStore: secretStore,
      gitRemoteChecker: WorkspaceGitRemoteChecker(
        workspaceStore: workspaceStore,
        secretStore: secretStore,
        executor: executor,
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

  test('Git check accepts a secret reference and never echoes its value', () async {
    executor.next = const WorkspaceGitCommandResult(
      exitCode: 0,
      stdout: 'abc123\trefs/heads/main\n',
      stderr: '',
    );

    final request = await client.postUrl(
      baseUri.resolve('workspaces/workspace-a/git/check'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer alice-token',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{
      'secretName': 'GITHUB_TOKEN',
    }));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final body = jsonDecode(text) as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.ok);
    expect(body['reachable'], isTrue);
    expect(body['branchFound'], isTrue);
    expect(body['remoteHead'], 'abc123');
    expect(text, isNot(contains('github_pat_not_for_response')));
    expect(executor.secret, 'github_pat_not_for_response');
  });
}

class _FakeGitExecutor implements WorkspaceGitCommandExecutor {
  WorkspaceGitCommandResult next = const WorkspaceGitCommandResult(
    exitCode: 0,
    stdout: '',
    stderr: '',
  );
  String? secret;

  @override
  Future<WorkspaceGitCommandResult> lsRemote({
    required String repositoryUrl,
    required String branch,
    String? username,
    String? secret,
  }) async {
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
