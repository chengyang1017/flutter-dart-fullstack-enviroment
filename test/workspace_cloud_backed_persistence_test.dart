import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/cloud_backed_workspace_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  test('cloud hydration replaces stale browser projects and snapshots', () async {
    final cache = _MemoryWorkspacePersistence();
    final stale = _project('stale-local', name: 'Stale local');
    cache.catalog.projects = <WorkspaceProject>[stale];
    cache.catalog.activeProjectId = stale.id;
    cache.snapshots.snapshots[stale.storageKey] = _snapshot('LOCAL');

    final cloudProject = _project('cloud-app', name: 'Cloud App');
    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{
      cloudProject.id: WorkspaceRemoteDocument(
        project: cloudProject,
        snapshot: _snapshot('CLOUD'),
        revision: 'r1',
      ),
    });
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );

    await persistence.hydrateFromRemote();

    expect(cache.catalog.projects.map((project) => project.id), ['cloud-app']);
    expect(cache.catalog.activeProjectId, 'cloud-app');
    expect(cache.snapshots.load(stale.storageKey), isNull);
    expect(
      cache.snapshots.load(cloudProject.storageKey)?.entries.single.content,
      'CLOUD',
    );
  });

  test('creating a Flutter project stores it in the cloud immediately', () async {
    final cache = _MemoryWorkspacePersistence();
    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{});
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );
    await persistence.hydrateFromRemote();
    final library = WorkspaceProjectLibrary.fromPersistence(persistence);

    final created = await library.createGeneratedFlutter(
      name: 'cloud_app',
      snapshot: _snapshot('CREATED'),
      platforms: const <String>{'android', 'web'},
    );

    expect(remote.documents[created.id], isNotNull);
    expect(remote.documents[created.id]?.project.name, 'cloud_app');
    expect(remote.documents[created.id]?.snapshot.entries.single.content, 'CREATED');
  });

  test('autosave metadata and delete stay cloud-backed', () async {
    final cache = _MemoryWorkspacePersistence();
    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{});
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );
    await persistence.hydrateFromRemote();
    final library = WorkspaceProjectLibrary.fromPersistence(persistence);

    final created = await library.createGeneratedFlutter(
      name: 'cloud_app',
      snapshot: _snapshot('V1'),
      platforms: const <String>{'android'},
    );

    await persistence.snapshotStore.save(
      created.storageKey,
      _snapshot('V2'),
    );
    await library.renameProject(created.id, 'renamed_cloud_app');

    expect(remote.documents[created.id]?.snapshot.entries.single.content, 'V2');
    expect(remote.documents[created.id]?.project.name, 'renamed_cloud_app');

    await library.deleteProject(created.id);
    expect(remote.documents.containsKey(created.id), isFalse);
  });
}

WorkspaceProject _project(String id, {required String name}) {
  final now = DateTime.utc(2026, 9, 8);
  return WorkspaceProject(
    id: id,
    name: name,
    storageKey: 'workspace:$id',
    kind: WorkspaceProjectKind.generatedFlutter,
    lifecycle: WorkspaceLifecycle.saved,
    createdAt: now,
    updatedAt: now,
  );
}

WorkspaceSnapshot _snapshot(String content) => WorkspaceSnapshot(
      entries: <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'file-1',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: content,
        ),
      ],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>['lib/main.dart'],
      activePath: 'lib/main.dart',
      nextId: 2,
      savedAt: DateTime.utc(2026, 9, 8),
    );

class _MemoryWorkspacePersistence implements WorkspacePersistence {
  final _MemoryCatalogStore catalog = _MemoryCatalogStore();
  final _MemorySnapshotStore snapshots = _MemorySnapshotStore();

  @override
  WorkspaceProjectCatalogStore get catalogStore => catalog;

  @override
  WorkspaceSnapshotStore get snapshotStore => snapshots;
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

class _FakeRemotePersistence implements WorkspaceRemotePersistence {
  _FakeRemotePersistence(this.documents);

  final Map<String, WorkspaceRemoteDocument> documents;
  int _revision = 10;

  @override
  WorkspaceIdentity get identity =>
      const WorkspaceIdentity(userId: 'cloud-test-user');

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() async => WorkspaceRemoteCatalog(
        projects: documents.values.map((document) => document.project).toList(),
        revision: 'catalog-${documents.length}',
      );

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async =>
      documents[workspaceId];

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    if (documents.containsKey(project.id)) {
      throw StateError('Workspace already exists: ${project.id}');
    }
    return _store(project, snapshot);
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    final current = documents[project.id];
    if (current == null) throw StateError('Workspace missing: ${project.id}');
    if (current.revision != expectedRevision) {
      throw WorkspaceRevisionConflict(
        workspaceId: project.id,
        expectedRevision: expectedRevision,
        actualRevision: current.revision,
      );
    }
    return _store(project, snapshot);
  }

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) async {
    final current = documents[workspaceId];
    if (current == null) {
      return loadCatalog();
    }
    if (current.revision != expectedRevision) {
      throw WorkspaceRevisionConflict(
        workspaceId: workspaceId,
        expectedRevision: expectedRevision,
        actualRevision: current.revision,
      );
    }
    documents.remove(workspaceId);
    return loadCatalog();
  }

  WorkspaceRemoteDocument _store(
    WorkspaceProject project,
    WorkspaceSnapshot snapshot,
  ) {
    _revision += 1;
    final document = WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r$_revision',
    );
    documents[project.id] = document;
    return document;
  }
}
