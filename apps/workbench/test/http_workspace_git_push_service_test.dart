import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_push.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_git_remote_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Git push client sends guards and only a vault secret reference', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'repositoryUrl': 'https://github.com/team/private-app.git',
          'branch': 'main',
          'provider': 'github',
          'previousRemoteHead': 'aaaaaaaaaaaaaaaa',
          'newRemoteHead': 'bbbbbbbbbbbbbbbb',
          'committed': true,
        }),
        200,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    final result = await service.pushRemote(
      workspaceId: 'workspace-a',
      expectedWorkspaceRevision: 'r7',
      expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
      commitMessage: 'feat: sync workspace',
      authorName: 'Alice Developer',
      authorEmail: 'alice@example.com',
      secretName: 'GITHUB_TOKEN',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/api/workspaces/workspace-a/git/push');
    expect(captured.headers['authorization'], 'Bearer workspace-token');
    expect(body['expectedWorkspaceRevision'], 'r7');
    expect(body['expectedRemoteHead'], 'aaaaaaaaaaaaaaaa');
    expect(body['commitMessage'], 'feat: sync workspace');
    expect(body['authorName'], 'Alice Developer');
    expect(body['authorEmail'], 'alice@example.com');
    expect(body['secretName'], 'GITHUB_TOKEN');
    expect(captured.body, isNot(contains('github_pat_')));
    expect(result.newRemoteHead, 'bbbbbbbbbbbbbbbb');
    expect(result.committed, isTrue);
  });

  test('Git push client exposes remote HEAD conflict', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'code': 'git_remote_conflict',
          'workspaceId': 'workspace-a',
          'expectedRemoteHead': 'aaaaaaaaaaaaaaaa',
          'actualRemoteHead': 'cccccccccccccccc',
        }),
        409,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    await expectLater(
      service.pushRemote(
        workspaceId: 'workspace-a',
        expectedWorkspaceRevision: 'r7',
        expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
        commitMessage: 'feat: sync workspace',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
      ),
      throwsA(
        isA<WorkspaceGitRemoteHeadConflict>()
            .having(
              (error) => error.expectedRemoteHead,
              'expectedRemoteHead',
              'aaaaaaaaaaaaaaaa',
            )
            .having(
              (error) => error.actualRemoteHead,
              'actualRemoteHead',
              'cccccccccccccccc',
            ),
      ),
    );
  });

  test('Git push client exposes stale Cloud Workspace revision', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'code': 'revision_conflict',
          'workspaceId': 'workspace-a',
          'expectedRevision': 'r7',
          'actualRevision': 'r8',
        }),
        409,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    await expectLater(
      service.pushRemote(
        workspaceId: 'workspace-a',
        expectedWorkspaceRevision: 'r7',
        expectedRemoteHead: 'aaaaaaaaaaaaaaaa',
        commitMessage: 'feat: sync workspace',
        authorName: 'Alice Developer',
        authorEmail: 'alice@example.com',
      ),
      throwsA(
        isA<WorkspaceRevisionConflict>()
            .having((error) => error.expectedRevision, 'expectedRevision', 'r7')
            .having((error) => error.actualRevision, 'actualRevision', 'r8'),
      ),
    );
  });
}
