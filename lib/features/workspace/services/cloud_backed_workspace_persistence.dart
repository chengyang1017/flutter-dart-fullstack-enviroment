import 'dart:async';
import 'dart:convert';

import '../models/workspace_project.dart';
import '../models/workspace_remote_models.dart';
import '../models/workspace_snapshot.dart';
import '../models/workspace_snapshot_delta.dart';
import 'workspace_delta_remote_persistence.dart';
import 'workspace_persistence.dart';
import 'workspace_project_catalog_store.dart';
import 'workspace_remote_persistence.dart';
import 'workspace_snapshot_store.dart';

/// Cloud-first Workspace persistence.
///
/// The remote Workspace service is authoritative. The wrapped [cache] remains
/// useful for fast browser restores and offline inspection, but every normal
/// project mutation is mirrored to the remote service before the operation is
/// considered complete.
class CloudBackedWorkspacePersistence implements WorkspacePersistence {
  CloudBackedWorkspacePersistence({
    required WorkspacePersistence cache,
    required WorkspaceRemotePersistence remote,
  })  : _cache = cache,
        _remote = remote {
    catalogStore = _CloudCatalogStore(this);
    snapshotStore = _CloudSnapshotStore(this);
  }

  static const _legacyDefaultProjectId = 'default-playground';

  final WorkspacePersistence _cache;
  final WorkspaceRemotePersistence _remote;
  final Map<String, String> _revisions = <String, String>{};
  final Map<String, WorkspaceSnapshot> _syncedSnapshots =
      <String, WorkspaceSnapshot>{};
  Future<void> _remoteTail = Future<void>.value();

  @override
  late final WorkspaceProjectCatalogStore catalogStore;

  @override
  late final WorkspaceSnapshotStore snapshotStore;

  /// Hydrates remote projects while preserving projects that only exist in the
  /// browser cache. A project created while cloud was disabled must not be
  /// deleted just because it is absent from the remote catalog.
  Future<void> hydrateFromRemote() async {
    final cachedProjects = _cache.catalogStore.loadProjects();
    final preferredActive = _cache.catalogStore.loadActiveProjectId();
    final catalog = await _remote.loadCatalog();

    final hydratedProjects = <WorkspaceProject>[];
    final remoteIds = <String>{};
    _revisions.clear();
    _syncedSnapshots.clear();

    for (final catalogProject in catalog.projects) {
      if (_isLocalOnlyProject(catalogProject)) continue;

      final document = await _remote.loadWorkspace(catalogProject.id);
      if (document == null) {
        throw StateError(
          'Remote Workspace catalog references a missing Workspace: '
          '${catalogProject.id}',
        );
      }
      if (document.project.id != catalogProject.id) {
        throw StateError(
          'Remote Workspace id mismatch: requested ${catalogProject.id}, '
          'received ${document.project.id}',
        );
      }

      hydratedProjects.add(document.project);
      remoteIds.add(document.project.id);
      _revisions[document.project.id] = document.revision;
      _syncedSnapshots[document.project.id] = document.snapshot;
      await _cache.snapshotStore.save(
        document.project.storageKey,
        document.snapshot,
      );
    }

    for (final cached in cachedProjects) {
      if (_isLocalOnlyProject(cached) || remoteIds.contains(cached.id)) {
        continue;
      }

      // Keep local-only projects visible. The first later cloud save will use
      // _saveRemoteProject(), which creates the remote document when no remote
      // revision exists yet. This avoids destructive startup hydration and also
      // avoids forcing a potentially huge upload during login.
      final snapshot = _cache.snapshotStore.load(cached.storageKey);
      if (snapshot != null) {
        hydratedProjects.add(cached);
      }
    }

    await _cache.catalogStore.saveProjects(hydratedProjects);

    final activeId = hydratedProjects.any(
      (project) => project.id == preferredActive,
    )
        ? preferredActive!
        : hydratedProjects.isNotEmpty
            ? hydratedProjects.first.id
            : _legacyDefaultProjectId;
    await _cache.catalogStore.saveActiveProjectId(activeId);
  }

  WorkspaceProject? _projectForStorageKey(String storageKey) {
    for (final project in _cache.catalogStore.loadProjects()) {
      if (project.storageKey == storageKey) return project;
    }
    return null;
  }

  bool _isLocalOnlyProject(WorkspaceProject project) =>
      project.id == _legacyDefaultProjectId;

