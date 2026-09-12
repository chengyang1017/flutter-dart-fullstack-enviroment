import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  test('register login me and logout use persistent account sessions', () async {
    final temp = await Directory.systemTemp.createTemp('workspace-auth-test-');
    final accounts = FileWorkspaceAccountStore(
      temp,
      passwordIterations: 100000,
    );
    final authenticator = CompositeWorkspaceAuthenticator(
      <WorkspaceAuthenticator>[
        const StaticBearerWorkspaceAuthenticator.principals(
          <String, WorkspacePrincipal>{
            'dev-token': WorkspacePrincipal(
              userId: 'user-1',
              username: 'chengyang1017',
            ),
          },
        ),
        accounts,
      ],
    );
    final workspaceHandler = WorkspaceStorageHttpServer(
      store: FileWorkspaceStore(temp),
      secretStore: FileWorkspaceSecretStore(
        temp,
        masterKey: List<int>.generate(32, (index) => index),
      ),
      authenticator: authenticator,
    );
    final handler = WorkspaceAuthHttpHandler(
      accounts: accounts,
      workspaceHandler: workspaceHandler,
    );
    final rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rawServer.listen(handler.handle);
    final client = HttpClient();
    final baseUri = Uri.parse('http://127.0.0.1:${rawServer.port}/');

    try {
      final registered = await _request(
        client,
        baseUri.resolve('auth/register'),
        method: 'POST',
        body: <String, Object?>{
          'username': 'Alice',
          'email': 'Alice@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(registered.statusCode, HttpStatus.created);
      final registerToken = registered.json['accessToken'];
      expect(registerToken, isA<String>());
      final user = Map<String, dynamic>.from(registered.json['user'] as Map);
      expect(user['username'], 'alice');
      expect(user['email'], 'alice@example.com');
      expect(user['userId'], startsWith('usr_'));

      final me = await _request(
        client,
        baseUri.resolve('me'),
        token: registerToken as String,
      );
      expect(me.statusCode, HttpStatus.ok);
      expect(me.json['userId'], user['userId']);
      expect(me.json['username'], 'alice');

      final wrongPassword = await _request(
        client,
        baseUri.resolve('auth/login'),
        method: 'POST',
        body: <String, Object?>{
          'email': 'alice@example.com',
          'password': 'definitely-wrong',
        },
      );
      expect(wrongPassword.statusCode, HttpStatus.unauthorized);

      final loggedIn = await _request(
        client,
        baseUri.resolve('auth/login'),
        method: 'POST',
        body: <String, Object?>{
          'email': 'ALICE@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(loggedIn.statusCode, HttpStatus.ok);
      final loginToken = loggedIn.json['accessToken'];
      expect(loginToken, isA<String>());
      expect(loginToken, isNot(registerToken));

      final logout = await _request(
        client,
        baseUri.resolve('auth/logout'),
        method: 'POST',
        token: loginToken as String,
      );
      expect(logout.statusCode, HttpStatus.noContent);

      final afterLogout = await _request(
        client,
        baseUri.resolve('me'),
        token: loginToken,
      );
      expect(afterLogout.statusCode, HttpStatus.unauthorized);

      final devMe = await _request(
        client,
        baseUri.resolve('me'),
        token: 'dev-token',
      );
      expect(devMe.statusCode, HttpStatus.ok);
      expect(devMe.json['userId'], 'user-1');
      expect(devMe.json['username'], 'chengyang1017');

      final accountFile = File('${temp.path}/auth/accounts.json');
      final stored = await accountFile.readAsString();
      expect(stored, isNot(contains('correct horse battery staple')));
      expect(stored, isNot(contains(registerToken)));
      expect(stored, isNot(contains(loginToken)));
      expect(stored, contains('passwordHash'));
      expect(stored, contains('tokenHash'));
    } finally {
      client.close(force: true);
      await rawServer.close(force: true);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('accounts are unique and different users can own the same project id',
      () async {
    final temp = await Directory.systemTemp.createTemp('workspace-users-test-');
    final accounts = FileWorkspaceAccountStore(
      temp,
      passwordIterations: 100000,
    );
    final workspaces = FileWorkspaceStore(temp);

    try {
      final alice = await accounts.register(
        username: 'alice',
        email: 'alice@example.com',
        password: 'password-one',
      );
      final bob = await accounts.register(
        username: 'bob',
        email: 'bob@example.com',
        password: 'password-two',
      );

      await expectLater(
        () => accounts.register(
          username: 'alice',
          email: 'other@example.com',
          password: 'password-three',
        ),
        throwsA(isA<WorkspaceAccountConflict>()),
      );

      Map<String, dynamic> project(String name) => <String, dynamic>{
            'id': 'my-app',
            'name': name,
            'storageKey': 'workspace:my-app',
            'kind': 'generatedFlutter',
            'lifecycle': 'saved',
            'createdAt': DateTime.utc(2026, 9, 8).toIso8601String(),
            'updatedAt': DateTime.utc(2026, 9, 8).toIso8601String(),
          };
      final snapshot = <String, dynamic>{
        'version': 3,
        'entries': <Object?>[],
        'baseEntries': <Object?>[],
        'openFiles': <Object?>[],
        'activePath': null,
        'nextId': 1,
        'savedAt': DateTime.utc(2026, 9, 8).toIso8601String(),
      };

      await workspaces.createWorkspace(
        userId: alice.principal.userId,
        project: project('Alice App'),
        snapshot: snapshot,
      );
      await workspaces.createWorkspace(
        userId: bob.principal.userId,
        project: project('Bob App'),
        snapshot: snapshot,
      );

      final aliceCatalog = await workspaces.loadCatalog(alice.principal.userId);
      final bobCatalog = await workspaces.loadCatalog(bob.principal.userId);
      expect(
        (aliceCatalog['projects'] as List).single['name'],
        'Alice App',
      );
      expect(
        (bobCatalog['projects'] as List).single['name'],
        'Bob App',
      );
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}

Future<_TestResponse> _request(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  String? token,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(method, uri);
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  final decoded = text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text);
  return _TestResponse(
    response.statusCode,
    decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{},
  );
}

class _TestResponse {
  const _TestResponse(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic> json;
}
