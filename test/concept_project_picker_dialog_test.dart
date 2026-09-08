import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/models/concept_project_context.dart';
import 'package:flutter_ui_playground/features/concept/widgets/concept_project_picker_dialog.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';

void main() {
  testWidgets('picker lets user choose one Flutter app from a monorepo', (
    tester,
  ) async {
    final snapshot = _twoFlutterApps();
    ConceptProjectProjection? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showConceptProjectPickerDialog(
                  context,
                  repositorySnapshot: snapshot,
                  repositoryName: 'team/monorepo',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('concept-project-picker')),
      findsOneWidget,
    );
    expect(find.text('first_app'), findsOneWidget);
    expect(find.text('second_app'), findsOneWidget);
    expect(find.text('apps/first'), findsOneWidget);
    expect(find.text('apps/second'), findsOneWidget);

    await tester.tap(find.text('second_app'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('concept-project-open')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.context.projectRoot, 'apps/second');
    expect(result!.snapshot.activePath, 'lib/main.dart');
    expect(
      result!.snapshot.entries.any((entry) => entry.path.startsWith('apps/')),
      isFalse,
    );
  });
}

WorkspaceSnapshot _twoFlutterApps() {
  final entries = <WorkspaceEntry>[
    const WorkspaceEntry(
      id: 'apps',
      path: 'apps',
      type: WorkspaceEntryType.directory,
    ),
    ..._flutterApp('first', 'first_app'),
    ..._flutterApp('second', 'second_app'),
  ];

  return WorkspaceSnapshot(
    entries: entries,
    baseEntries: entries,
    openFiles: const <String>[],
    activePath: '',
    nextId: 30,
    savedAt: DateTime.utc(2026, 9, 8),
  );
}

List<WorkspaceEntry> _flutterApp(String folder, String packageName) {
  final root = 'apps/$folder';
  return <WorkspaceEntry>[
    WorkspaceEntry(
      id: '$folder-root',
      path: root,
      type: WorkspaceEntryType.directory,
    ),
    WorkspaceEntry(
      id: '$folder-lib',
      path: '$root/lib',
      type: WorkspaceEntryType.directory,
    ),
    WorkspaceEntry(
      id: '$folder-main',
      path: '$root/lib/main.dart',
      type: WorkspaceEntryType.file,
      content: 'void main() {}',
    ),
    WorkspaceEntry(
      id: '$folder-pubspec',
      path: '$root/pubspec.yaml',
      type: WorkspaceEntryType.file,
      content: '''name: $packageName\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n''',
    ),
  ];
}