  bool _sameProject(WorkspaceProject? a, WorkspaceProject b) {
    if (a == null) return false;
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  Future<void> _saveRemoteProject(
    WorkspaceProject project,
    WorkspaceSnapshot snapshot,
  ) {
    if (_isLocalOnlyProject(project)) return Future<void>.value();

    return _serializeRemote(() async {
      var knownRevision = _revisions[project.id];
      var syncedSnapshot = _syncedSnapshots[project.id];

      if (knownRevision == null) {
        final existing = await _remote.loadWorkspace(project.id);
        if (existing == null) {
          final created = await _remote.createWorkspace(
            project: project,
            snapshot: snapshot,
          );
          _revisions[project.id] = created.revision;
          _syncedSnapshots[project.id] = snapshot;
          return;
        }

        knownRevision = existing.revision;
        syncedSnapshot = existing.snapshot;
        _revisions[project.id] = knownRevision;
        _syncedSnapshots[project.id] = syncedSnapshot;
      }

      final deltaRemote = _remote;
      if (syncedSnapshot == null ||
          deltaRemote is! WorkspaceDeltaRemotePersistence) {
        final saved = await _saveWithConflictRefresh(
          project: project,
          snapshot: snapshot,
          expectedRevision: knownRevision,
        );
        _revisions[project.id] = saved.revision;
        _syncedSnapshots[project.id] = snapshot;
        return;
      }

      final deltaPersistence =
          deltaRemote as WorkspaceDeltaRemotePersistence;
      final delta = WorkspaceSnapshotDelta.between(syncedSnapshot, snapshot);
      try {
        final result = await deltaPersistence.patchWorkspace(
          project: project,
          delta: delta,
          expectedRevision: knownRevision,
        );
        _revisions[project.id] = result.revision;
        _syncedSnapshots[project.id] = snapshot;
      } on WorkspaceRevisionConflict {
        final latest = await _remote.loadWorkspace(project.id);
        if (latest == null) {
          final created = await _remote.createWorkspace(
            project: project,
            snapshot: snapshot,
          );
          _revisions[project.id] = created.revision;
          _syncedSnapshots[project.id] = snapshot;
          return;
        }

        final retryDelta = WorkspaceSnapshotDelta.between(
          latest.snapshot,
          snapshot,
        );
        final result = await deltaPersistence.patchWorkspace(
          project: project,
          delta: retryDelta,
          expectedRevision: latest.revision,
        );
        _revisions[project.id] = result.revision;
        _syncedSnapshots[project.id] = snapshot;
      }
    });
  }

  Future<WorkspaceRemoteDocument> _saveWithConflictRefresh({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    try {
      return await _remote.saveWorkspace(
        project: project,
        snapshot: snapshot,
        expectedRevision: expectedRevision,
      );
    } on WorkspaceRevisionConflict {
      // Git operations use the same Workspace API and can legitimately advance
      // the revision outside this adapter. Refresh once, then retry the user's
      // current Workspace against the server's latest revision.
      final latest = await _remote.loadWorkspace(project.id);
      if (latest == null) {
        return _remote.createWorkspace(
          project: project,
          snapshot: snapshot,
        );
      }
      return _remote.saveWorkspace(
        project: project,
        snapshot: snapshot,
        expectedRevision: latest.revision,
      );
    }
  }

  Future<void> _deleteRemoteProject(WorkspaceProject project) {
    if (_isLocalOnlyProject(project)) return Future<void>.value();

    return _serializeRemote(() async {
      var revision = _revisions[project.id];
      if (revision == null) {
        final existing = await _remote.loadWorkspace(project.id);
        if (existing == null) return;
        revision = existing.revision;
      }

      try {
        await _remote.deleteWorkspace(
          workspaceId: project.id,
          expectedRevision: revision,
        );
      } on WorkspaceRevisionConflict {
        final latest = await _remote.loadWorkspace(project.id);
        if (latest != null) {
          await _remote.deleteWorkspace(
            workspaceId: project.id,
            expectedRevision: latest.revision,
          );
        }
      }
      _revisions.remove(project.id);
      _syncedSnapshots.remove(project.id);
    });
  }

  Future<T> _serializeRemote<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final previous = _remoteTail;

    _remoteTail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed request must not poison later cloud saves.
      }

      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();

    return completer.future;
  }
}

class _CloudSnapshotStore implements WorkspaceSnapshotStore {
  _CloudSnapshotStore(this.owner);

  final CloudBackedWorkspacePersistence owner;

  @override
  WorkspaceSnapshot? load(String key) => owner._cache.snapshotStore.load(key);

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    await owner._cache.snapshotStore.save(key, snapshot);

    final project = owner._projectForStorageKey(key);
    if (project != null) {
      await owner._saveRemoteProject(project, snapshot);
    }
  }

  @override
  Future<void> delete(String key) async {
    final project = owner._projectForStorageKey(key);
    if (project != null) {
      await owner._deleteRemoteProject(project);
    }
    await owner._cache.snapshotStore.delete(key);
  }
}

class _CloudCatalogStore implements WorkspaceProjectCatalogStore {
  _CloudCatalogStore(this.owner);

  final CloudBackedWorkspacePersistence owner;

  @override
  List<WorkspaceProject> loadProjects() =>
      owner._cache.catalogStore.loadProjects();

  @override
  String? loadActiveProjectId() =>
      owner._cache.catalogStore.loadActiveProjectId();

  @override
  Future<void> saveProjects(List<WorkspaceProject> projects) async {
    final previous = <String, WorkspaceProject>{
      for (final project in owner._cache.catalogStore.loadProjects())
        project.id: project,
    };

    await owner._cache.catalogStore.saveProjects(projects);

    for (final project in projects) {
      if (owner._isLocalOnlyProject(project) ||
          owner._sameProject(previous[project.id], project)) {
        continue;
      }

      final snapshot = owner._cache.snapshotStore.load(project.storageKey);
      if (snapshot != null) {
        await owner._saveRemoteProject(project, snapshot);
      }
    }
  }

  @override
  Future<void> saveActiveProjectId(String projectId) =>
      owner._cache.catalogStore.saveActiveProjectId(projectId);
}
