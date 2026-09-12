import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_secret.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_secret_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('putSecret sends value once but only returns metadata', () async {
    late http.Request captured;
    late String capturedBody;
    final client = MockClient((request) async {
      captured = request;
      capturedBody = request.body;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'name': 'GITHUB_TOKEN',
          'contexts': <String>['git'],
          'createdAt': '2026-09-03T00:00:00.000Z',
          'updatedAt': '2026-09-03T00:00:01.000Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final service = HttpWorkspaceSecretService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-access-token',
      client: client,
    );

    final metadata = await service.putSecret(
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'github_pat_transient_only',
      contexts: const <WorkspaceSecretContext>{WorkspaceSecretContext.git},
    );

    expect(captured.method, 'PUT');
    expect(
      captured.url.path,
      '/api/workspaces/workspace-a/secrets/GITHUB_TOKEN',
    );
    expect(captured.headers['authorization'], 'Bearer workspace-access-token');
    expect(capturedBody, contains('github_pat_transient_only'));
    expect(metadata.name, 'GITHUB_TOKEN');
    expect(metadata.contexts, contains(WorkspaceSecretContext.git));
  });

  test('listSecrets parses metadata without any value field', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'secrets': <Object>[
            <String, dynamic>{
              'name': 'API_KEY',
              'contexts': <String>['runner', 'deploy'],
              'createdAt': '2026-09-03T00:00:00.000Z',
              'updatedAt': '2026-09-03T00:00:01.000Z',
            },
          ],
        }),
        200,
      );
    });
    final service = HttpWorkspaceSecretService(
      baseUri: Uri.parse('https://workspace.example/'),
      accessToken: 'token',
      client: client,
    );

    final secrets = await service.listSecrets('workspace-a');
    expect(secrets, hasLength(1));
    expect(secrets.single.name, 'API_KEY');
    expect(
      secrets.single.contexts,
      containsAll(<WorkspaceSecretContext>{
        WorkspaceSecretContext.runner,
        WorkspaceSecretContext.deploy,
      }),
    );
  });

  test('deleteSecret accepts a no-content response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/workspaces/workspace-a/secrets/API_KEY');
      return http.Response('', 204);
    });
    final service = HttpWorkspaceSecretService(
      baseUri: Uri.parse('https://workspace.example/'),
      accessToken: 'token',
      client: client,
    );

    await service.deleteSecret(workspaceId: 'workspace-a', name: 'API_KEY');
  });

  test('secret value validation happens before any network request', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response('{}', 200);
    });
    final service = HttpWorkspaceSecretService(
      baseUri: Uri.parse('https://workspace.example/'),
      accessToken: 'token',
      client: client,
    );

    await expectLater(
      service.putSecret(
        workspaceId: 'workspace-a',
        name: 'EMPTY',
        value: '',
        contexts: const <WorkspaceSecretContext>{WorkspaceSecretContext.runner},
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });
}
