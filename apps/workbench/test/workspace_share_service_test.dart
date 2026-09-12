import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_share_service.dart';

void main() {
  test('creates a fixed read-only share URL from server response', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'token': 'share-token-abcdefghijklmnopqrstuvwxyz',
          'workspaceId': 'workspace a',
          'revision': 'r7',
          'createdAt': '2026-09-09T11:30:00.000Z',
          'sharePath': '/shares/share-token-abcdefghijklmnopqrstuvwxyz',
        }),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final service = WorkspaceShareService(
      client: client,
      baseUri: Uri.parse('https://workspace.example.test/api-root'),
      accessToken: 'alice-token',
    );

    final share = await service.createShare('workspace a');

    expect(
      captured.url.toString(),
      'https://workspace.example.test/api-root/workspaces/workspace%20a/shares',
    );
    expect(captured.headers['authorization'], 'Bearer alice-token');
    expect(share.revision, 'r7');
    expect(
      share.url.toString(),
      'https://workspace.example.test/shares/'
      'share-token-abcdefghijklmnopqrstuvwxyz',
    );
  });

  test('surfaces server share creation errors', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{'error': 'Workspace not found.'}),
        404,
        headers: <String, String>{'content-type': 'application/json'},
      ),
    );

    final service = WorkspaceShareService(
      client: client,
      baseUri: Uri.parse('https://workspace.example.test/'),
      accessToken: 'alice-token',
    );

    await expectLater(
      service.createShare('missing'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Workspace not found.'),
        ),
      ),
    );
  });
}
