import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/screens/concept_mode_screen.dart';
import 'package:flutter_ui_playground/features/concept/widgets/concept_git_import_dialog.dart';

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

  testWidgets('direct Git import dialog exposes monorepo project path',
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
      find.byKey(const ValueKey('concept-git-project-path')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('concept-git-import-submit')),
      findsOneWidget,
    );
  });
}
