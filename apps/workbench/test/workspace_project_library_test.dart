import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/keyed_workspace_snapshot_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';
import 'package:flutter_ui_playground/features/workspace/widgets/workspace_project_bar.dart';

void main() {
  test('default workspace stays saved for migration stability', () {
    final library = WorkspaceProjectLibrary(
      catalogStore: _MemoryWorkspaceProjectCatalogStore(),
      snapshotStore: _MemoryWorkspaceSnapshotStore(),
    );

    expect(library.activeProject.lifecycle, WorkspaceLifecycle.saved);
  });

  test('local library reuses the legacy default-playground snapshot', () async {
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final legacy = PlaygroundController(workspaceStore: snapshots);
    legacy.workspace.updateFileContent(
      'lib/main.dart',
      '${PlaygroundController.exampleCode}\n// legacy browser workspace',
    );
    await legacy.flushWorkspacePersistence();
    legacy.dispose();

    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    expect(library.projects, hasLength(1));
    expect(library.activeProject.id, WorkspaceProjectLibrary.defaultProjectId);
    expect(
      library.activeProject.storageKey,
      PlaygroundController.workspaceStorageKey,
    );
    expect(library.activeProject.lifecycle, WorkspaceLifecycle.saved);

    final restored = PlaygroundController(
      workspaceStore: KeyedWorkspaceSnapshotStore(
        delegate: snapshots,
        storageKey: library.activeProject.storageKey,
      ),
    );
    expect(restored.restoredBrowserWorkspace, isTrue);
    expect(
      restored.workspace.entryAt('lib/main.dart')?.content,
      contains('// legacy browser workspace'),
    );
    await restored.flushWorkspacePersistence();
    restored.dispose();
  });

  test('legacy project metadata without lifecycle is kept as saved', () {
    final project = WorkspaceProject.fromJson(<String, dynamic>{
      'id': 'legacy',
      'name': 'Legacy Workspace',
      'storageKey': 'workspace:legacy',
      'kind': 'practice',
      'createdAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 9, 1).toIso8601String(),
    });

    expect(project.lifecycle, WorkspaceLifecycle.saved);
  });

  test('new practices are temporary and Keep persists saved lifecycle', () async {
    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    final practice = await library.createPractice('Quick BLoC Practice');
    expect(practice.lifecycle, WorkspaceLifecycle.temporary);

    await library.keepProject(practice.id);
    expect(
      library.projectById(practice.id)?.lifecycle,
      WorkspaceLifecycle.saved,
    );

    final reopened = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );
    expect(
      reopened.projectById(practice.id)?.lifecycle,
      WorkspaceLifecycle.saved,
    );
  });

  test('imported Flutter workspaces are saved by default', () async {
    final library = WorkspaceProjectLibrary(
      catalogStore: _MemoryWorkspaceProjectCatalogStore(),
      snapshotStore: _MemoryWorkspaceSnapshotStore(),
    );
    final seed = PlaygroundController();
    final snapshot = seed.workspace.createSnapshot();
    seed.dispose();

    final imported = await library.createImportedFlutter(
      name: 'Existing App',
      snapshot: snapshot,
    );

    expect(imported.lifecycle, WorkspaceLifecycle.saved);
  });

    test('generated Flutter workspaces persist selected platforms', () async {
    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final snapshots = _MemoryWorkspaceSnapshotStore();

    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    final seed = PlaygroundController();
    final snapshot = seed.workspace.createSnapshot();
    seed.dispose();

    final generated = await library.createGeneratedFlutter(
      name: 'my_app',
      snapshot: snapshot,
      platforms: const <String>{
        'android',
        'web',
        'windows',
      },
    );

    expect(
      generated.kind,
      WorkspaceProjectKind.generatedFlutter,
    );

    expect(
      generated.lifecycle,
      WorkspaceLifecycle.saved,
    );

    expect(
      generated.flutterPlatforms,
      unorderedEquals(
        const <String>[
          'android',
          'web',
          'windows',
        ],
      ),
    );

    expect(
      snapshots.load(generated.storageKey),
      isNotNull,
    );

    final reopened = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    final restored = reopened.projectById(
      generated.id,
    );

    expect(
      restored,
      isNotNull,
    );

    expect(
      restored!.kind,
      WorkspaceProjectKind.generatedFlutter,
    );

    expect(
      restored.flutterPlatforms,
      unorderedEquals(
        const <String>[
          'android',
          'web',
          'windows',
        ],
      ),
    );
  });

  test('projects persist and the last selected project is restored', () async {
    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final first = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    final riverpod = await first.createPractice('Riverpod Practice');
    expect(first.projects, hasLength(2));
    expect(first.activeProjectId, riverpod.id);

    await first.selectProject(WorkspaceProjectLibrary.defaultProjectId);

    final reopened = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );
    expect(reopened.projects, hasLength(2));
    expect(
      reopened.activeProjectId,
      WorkspaceProjectLibrary.defaultProjectId,
    );
    expect(reopened.projectById(riverpod.id)?.name, 'Riverpod Practice');
  });

  test('rename and delete remove only the selected project snapshot', () async {
    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );

    final project = await library.createPractice('Serverpod Test');
    final seed = PlaygroundController();
    final snapshot = seed.workspace.createSnapshot();
    seed.dispose();
    await snapshots.save(project.storageKey, snapshot);

    await library.renameProject(project.id, 'Serverpod Mini Test');
    expect(library.activeProject.name, 'Serverpod Mini Test');

    final nextActive = await library.deleteProject(project.id);
    expect(nextActive, WorkspaceProjectLibrary.defaultProjectId);
    expect(library.projects, hasLength(1));
    expect(snapshots.load(project.storageKey), isNull);
    expect(
      snapshots.deletedKeys,
      contains(project.storageKey),
    );
  });

  test('the final local workspace cannot be deleted', () async {
    final library = WorkspaceProjectLibrary(
      catalogStore: _MemoryWorkspaceProjectCatalogStore(),
      snapshotStore: _MemoryWorkspaceSnapshotStore(),
    );

    await expectLater(
      library.deleteProject(WorkspaceProjectLibrary.defaultProjectId),
      throwsStateError,
    );
  });

  test('disabled keyed store ignores late final saves', () async {
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final keyed = KeyedWorkspaceSnapshotStore(
      delegate: snapshots,
      storageKey: 'workspace:deleted',
    );
    final controller = PlaygroundController();
    final snapshot = controller.workspace.createSnapshot();
    controller.dispose();

    keyed.disableWrites();
    await keyed.save('default-playground', snapshot);

    expect(snapshots.saveCalls, 0);
    expect(snapshots.load('workspace:deleted'), isNull);
  });

  testWidgets('project bar fits a narrow phone width with Keep action', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 2);
    final projects = <WorkspaceProject>[
      WorkspaceProject(
        id: 'default-playground',
        name: 'Flutter Practice',
        storageKey: 'default-playground',
        kind: WorkspaceProjectKind.practice,
        lifecycle: WorkspaceLifecycle.temporary,
        createdAt: now,
        updatedAt: now,
      ),
      WorkspaceProject(
        id: 'second',
        name: 'A very long second Flutter practice workspace',
        storageKey: 'workspace:second',
        kind: WorkspaceProjectKind.practice,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: WorkspaceProjectBar(
                projects: projects,
                activeProject: projects.first,
                onSelect: (_) {},
                onCreate: () {},
                onKeep: () {},
                onRename: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('workspace-project-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-project-keep')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryWorkspaceProjectCatalogStore
    implements WorkspaceProjectCatalogStore {
  List<WorkspaceProject> _projects = <WorkspaceProject>[];
  String? _activeProjectId;

  @override
  List<WorkspaceProject> loadProjects() => _projects
      .map((project) => WorkspaceProject.fromJson(project.toJson()))
      .toList(growable: false);

  @override
  String? loadActiveProjectId() => _activeProjectId;

  @override
  Future<void> saveProjects(List<WorkspaceProject> projects) async {
    _projects = projects
        .map((project) => WorkspaceProject.fromJson(project.toJson()))
        .toList(growable: false);
  }

  @override
  Future<void> saveActiveProjectId(String projectId) async {
    _activeProjectId = projectId;
  }
}

class _MemoryWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
  final Map<String, WorkspaceSnapshot> _values = <String, WorkspaceSnapshot>{};
  final List<String> deletedKeys = <String>[];
  int saveCalls = 0;

  @override
  WorkspaceSnapshot? load(String key) {
    final value = _values[key];
    return value == null ? null : WorkspaceSnapshot.fromJson(value.toJson());
  }

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    saveCalls += 1;
    _values[key] = WorkspaceSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    _values.remove(key);
  }
}
