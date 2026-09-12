import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote.dart';
import 'package:flutter_ui_playground/features/workspace/widgets/workspace_git_remote_dialog.dart';

void main() {
  testWidgets('Git remote dialog rejects credentials embedded in repository URL', (
    tester,
  ) async {
    WorkspaceGitRemoteDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<WorkspaceGitRemoteDialogResult>(
                  context: context,
                  builder: (_) => const WorkspaceGitRemoteDialog(),
                );
              },
              child: const Text('Git'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Git'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-git-repository-url')),
      'https://secret@github.com/team/app.git',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-git-save')));
    await tester.pump();

    expect(find.byKey(const ValueKey('workspace-git-error')), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('workspace-git-repository-url')),
      'https://github.com/team/app.git',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-git-branch')),
      'develop',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-git-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.unbind, isFalse);
    expect(result!.remote?.repositoryUrl, 'https://github.com/team/app.git');
    expect(result!.remote?.branch, 'develop');
    expect(result!.remote?.provider, WorkspaceGitProvider.github);
  });

  testWidgets('existing Git binding can be unbound', (tester) async {
    WorkspaceGitRemoteDialogResult? result;
    final remote = WorkspaceGitRemote(
      repositoryUrl: 'https://github.com/team/app.git',
      branch: 'main',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<WorkspaceGitRemoteDialogResult>(
                  context: context,
                  builder: (_) => WorkspaceGitRemoteDialog(
                    initialRemote: remote,
                  ),
                );
              },
              child: const Text('Git'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Git'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-git-unbind')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.unbind, isTrue);
    expect(result!.remote, isNull);
  });
}
