import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/screens/concept_mode_screen.dart';

void main() {
  testWidgets('concept mode opens the direct Git import dialog', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: ConceptModeScreen()),
    );

    final gitEntry = find.byKey(
      const ValueKey('concept-open-git-project'),
    );
    expect(gitEntry, findsOneWidget);

    await tester.tap(gitEntry);
    await tester.pumpAndSettle();

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
