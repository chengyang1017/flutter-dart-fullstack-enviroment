import 'dart:async';
import 'dart:convert';

import '../models/workspace_project.dart';
import '../models/workspace_remote_models.dart';
import '../models/workspace_snapshot.dart';
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
  Future<void> _remoteTail = Future<void>.value();

  @override
  late final WorkspaceProjectCatalogStore catalogStore;

  @override
  late final WorkspaceSnapshotStore snapshotStore;

  /// Replaces the browser cache with the current remote catalog and snapshots.
  /// This makes the cloud copy the source of truth on every app start.
  Future<void> hydrateFromRemote() async {
    final cachedProjects = _cache.catalogStore.loadProjects();
    final preferredActive = _cache.catalogStore.loadActiveProjectId();
    final catalog = await _remote.loadCatalog();

    final hydratedProjects = <WorkspaceProject>[];
    final remoteIds = <String>{};
    _revisions.clear();

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
      await _cache.snapshotStore.save(
        document.project.storageKey,
        document.snapshot,
      );
    }

    for (final cached in cachedProjects) {
      if (_isLocalOnlyProject(cached) || remoteIds.contains(cached.id)) {
        continue;
      }
      await _cache.snapshotStore.delete(cached.storageKey);
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
      WorkspaceRemoteDocument document;
      final knownRevision = _revisions[project.id];

      if (knownRevision == null) {
        final existing = await _remote.loadWorkspace(project.id);
        if (existing == null) {
          document = await _remote.createWorkspace(
            project: project,
            snapshot: snapshot,
          );
        } else {
          document = await _saveWithConflictRefresh(
            project: project,
            snapshot: snapshot,
            expectedRevision: existing.revision,
          );
        }
      } else {
        document = await _saveWithConflictRefresh(
          project: project,
          snapshot: snapshot,
          expectedRevision: knownRevision,
        );
      }

      _revisions[project.id] = document.revision;
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
