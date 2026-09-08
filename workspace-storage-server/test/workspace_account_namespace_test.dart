import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  test('structured token config separates stable user id from username', () {
    final authenticator = StaticBearerWorkspaceAuthenticator.fromJson(
      '''{"token":{"userId":"usr_123","username":"Alice"}}''',
    );

    final principal = authenticator.principalForToken('token');
    expect(principal, isNotNull);
    expect(principal!.userId, 'usr_123');
    expect(principal.username, 'alice');
  });

  test('legacy token-to-user-id config remains compatible', () {
    final authenticator = StaticBearerWorkspaceAuthenticator.fromJson(
      '''{"legacy-token":"user-1"}''',
    );

    final principal = authenticator.principalForToken('legacy-token');
    expect(principal, isNotNull);
    expect(principal!.userId, 'user-1');
    expect(principal.username, 'user-1');
  });

  test('GET /me exposes the authenticated account namespace', () async {
    final temp = await Directory.systemTemp.createTemp('workspace-account-test-');
    final handler = WorkspaceStorageHttpServer(
      store: FileWorkspaceStore(temp),
      secretStore: FileWorkspaceSecretStore(
        temp,
        masterKey: List<int>.generate(32, (index) => index),
      ),
      authenticator: const StaticBearerWorkspaceAuthenticator.principals(
        <String, WorkspacePrincipal>{
          'alice-token': WorkspacePrincipal(
            userId: 'usr-alice-001',
            username: 'alice',
          ),
        },
      ),
    );
    final rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rawServer.listen(handler.handle);
    final client = HttpClient();
    final baseUri = Uri.parse('http://127.0.0.1:${rawServer.port}/');

    try {
      final unauthorized = await _request(client, baseUri, token: null);
      expect(unauthorized.statusCode, HttpStatus.unauthorized);

      final me = await _request(client, baseUri, token: 'alice-token');
      expect(me.statusCode, HttpStatus.ok);
      expect(me.json['userId'], 'usr-alice-001');
      expect(me.json['username'], 'alice');
    } finally {
      client.close(force: true);
      await rawServer.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });
}

Future<_TestResponse> _request(
  HttpClient client,
  Uri baseUri, {
  required String? token,
}) async {
  final request = await client.getUrl(baseUri.resolve('me'));
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
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
