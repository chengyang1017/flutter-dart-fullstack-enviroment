import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/widgets/concept_existing_project_dialog.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_git_remote.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';

void main() {
  testWidgets('Concept Mode can pick an existing Git-backed Flutter project', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 8);
    final projects = <WorkspaceProject>[
      WorkspaceProject(
        id: 'practice',
        name: 'Flutter Practice',
        storageKey: 'default-playground',
        kind: WorkspaceProjectKind.practice,
        createdAt: now,
        updatedAt: now,
      ),
      WorkspaceProject(
        id: 'glyphora',
        name: 'glyphora_mobile',
        storageKey: 'workspace:glyphora',
        kind: WorkspaceProjectKind.importedFlutter,
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 1)),
        gitRemote: WorkspaceGitRemote(
          repositoryUrl: 'https://github.com/chengyang1017/glyphora.git',
          branch: 'main',
          projectPath: 'apps/mobile-flutter',
        ),
      ),
    ];

    WorkspaceProject? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                selected = await showConceptExistingProjectDialog(
                  context,
                  projects: projects,
                );
              },
              child: const Text('Open projects'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open projects'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('concept-existing-project-dialog')),
      findsOneWidget,
    );
    expect(find.text('glyphora_mobile'), findsOneWidget);
    expect(
      find.text(
        'https://github.com/chengyang1017/glyphora.git · main · apps/mobile-flutter',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('glyphora_mobile'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('concept-existing-project-open')),
    );
    await tester.pumpAndSettle();

    expect(selected?.id, 'glyphora');
  });
}
