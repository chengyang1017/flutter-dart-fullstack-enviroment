import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  test('legacy development identity can become a normal account in place', () async {
    final temp = await Directory.systemTemp.createTemp(
      'workspace-legacy-claim-test-',
    );
    final accounts = FileWorkspaceAccountStore(temp, passwordIterations: 100000);
    const legacy = StaticBearerWorkspaceAuthenticator.principals(
      <String, WorkspacePrincipal>{
        'legacy-token': WorkspacePrincipal(
          userId: 'user-1',
          username: 'chengyang1017',
        ),
      },
    );
    final store = FileWorkspaceStore(temp);
    await store.createWorkspace(
      userId: 'user-1',
      project: <String, dynamic>{
        'id': 'legacy-project',
        'name': 'Legacy Project',
      },
      snapshot: <String, dynamic>{'files': <Object?>[]},
    );

    final workspaceHandler = WorkspaceStorageHttpServer(
      store: store,
      secretStore: FileWorkspaceSecretStore(
        temp,
        masterKey: List<int>.generate(32, (index) => index),
      ),
      authenticator: CompositeWorkspaceAuthenticator(
        <WorkspaceAuthenticator>[legacy, accounts],
      ),
    );
    final handler = WorkspaceAuthHttpHandler(
      accounts: accounts,
      workspaceHandler: workspaceHandler,
      legacyAuthenticator: legacy,
    );
    final rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rawServer.listen(handler.handle);
    final client = HttpClient();
    final baseUri = Uri.parse('http://127.0.0.1:${rawServer.port}/');

    try {
      final ordinary = await _postJson(
        client,
        baseUri.resolve('auth/register'),
        body: <String, Object?>{
          'username': 'alice',
          'email': 'alice@example.com',
          'password': 'password-one',
        },
      );
      expect(ordinary.statusCode, HttpStatus.created);
      final ordinaryToken = ordinary.json['accessToken'] as String;

      final rejected = await _postJson(
        client,
        baseUri.resolve('auth/claim-existing'),
        token: ordinaryToken,
        body: <String, Object?>{
          'email': 'owner@example.com',
          'password': 'password-two',
        },
      );
      expect(rejected.statusCode, HttpStatus.unauthorized);

      final claimed = await _postJson(
        client,
        baseUri.resolve('auth/claim-existing'),
        token: 'legacy-token',
        body: <String, Object?>{
          'email': 'owner@example.com',
          'password': 'password-two',
        },
      );
      expect(claimed.statusCode, HttpStatus.created);
      final user = Map<String, dynamic>.from(claimed.json['user'] as Map);
      expect(user['userId'], 'user-1');
      expect(user['username'], 'chengyang1017');
      expect(user['email'], 'owner@example.com');
      final claimedToken = claimed.json['accessToken'] as String;

      final catalog = await _getJson(
        client,
        baseUri.resolve('workspaces'),
        token: claimedToken,
      );
      expect(catalog.statusCode, HttpStatus.ok);
      final projects = catalog.json['projects'] as List<dynamic>;
      expect(
        projects.any(
          (project) => project is Map && project['id'] == 'legacy-project',
        ),
        isTrue,
      );

      final login = await _postJson(
        client,
        baseUri.resolve('auth/login'),
        body: <String, Object?>{
          'email': 'owner@example.com',
          'password': 'password-two',
        },
      );
      expect(login.statusCode, HttpStatus.ok);
      final loginUser = Map<String, dynamic>.from(login.json['user'] as Map);
      expect(loginUser['userId'], 'user-1');
      expect(loginUser['username'], 'chengyang1017');

      final secondClaim = await _postJson(
        client,
        baseUri.resolve('auth/claim-existing'),
        token: 'legacy-token',
        body: <String, Object?>{
          'email': 'owner2@example.com',
          'password': 'password-three',
        },
      );
      expect(secondClaim.statusCode, HttpStatus.conflict);
      expect(secondClaim.json['code'], 'account_already_claimed');
    } finally {
      client.close(force: true);
      await rawServer.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });
}

Future<_TestResponse> _postJson(
  HttpClient client,
  Uri uri, {
  required Map<String, Object?> body,
  String? token,
}) async {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  request.write(jsonEncode(body));
  return _readResponse(await request.close());
}

Future<_TestResponse> _getJson(
  HttpClient client,
  Uri uri, {
  required String token,
}) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  return _readResponse(await request.close());
}

Future<_TestResponse> _readResponse(HttpClientResponse response) async {
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
