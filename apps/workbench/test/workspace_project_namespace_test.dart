import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  test('projects receive GitHub-style unique slugs inside one account', () async {
    final catalog = _MemoryCatalogStore();
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: _MemorySnapshotStore(),
    );

    final first = await library.createPractice('My App');
    final second = await library.createPractice('My App');

    expect(first.slug, 'my-app');
    expect(second.slug, 'my-app-2');
    expect(library.projectBySlug('my-app')?.id, first.id);
    expect(library.projectBySlug('MY APP')?.id, first.id);

    await library.renameProject(second.id, 'Clyven');
    final renamed = library.projectById(second.id)!;
    expect(renamed.slug, 'clyven');
    expect(library.projectBySlug('clyven')?.id, second.id);

    final persisted = catalog.projects.firstWhere((project) => project.id == second.id);
    expect(persisted.toJson()['slug'], 'clyven');
  });

  test('legacy project metadata derives a route slug without changing its id', () {
    final restored = WorkspaceProject.fromJson(<String, dynamic>{
      'id': 'stable-project-id',
      'name': '万文社 Demo',
      'storageKey': 'workspace:stable-project-id',
      'kind': 'generatedFlutter',
      'lifecycle': 'saved',
      'createdAt': '2026-09-08T00:00:00.000Z',
      'updatedAt': '2026-09-08T00:00:00.000Z',
    });

    expect(restored.id, 'stable-project-id');
    expect(restored.slug, '万文社-demo');
    expect(restored.toJson()['slug'], '万文社-demo');
  });

  test('legacy duplicate names are disambiguated in the project library', () {
    final now = DateTime.utc(2026, 9, 8);
    final catalog = _MemoryCatalogStore()
      ..projects = <WorkspaceProject>[
        WorkspaceProject(
          id: 'project-a',
          name: 'Demo',
          storageKey: 'workspace:project-a',
          kind: WorkspaceProjectKind.practice,
          createdAt: now,
          updatedAt: now,
        ),
        WorkspaceProject(
          id: 'project-b',
          name: 'Demo',
          storageKey: 'workspace:project-b',
          kind: WorkspaceProjectKind.practice,
          createdAt: now,
          updatedAt: now,
        ),
      ];

    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: _MemorySnapshotStore(),
    );

    expect(library.projectById('project-a')!.slug, 'demo');
    expect(library.projectById('project-b')!.slug, 'demo-2');
  });
}

class _MemoryCatalogStore implements WorkspaceProjectCatalogStore {
  List<WorkspaceProject> projects = <WorkspaceProject>[];
  String? activeProjectId;

  @override
  List<WorkspaceProject> loadProjects() => List<WorkspaceProject>.of(projects);

  @override
  String? loadActiveProjectId() => activeProjectId;

  @override
  Future<void> saveProjects(List<WorkspaceProject> value) async {
    projects = List<WorkspaceProject>.of(value);
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
