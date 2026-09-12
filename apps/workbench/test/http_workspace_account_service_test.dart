import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_account_service.dart';

void main() {
  test('Workspace account identity is resolved from authenticated /me', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://workspace.example/api/me');
      expect(request.headers['authorization'], 'Bearer dev-token');
      return http.Response(
        jsonEncode(<String, String>{
          'userId': 'usr-123',
          'username': 'chengyang1017',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final service = HttpWorkspaceAccountService(
      baseUri: Uri.parse('https://workspace.example/api/'),
      accessToken: 'dev-token',
      client: client,
    );

    final identity = await service.currentIdentity();
    expect(identity.userId, 'usr-123');
    expect(identity.username, 'chengyang1017');
    expect(identity.accountNamespace, 'chengyang1017');
  });

  test('Workspace account endpoint rejects an invalid bearer session', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, String>{'error': 'Authentication required.'}),
        401,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final service = HttpWorkspaceAccountService(
      baseUri: Uri.parse('https://workspace.example/'),
      accessToken: 'expired-token',
      client: client,
    );

    expect(
      service.currentIdentity,
      throwsA(
        isA<WorkspaceAccountRequestException>()
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
  });
}
