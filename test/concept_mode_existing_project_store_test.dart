import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/models/concept_project_context.dart';
import 'package:flutter_ui_playground/features/concept/screens/concept_mode_screen.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/keyed_workspace_snapshot_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  testWidgets('existing project store wins over detached projection snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final stored = _snapshot(extraPath: 'lib/from_store.dart');
    final detached = _snapshot(extraPath: 'lib/from_projection.dart');
    final memory = _MemorySnapshotStore(<String, WorkspaceSnapshot>{
      'workspace:glyphora': stored,
    });
    final keyed = KeyedWorkspaceSnapshotStore(
      delegate: memory,
      storageKey: 'workspace:glyphora',
    );
    final projection = ConceptProjectProjection(
      context: const ConceptProjectContext(
        repositoryName: 'chengyang1017/glyphora',
        projectName: 'glyphora_mobile',
        projectRoot: 'apps/mobile-flutter',
      ),
      snapshot: detached,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ConceptModeScreen(
          projection: projection,
          workspaceStore: keyed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('concept-lib-entry-lib/from_store.dart')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('concept-lib-entry-lib/from_projection.dart'),
      ),
      findsNothing,
    );
    expect(
      find.text(
        'chengyang1017/glyphora / apps/mobile-flutter · 应用 + 后端',
      ),
      findsOneWidget,
    );
  });
}

WorkspaceSnapshot _snapshot({required String extraPath}) {
  final entries = <WorkspaceEntry>[
    const WorkspaceEntry(
      id: 'lib',
      path: 'lib',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'main',
      path: 'lib/main.dart',
      type: WorkspaceEntryType.file,
      content: 'void main() {}',
    ),
    WorkspaceEntry(
      id: 'extra',
      path: extraPath,
      type: WorkspaceEntryType.file,
      content: 'class Extra {}',
    ),
    const WorkspaceEntry(
      id: 'pubspec',
      path: 'pubspec.yaml',
      type: WorkspaceEntryType.file,
      content: '''name: glyphora_mobile\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n''',
    ),
  ];

  return WorkspaceSnapshot(
    entries: entries,
    baseEntries: entries,
    openFiles: const <String>['lib/main.dart'],
    activePath: 'lib/main.dart',
    nextId: 10,
    savedAt: DateTime.utc(2026, 9, 8),
  );
}

class _MemorySnapshotStore implements WorkspaceSnapshotStore {
  _MemorySnapshotStore(this.values);

  final Map<String, WorkspaceSnapshot> values;

  @override
  WorkspaceSnapshot? load(String key) => values[key];

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    values[key] = snapshot;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
