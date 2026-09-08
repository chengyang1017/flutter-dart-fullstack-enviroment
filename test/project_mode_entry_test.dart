import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/project_mode/screens/project_mode_screen.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  testWidgets('project mode hides legacy default workspace and shows empty launcher',
      (tester) async {
    final library = WorkspaceProjectLibrary(
      catalogStore: _MemoryCatalogStore(),
      snapshotStore: _MemorySnapshotStore(),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectModeScreen(projectLibrary: library)),
    );

    expect(find.byKey(const ValueKey('project-mode-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-mode-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-mode-create')), findsOneWidget);
    expect(find.text('Flutter Practice'), findsNothing);
  });

  testWidgets('project mode lists real Flutter projects under account namespace',
      (tester) async {
    final now = DateTime.utc(2026, 9, 8);
    final catalog = _MemoryCatalogStore(
      projects: <WorkspaceProject>[
        WorkspaceProject(
          id: WorkspaceProjectLibrary.defaultProjectId,
          name: 'Flutter Practice',
          storageKey: WorkspaceProjectLibrary.defaultStorageKey,
          kind: WorkspaceProjectKind.practice,
          createdAt: now,
          updatedAt: now,
        ),
        WorkspaceProject(
          id: 'glyphora-mobile',
          name: 'Glyphora Mobile',
          slug: 'glyphora-mobile',
          storageKey: 'workspace:glyphora-mobile',
          kind: WorkspaceProjectKind.generatedFlutter,
          createdAt: now,
          updatedAt: now,
          flutterPlatforms: const <String>{'android', 'web'},
        ),
      ],
      activeProjectId: WorkspaceProjectLibrary.defaultProjectId,
    );
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: _MemorySnapshotStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectModeScreen(
          projectLibrary: library,
          identity: const WorkspaceIdentity(
            userId: 'usr-123',
            username: 'chengyang1017',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('project-mode-project-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-mode-project-glyphora-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-mode-account-namespace')),
      findsOneWidget,
    );
    expect(find.text('Glyphora Mobile'), findsOneWidget);
    expect(find.text('chengyang1017 / glyphora-mobile'), findsOneWidget);
    expect(find.text('Flutter Practice'), findsNothing);
  });
}

class _MemoryCatalogStore implements WorkspaceProjectCatalogStore {
  _MemoryCatalogStore({
    List<WorkspaceProject>? projects,
    this.activeProjectId,
  }) : projects = List<WorkspaceProject>.of(projects ?? const []);

  List<WorkspaceProject> projects;
  String? activeProjectId;

  @override
  List<WorkspaceProject> loadProjects() => List<WorkspaceProject>.of(projects);

  @override
  String? loadActiveProjectId() => activeProjectId;

  @override
  Future<void> saveProjects(List<WorkspaceProject> projects) async {
    this.projects = List<WorkspaceProject>.of(projects);
  }

  @override
  Future<void> saveActiveProjectId(String projectId) async {
    activeProjectId = projectId;
  }
}

class _MemorySnapshotStore implements WorkspaceSnapshotStore {
  final Map<String, WorkspaceSnapshot> snapshots = <String, WorkspaceSnapshot>{};

  @override
  WorkspaceSnapshot? load(String key) => snapshots[key];

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    snapshots[key] = snapshot;
  }

  @override
  Future<void> delete(String key) async {
    snapshots.remove(key);
  }
}
