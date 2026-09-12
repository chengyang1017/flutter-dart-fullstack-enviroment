import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_git_remote_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Git remote client sends only a vault secret reference', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'repositoryUrl': 'https://github.com/team/private-app.git',
          'branch': 'main',
          'provider': 'github',
          'reachable': true,
          'branchFound': true,
          'remoteHead': 'abc123',
        }),
        200,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    final result = await service.checkRemote(
      workspaceId: 'workspace-a',
      secretName: 'GITHUB_TOKEN',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/api/workspaces/workspace-a/git/check');
    expect(captured.headers['authorization'], 'Bearer workspace-token');
    expect(body, <String, dynamic>{'secretName': 'GITHUB_TOKEN'});
    expect(captured.body, isNot(contains('github_pat_')));
    expect(result.reachable, isTrue);
    expect(result.remoteHead, 'abc123');
  });
}
