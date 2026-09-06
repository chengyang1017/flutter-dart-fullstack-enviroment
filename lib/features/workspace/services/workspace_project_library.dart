import '../models/workspace_git_remote.dart';
import '../models/workspace_project.dart';
import '../models/workspace_snapshot.dart';
import 'workspace_persistence.dart';
import 'workspace_project_catalog_store.dart';
import 'workspace_snapshot_store.dart';

class WorkspaceProjectLibrary {
  WorkspaceProjectLibrary({
    required this.catalogStore,
    required this.snapshotStore,
  }) {
    _projects.addAll(catalogStore.loadProjects());

    if (_projects.isEmpty) {
      final now = DateTime.now().toUtc();
      _projects.add(
        WorkspaceProject(
          id: defaultProjectId,
          name: 'Flutter Practice',
          storageKey: defaultStorageKey,
          kind: WorkspaceProjectKind.practice,
          lifecycle: WorkspaceLifecycle.saved,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final storedActive = catalogStore.loadActiveProjectId();
    _activeProjectId = _projects.any((project) => project.id == storedActive)
        ? storedActive!
        : _projects.first.id;
  }

  WorkspaceProjectLibrary.fromPersistence(WorkspacePersistence persistence)
      : this(
          catalogStore: persistence.catalogStore,
          snapshotStore: persistence.snapshotStore,
        );

  static const defaultProjectId = 'default-playground';
  static const defaultStorageKey = 'default-playground';

  final WorkspaceProjectCatalogStore catalogStore;
  final WorkspaceSnapshotStore snapshotStore;

  final List<WorkspaceProject> _projects = <WorkspaceProject>[];
  late String _activeProjectId;
  int _idCounter = 0;

  List<WorkspaceProject> get projects {
    final copy = List<WorkspaceProject>.of(_projects)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(copy);
  }

  String get activeProjectId => _activeProjectId;

  WorkspaceProject get activeProject =>
      _projects.firstWhere((project) => project.id == _activeProjectId);

  WorkspaceProject? projectById(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  Future<WorkspaceProject> createPractice(String name) async {
    final cleanName = _validateName(name);
    final now = DateTime.now().toUtc();
    final id = _newProjectId(now);
    final project = WorkspaceProject(
      id: id,
      name: cleanName,
      storageKey: 'workspace:$id',
      kind: WorkspaceProjectKind.practice,
      lifecycle: WorkspaceLifecycle.temporary,
      createdAt: now,
      updatedAt: now,
    );

    _projects.add(project);
    _activeProjectId = project.id;
    await _persistCatalog();
    return project;
  }

  Future<WorkspaceProject> createImportedFlutter({
    required String name,
    required WorkspaceSnapshot snapshot,
  }) async {
    final cleanName = _validateName(name);
    final now = DateTime.now().toUtc();
    final id = _newProjectId(now);
    final project = WorkspaceProject(
      id: id,
      name: cleanName,
      storageKey: 'workspace:$id',
      kind: WorkspaceProjectKind.importedFlutter,
      lifecycle: WorkspaceLifecycle.saved,
      createdAt: now,
      updatedAt: now,
    );

    await snapshotStore.save(project.storageKey, snapshot);
    final previousActive = _activeProjectId;
    _projects.add(project);
    _activeProjectId = project.id;

    try {
      await _persistCatalog();
    } catch (_) {
      _projects.removeWhere((item) => item.id == project.id);
      _activeProjectId = previousActive;
      await snapshotStore.delete(project.storageKey);
      rethrow;
    }

    return project;
  }

  Future<void> selectProject(String id) async {
    final project = projectById(id);
    if (project == null) {
      throw ArgumentError('Workspace project does not exist: $id');
    }

    _activeProjectId = id;
    await catalogStore.saveActiveProjectId(id);
  }

  Future<void> renameProject(String id, String name) async {
    final index = _projectIndex(id);
    final now = DateTime.now().toUtc();
    _projects[index] = _projects[index].copyWith(
      name: _validateName(name),
      updatedAt: now,
    );
    await catalogStore.saveProjects(projects);
  }

  Future<void> keepProject(String id) async {
    final index = _projectIndex(id);
    if (_projects[index].lifecycle == WorkspaceLifecycle.saved) return;

    _projects[index] = _projects[index].copyWith(
      lifecycle: WorkspaceLifecycle.saved,
      updatedAt: DateTime.now().toUtc(),
    );
    await catalogStore.saveProjects(projects);
  }

  Future<void> bindGitRemote(String id, WorkspaceGitRemote remote) async {
    final index = _projectIndex(id);
    final existing = _projects[index].gitRemote;
    final targetChanged = existing != null &&
        (existing.repositoryUrl != remote.repositoryUrl ||
            existing.remoteName != remote.remoteName ||
            existing.branch != remote.branch ||
            existing.projectPath != remote.projectPath);
    final binding = targetChanged && remote.lastSyncedHead != null
        ? remote.copyWith(clearLastSyncedHead: true)
        : remote;

    _projects[index] = _projects[index].copyWith(
      gitRemote: binding,
      updatedAt: DateTime.now().toUtc(),
    );
    await catalogStore.saveProjects(projects);
  }

  Future<void> markGitSyncedHead(String id, String remoteHead) async {
    final index = _projectIndex(id);
    final remote = _projects[index].gitRemote;
    if (remote == null) {
      throw StateError('Workspace has no Git remote binding.');
    }
    _projects[index] = _projects[index].copyWith(
      gitRemote: remote.copyWith(lastSyncedHead: remoteHead),
      updatedAt: DateTime.now().toUtc(),
    );
    await catalogStore.saveProjects(projects);
  }

  Future<void> unbindGitRemote(String id) async {
    final index = _projectIndex(id);
    if (_projects[index].gitRemote == null) return;

    _projects[index] = _projects[index].copyWith(
      clearGitRemote: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await catalogStore.saveProjects(projects);
  }

  Future<void> touchProject(String id) async {
    final index = _projects.indexWhere((project) => project.id == id);
    if (index == -1) return;
    _projects[index] = _projects[index].copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    await catalogStore.saveProjects(projects);
  }

  Future<String?> deleteProject(String id) async {
    if (_projects.length <= 1) {
      throw StateError('At least one local Workspace must remain.');
    }

    final index = _projects.indexWhere((project) => project.id == id);
    if (index == -1) return null;
    final removed = _projects[index];

    await snapshotStore.delete(removed.storageKey);
    _projects.removeAt(index);

    String? nextActive;
    if (_activeProjectId == id) {
      _activeProjectId = projects.first.id;
      nextActive = _activeProjectId;
    }

    await _persistCatalog();
    return nextActive;
  }

  Future<void> _persistCatalog() async {
    await catalogStore.saveProjects(projects);
    await catalogStore.saveActiveProjectId(_activeProjectId);
  }

  int _projectIndex(String id) {
    final index = _projects.indexWhere((project) => project.id == id);
    if (index == -1) {
      throw ArgumentError('Workspace project does not exist: $id');
    }
    return index;
  }

  String _validateName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Workspace name cannot be empty.');
    }
    if (clean.length > 80) {
      throw ArgumentError('Workspace name must be 80 characters or fewer.');
    }
    return clean;
  }

  String _newProjectId(DateTime now) {
    _idCounter += 1;
    return 'local-${now.microsecondsSinceEpoch}-$_idCounter';
  }
}
