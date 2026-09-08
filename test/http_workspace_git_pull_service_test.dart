import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_git_remote_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Git pull client sends only vault secret reference and builds snapshot', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'repositoryUrl': 'https://github.com/team/private-app.git',
          'branch': 'main',
          'provider': 'github',
          'projectName': 'pulled_app',
          'projectPath': 'apps/mobile',
          'remoteHead': 'abcdef123456',
          'files': <String, String>{
            'pubspec.yaml': 'name: pulled_app\n',
            'lib/main.dart': 'void main() {}\n',
            'lib/src/app.dart': 'class App {}\n',
          },
          'importedFileCount': 3,
          'ignoredFileCount': 12,
        }),
        200,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    final result = await service.pullRemote(
      workspaceId: 'workspace-a',
      secretName: 'GITHUB_TOKEN',
    );

    final requestBody = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/api/workspaces/workspace-a/git/pull');
    expect(captured.headers['authorization'], 'Bearer workspace-token');
    expect(requestBody, <String, dynamic>{'secretName': 'GITHUB_TOKEN'});
    expect(captured.body, isNot(contains('github_pat_')));
    expect(result.remoteHead, 'abcdef123456');
    expect(result.projectPath, 'apps/mobile');
    expect(result.ignoredFileCount, 12);

    final snapshot = result.toSnapshot(
      pulledAt: DateTime.utc(2026, 9, 3, 0, 30),
    );
    expect(snapshot.activePath, 'lib/main.dart');
    expect(snapshot.openFiles, ['lib/main.dart', 'pubspec.yaml']);
    expect(
      snapshot.entries
          .where((entry) => entry.isDirectory)
          .map((entry) => entry.path),
      containsAll(<String>['lib', 'lib/src']),
    );
    expect(
      snapshot.entries
          .singleWhere((entry) => entry.path == 'lib/src/app.dart')
          .content,
      'class App {}\n',
    );
    expect(snapshot.entries.length, snapshot.baseEntries.length);
  });

  test('Git pull response rejects unsafe file paths', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'repositoryUrl': 'https://github.com/team/private-app.git',
          'branch': 'main',
          'provider': 'github',
          'projectName': 'bad_app',
          'projectPath': 'apps/mobile',
          'remoteHead': 'abcdef123456',
          'files': <String, String>{
            'pubspec.yaml': 'name: bad_app\n',
            'lib/main.dart': 'void main() {}\n',
            '../outside.txt': 'nope',
          },
          'importedFileCount': 3,
          'ignoredFileCount': 0,
        }),
        200,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    await expectLater(
      service.pullRemote(workspaceId: 'workspace-a'),
      throwsFormatException,
    );
  });

  test('Git pull response rejects an unsafe detected project path', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'repositoryUrl': 'https://github.com/team/private-app.git',
          'branch': 'main',
          'provider': 'github',
          'projectName': 'bad_app',
          'projectPath': '../mobile',
          'remoteHead': 'abcdef123456',
          'files': <String, String>{
            'pubspec.yaml': 'name: bad_app\n',
            'lib/main.dart': 'void main() {}\n',
          },
          'importedFileCount': 2,
          'ignoredFileCount': 0,
        }),
        200,
      );
    });
    final service = HttpWorkspaceGitRemoteService(
      baseUri: Uri.parse('https://workspace.example/api'),
      accessToken: 'workspace-token',
      client: client,
    );

    await expectLater(
      service.pullRemote(workspaceId: 'workspace-a'),
      throwsFormatException,
    );
  });
}
