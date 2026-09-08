import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/screens/concept_mode_screen.dart';
import 'package:flutter_ui_playground/features/concept/services/concept_project_projection_service.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';

void main() {
  testWidgets(
    'projected monorepo opens as lib-only runnable Concept Mode',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const service = ConceptProjectProjectionService();
      final repository = _repositorySnapshot();
      final projection = service.project(
        repositorySnapshot: repository,
        repositoryName: 'chengyang1017/glyphora',
        candidate: service.detectFlutterProjects(repository).single,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConceptModeScreen(projection: projection),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('concept-source-project')),
        findsOneWidget,
      );
      expect(
        find.text(
          'chengyang1017/glyphora / apps/mobile-flutter · lib/ only',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-lib-entry-lib/main.dart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-lib-entry-lib/screens')),
        findsOneWidget,
      );
      expect(find.text('apps'), findsNothing);
      expect(find.text('api'), findsNothing);
      expect(find.text('mobile-rn'), findsNothing);
      expect(find.text('pubspec.yaml'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('concept-run-button')));
      await tester.pumpAndSettle();
      expect(find.text('Mock Flutter Runner · Running'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('concept-assets-entry')));
      await tester.pumpAndSettle();
      expect(find.text('1 个资源'), findsOneWidget);
      expect(find.text('pubspec 已声明 assets/'), findsOneWidget);
    },
  );
}

WorkspaceSnapshot _repositorySnapshot() {
  final entries = <WorkspaceEntry>[
    const WorkspaceEntry(
      id: 'apps',
      path: 'apps',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'api',
      path: 'apps/api',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'api-file',
      path: 'apps/api/index.ts',
      type: WorkspaceEntryType.file,
      content: 'export const api = true;',
    ),
    const WorkspaceEntry(
      id: 'rn',
      path: 'apps/mobile-rn',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'rn-file',
      path: 'apps/mobile-rn/package.json',
      type: WorkspaceEntryType.file,
      content: '{"name":"rn"}',
    ),
    const WorkspaceEntry(
      id: 'flutter',
      path: 'apps/mobile-flutter',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'flutter-lib',
      path: 'apps/mobile-flutter/lib',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'flutter-screens',
      path: 'apps/mobile-flutter/lib/screens',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'flutter-main',
      path: 'apps/mobile-flutter/lib/main.dart',
      type: WorkspaceEntryType.file,
      content: '''import 'package:flutter/material.dart';\nvoid main() => runApp(const MaterialApp(home: Text('Glyphora')));\n''',
    ),
    const WorkspaceEntry(
      id: 'flutter-home',
      path: 'apps/mobile-flutter/lib/screens/home.dart',
      type: WorkspaceEntryType.file,
      content: 'class Home {}',
    ),
    const WorkspaceEntry(
      id: 'flutter-pubspec',
      path: 'apps/mobile-flutter/pubspec.yaml',
      type: WorkspaceEntryType.file,
      content: '''name: glyphora_mobile\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n  assets:\n    - assets/\n''',
    ),
    const WorkspaceEntry(
      id: 'flutter-assets',
      path: 'apps/mobile-flutter/assets',
      type: WorkspaceEntryType.directory,
    ),
    WorkspaceEntry.binary(
      id: 'flutter-logo',
      path: 'apps/mobile-flutter/assets/logo.png',
      bytes: const <int>[137, 80, 78, 71],
    ),
  ];

  return WorkspaceSnapshot(
    entries: entries,
    baseEntries: entries,
    openFiles: const <String>[
      'apps/mobile-flutter/lib/main.dart',
      'apps/api/index.ts',
    ],
    activePath: 'apps/api/index.ts',
    nextId: 40,
    savedAt: DateTime.utc(2026, 9, 8),
  );
}
