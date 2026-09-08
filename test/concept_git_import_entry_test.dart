import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/screens/concept_mode_screen.dart';
import 'package:flutter_ui_playground/features/concept/widgets/concept_git_import_dialog.dart';
import 'package:flutter_ui_playground/features/concept/widgets/concept_git_remote_project_picker_dialog.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_pull.dart';

void main() {
  testWidgets('concept mode exposes a direct Git project entry', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: ConceptModeScreen()),
    );

    expect(
      find.byKey(const ValueKey('concept-open-git-project')),
      findsOneWidget,
    );
  });

  testWidgets('direct Git import auto-detects project path instead of asking',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ConceptGitImportDialog())),
    );

    expect(
      find.byKey(const ValueKey('concept-git-import-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('concept-git-repository-url')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('concept-git-branch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('concept-git-project-path')),
      findsNothing,
    );
    expect(find.textContaining('不需要手写 monorepo 子项目路径'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('concept-git-import-submit')),
      findsOneWidget,
    );
  });

  testWidgets('remote monorepo picker shows package names and project paths',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConceptGitRemoteProjectPickerDialog(
            repositoryUrl: 'https://github.com/team/mono.git',
            candidates: <WorkspaceGitFlutterProjectCandidate>[
              WorkspaceGitFlutterProjectCandidate(
                projectName: 'customer_app',
                projectPath: 'apps/customer',
              ),
              WorkspaceGitFlutterProjectCandidate(
                projectName: 'driver_app',
                projectPath: 'apps/driver',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('concept-git-project-picker')),
      findsOneWidget,
    );
    expect(find.text('team/mono'), findsOneWidget);
    expect(find.text('customer_app'), findsOneWidget);
    expect(find.text('apps/customer'), findsOneWidget);
    expect(find.text('driver_app'), findsOneWidget);
    expect(find.text('apps/driver'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('concept-git-project-select')),
      findsOneWidget,
    );
  });
}
