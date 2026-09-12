import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('register parses server-issued account session', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/auth/register');
      expect(request.headers['authorization'], isNull);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['username'], 'alice');
      expect(body['email'], 'alice@example.com');
      expect(body['password'], 'password-one');
      return http.Response(
        jsonEncode(<String, Object?>{
          'accessToken': 'session-token',
          'user': <String, Object?>{
            'userId': 'usr-alice',
            'username': 'alice',
            'email': 'alice@example.com',
          },
        }),
        201,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final session = await HttpWorkspaceAuthService(
      baseUri: Uri.parse('https://workspace.example/'),
      client: client,
    ).register(
      username: 'alice',
      email: 'alice@example.com',
      password: 'password-one',
    );

    expect(session.accessToken, 'session-token');
    expect(session.identity.userId, 'usr-alice');
    expect(session.identity.accountNamespace, 'alice');
    expect(session.email, 'alice@example.com');
  });

  test('login exposes structured account errors', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/login');
      return http.Response(
        jsonEncode(<String, Object?>{
          'code': 'email_taken',
          'error': 'Email is already registered.',
        }),
        409,
      );
    });

    final service = HttpWorkspaceAuthService(
      baseUri: Uri.parse('https://workspace.example/'),
      client: client,
    );

    await expectLater(
      service.login(
        email: 'alice@example.com',
        password: 'password-one',
      ),
      throwsA(
        isA<WorkspaceAuthRequestException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'email_taken'),
      ),
    );
  });

  test('logout revokes the current bearer session', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/auth/logout');
      expect(request.headers['authorization'], 'Bearer session-token');
      return http.Response('', 204);
    });

    await HttpWorkspaceAuthService(
      baseUri: Uri.parse('https://workspace.example/'),
      client: client,
    ).logout('session-token');
  });
}
