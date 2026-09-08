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

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-git-pull-http-');
    final workspaceStore = FileWorkspaceStore(temp);
    final secretStore = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
    );
    cloneExecutor = _FakeCloneExecutor();

    await workspaceStore.createWorkspace(
      userId: 'alice',
      project: _project(),
      snapshot: _snapshot(),
    );
    await secretStore.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_pull_only',
      contexts: const <String>{'git'},
    );

    final handler = WorkspaceStorageHttpServer(
      store: workspaceStore,
      secretStore: secretStore,
      gitPullService: WorkspaceGitPullService(
        workspaceStore: workspaceStore,
        secretStore: secretStore,
        executor: cloneExecutor,
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

  test('Git pull returns portable source without echoing vault secret', () async {
    cloneExecutor.populate = (root) async {
      await _write(
        root,
        'pubspec.yaml',
        'name: pulled_app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await _write(root, 'lib/main.dart', 'void main() {}\n');
      await _write(root, 'README.md', '# Remote\n');
    };

    final result = await _postPull(
      client: client,
      baseUri: baseUri,
      body: <String, dynamic>{'secretName': 'GITHUB_TOKEN'},
    );

    expect(result.response.statusCode, HttpStatus.ok);
    expect(result.body['projectName'], 'pulled_app');
    expect(result.body['remoteHead'], 'fedcba9876543210');
    expect(
      (result.body['files'] as Map)['lib/main.dart'],
      'void main() {}\n',
    );
    expect(result.text, isNot(contains('github_pat_pull_only')));
    expect(cloneExecutor.secret, 'github_pat_pull_only');
    expect(cloneExecutor.username, 'x-access-token');
  });

  test('Git pull returns structured Flutter candidates for a monorepo', () async {
    cloneExecutor.populate = (root) async {
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
    };

    final result = await _postPull(
      client: client,
      baseUri: baseUri,
      body: const <String, dynamic>{},
    );

    expect(result.response.statusCode, HttpStatus.conflict);
    expect(result.body['code'], 'git_flutter_project_selection_required');
    final candidates = result.body['candidates'] as List<dynamic>;
    expect(candidates, hasLength(2));
    expect(candidates.first, <String, Object?>{
      'projectName': 'customer_app',
      'projectPath': 'apps/customer',
    });
    expect(candidates.last, <String, Object?>{
      'projectName': 'driver_app',
      'projectPath': 'apps/driver',
    });
  });
}

Future<_HttpResult> _postPull({
  required HttpClient client,
  required Uri baseUri,
  required Map<String, dynamic> body,
}) async {
  final request = await client.postUrl(
    baseUri.resolve('workspaces/workspace-a/git/pull'),
  );
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer alice-token',
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return _HttpResult(
    response: response,
    text: text,
    body: jsonDecode(text) as Map<String, dynamic>,
  );
}

class _HttpResult {
  const _HttpResult({
    required this.response,
    required this.text,
    required this.body,
  });

  final HttpClientResponse response;
  final String text;
  final Map<String, dynamic> body;
}

class _FakeCloneExecutor implements WorkspaceGitCloneExecutor {
  Future<void> Function(Directory root)? populate;
  String? secret;
  String? username;

  @override
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  }) async {
    this.secret = secret;
    this.username = username;
    await targetDirectory.create(recursive: true);
    await populate?.call(targetDirectory);
    return const WorkspaceGitCloneResult(
      exitCode: 0,
      stderr: '',
      remoteHead: 'fedcba9876543210',
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
