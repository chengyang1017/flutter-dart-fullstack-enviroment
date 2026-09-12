import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  test('project library can be created from one persistence boundary', () async {
    final persistence = _MemoryWorkspacePersistence();
    final library = WorkspaceProjectLibrary.fromPersistence(persistence);

    expect(library.activeProject.id, WorkspaceProjectLibrary.defaultProjectId);

    final created = await library.createPractice('Cloud-ready practice');

    expect(created.name, 'Cloud-ready practice');
    expect(created.lifecycle, WorkspaceLifecycle.temporary);
    expect(
      persistence.catalog.projects.map((project) => project.id),
      contains(created.id),
    );
    expect(persistence.catalog.activeProjectId, created.id);
  });
}

class _MemoryWorkspacePersistence implements WorkspacePersistence {
  final _MemoryWorkspaceProjectCatalogStore catalog =
      _MemoryWorkspaceProjectCatalogStore();
  final _MemoryWorkspaceSnapshotStore snapshots = _MemoryWorkspaceSnapshotStore();

  @override
  WorkspaceProjectCatalogStore get catalogStore => catalog;

  @override
  WorkspaceSnapshotStore get snapshotStore => snapshots;
}

class _MemoryWorkspaceProjectCatalogStore
    implements WorkspaceProjectCatalogStore {
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

class _MemoryWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
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
