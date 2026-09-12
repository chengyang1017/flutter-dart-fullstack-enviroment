import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_pull.dart';

void main() {
  test('Git pull response restores binary payload as binary Workspace entry', () {
    final logoBytes = <int>[137, 80, 78, 71, 0, 1, 2, 3, 255];
    final result = WorkspaceGitPullResult.fromJson(<String, dynamic>{
      'repositoryUrl': 'https://github.com/team/app.git',
      'branch': 'main',
      'provider': 'github',
      'projectName': 'app',
      'remoteHead': '0123456789abcdef',
      'files': <String, String>{
        'pubspec.yaml': 'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
        'lib/main.dart': 'void main() {}\n',
        'assets/logo.png':
            '${WorkspaceEntry.runnerBinaryPrefix}${base64Encode(logoBytes)}',
      },
      'importedFileCount': 3,
      'ignoredFileCount': 0,
    });

    final snapshot = result.toSnapshot(
      pulledAt: DateTime.utc(2026, 9, 3),
    );
    final asset = snapshot.entries.singleWhere(
      (entry) => entry.path == 'assets/logo.png',
    );
    expect(asset.isBinary, isTrue);
    expect(asset.bytes, orderedEquals(logoBytes));
    expect(snapshot.activePath, 'lib/main.dart');
    expect(snapshot.baseEntries.length, snapshot.entries.length);
  });

  test('pubspec and main must remain text files', () {
    final binaryMain = '${WorkspaceEntry.runnerBinaryPrefix}${base64Encode([0, 1])}';
    expect(
      () => WorkspaceGitPullResult.fromJson(<String, dynamic>{
        'repositoryUrl': 'https://github.com/team/app.git',
        'branch': 'main',
        'provider': 'github',
        'projectName': 'app',
        'remoteHead': '0123456789abcdef',
        'files': <String, String>{
          'pubspec.yaml': 'name: app\nflutter:\n  uses-material-design: true\n',
          'lib/main.dart': binaryMain,
        },
        'importedFileCount': 2,
        'ignoredFileCount': 0,
      }),
      throwsFormatException,
    );
  });
}
