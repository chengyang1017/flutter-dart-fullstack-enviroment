import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/cloud_backed_workspace_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_pending_sync_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  test('replays pending local snapshot before remote hydration can overwrite it',
      () async {
    final project = _project('cloud-app');
    final cache = _MemoryWorkspacePersistence()
      ..catalog.projects = <WorkspaceProject>[project]
      ..catalog.activeProjectId = project.id;
    cache.snapshots.snapshots[project.storageKey] = _snapshot('LOCAL-NEW');
    await cache.snapshots.markPendingSync(project.storageKey);

    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{
      project.id: WorkspaceRemoteDocument(
        project: project,
        snapshot: _snapshot('REMOTE-OLD'),
        revision: 'r1',
      ),
    });
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );

    await persistence.hydrateFromRemote();

    expect(
      cache.snapshots.load(project.storageKey)?.entries.single.content,
      'LOCAL-NEW',
    );
    expect(remote.documents[project.id]?.snapshot.entries.single.content,
        'LOCAL-NEW');
    expect(cache.snapshots.isPendingSync(project.storageKey), isFalse);
  });

  test('failed recovery keeps local snapshot and pending marker for next boot',
      () async {
    final project = _project('cloud-app');
    final cache = _MemoryWorkspacePersistence()
      ..catalog.projects = <WorkspaceProject>[project]
      ..catalog.activeProjectId = project.id;
    cache.snapshots.snapshots[project.storageKey] = _snapshot('LOCAL-NEW');
    await cache.snapshots.markPendingSync(project.storageKey);

    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{
      project.id: WorkspaceRemoteDocument(
        project: project,
        snapshot: _snapshot('REMOTE-OLD'),
        revision: 'r1',
      ),
    })..failWrites = true;
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );

    await expectLater(persistence.hydrateFromRemote(), throwsStateError);

    expect(
      cache.snapshots.load(project.storageKey)?.entries.single.content,
      'LOCAL-NEW',
    );
    expect(cache.snapshots.isPendingSync(project.storageKey), isTrue);
    expect(remote.documents[project.id]?.snapshot.entries.single.content,
        'REMOTE-OLD');
  });

  test('pending local project missing remotely is created on next bootstrap',
      () async {
    final project = _project('new-cloud-app');
    final cache = _MemoryWorkspacePersistence()
      ..catalog.projects = <WorkspaceProject>[project]
      ..catalog.activeProjectId = project.id;
    cache.snapshots.snapshots[project.storageKey] = _snapshot('LOCAL-ONLY');
    await cache.snapshots.markPendingSync(project.storageKey);

    final remote = _FakeRemotePersistence(<String, WorkspaceRemoteDocument>{});
    final persistence = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );

    await persistence.hydrateFromRemote();

    expect(remote.documents[project.id], isNotNull);
    expect(remote.documents[project.id]?.snapshot.entries.single.content,
        'LOCAL-ONLY');
    expect(cache.snapshots.isPendingSync(project.storageKey), isFalse);
  });
}

WorkspaceProject _project(String id) {
  final now = DateTime.utc(2026, 9, 9);
  return WorkspaceProject(
    id: id,
    name: id,
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
      savedAt: DateTime.utc(2026, 9, 9),
    );

class _MemoryWorkspacePersistence implements WorkspacePersistence {
  final _MemoryCatalogStore catalog = _MemoryCatalogStore();
  final _MemoryPendingSnapshotStore snapshots = _MemoryPendingSnapshotStore();

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

class _MemoryPendingSnapshotStore
    implements WorkspaceSnapshotStore, WorkspacePendingSyncStore {
  final Map<String, WorkspaceSnapshot> snapshots = <String, WorkspaceSnapshot>{};
  final Set<String> pending = <String>{};

  @override
  WorkspaceSnapshot? load(String key) => snapshots[key];

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    snapshots[key] = snapshot;
  }

  @override
  Future<void> delete(String key) async {
    snapshots.remove(key);
    pending.remove(key);
  }

  @override
  bool isPendingSync(String key) => pending.contains(key);

  @override
  Future<void> markPendingSync(String key) async {
    pending.add(key);
  }

  @override
  Future<void> clearPendingSync(String key) async {
    pending.remove(key);
  }
}

class _FakeRemotePersistence implements WorkspaceRemotePersistence {
  _FakeRemotePersistence(this.documents);

  final Map<String, WorkspaceRemoteDocument> documents;
  bool failWrites = false;
  int _revision = 1;

  @override
  WorkspaceIdentity get identity =>
      const WorkspaceIdentity(userId: 'pending-sync-test-user');

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
    if (failWrites) throw StateError('simulated offline write');
    return _store(project, snapshot);
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    if (failWrites) throw StateError('simulated offline write');
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
