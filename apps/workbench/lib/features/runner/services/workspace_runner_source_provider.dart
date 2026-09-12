import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_capability.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/models/workspace_remote_models.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../../workspace/services/workspace_remote_persistence.dart';
import '../models/workspace_runner_source.dart';

abstract interface class WorkspaceRunnerSourceProvider {
  Future<WorkspaceRunnerSource> prepare();
}

class LocalWorkspaceRunnerSourceProvider
    implements WorkspaceRunnerSourceProvider {
  const LocalWorkspaceRunnerSourceProvider(
    this.workspace, {
    this.firebaseCapabilities = const <FirebaseCapability>{},
  });

  final WorkspaceController workspace;
  final Set<FirebaseCapability> firebaseCapabilities;

  @override
  Future<WorkspaceRunnerSource> prepare() async {
    return WorkspaceRunnerSource(
      files: _filesFromSnapshot(workspace.createSnapshot()),
      changes: workspace.changes,
      firebaseCapabilities: firebaseCapabilities,
    );
  }
}

class RemoteBackedWorkspaceRunnerSourceProvider
    implements WorkspaceRunnerSourceProvider {
  RemoteBackedWorkspaceRunnerSourceProvider({
    required this.workspace,
    required this.remote,
    required WorkspaceProject project,
    WorkspaceRemoteDocument? hydratedDocument,
  })  : _project = hydratedDocument?.project ?? project,
        _revision = hydratedDocument?.revision,
        _remoteExists = hydratedDocument != null;

  final WorkspaceController workspace;
  final WorkspaceRemotePersistence remote;

  WorkspaceProject _project;
  String? _revision;
  bool _remoteExists;

  WorkspaceProject get project => _project;
  String? get revision => _revision;

  @override
  Future<WorkspaceRunnerSource> prepare() async {
    final snapshot = workspace.createSnapshot();
    final changes = workspace.changes;
    final now = DateTime.now().toUtc();
    final projectToSave = _project.copyWith(updatedAt: now);

    WorkspaceRemoteDocument document;
    if (!_remoteExists || _revision == null) {
      final existing = await remote.loadWorkspace(_project.id);
      if (existing == null) {
        document = await remote.createWorkspace(
          project: projectToSave,
          snapshot: snapshot,
        );
      } else {
        _project = existing.project;
        _revision = existing.revision;
        document = await remote.saveWorkspace(
          project: _project.copyWith(updatedAt: now),
          snapshot: snapshot,
          expectedRevision: existing.revision,
        );
      }
    } else {
      document = await remote.saveWorkspace(
        project: projectToSave,
        snapshot: snapshot,
        expectedRevision: _revision!,
      );
    }

    _remoteExists = true;
    _project = document.project;
    _revision = document.revision;

    return WorkspaceRunnerSource(
      files: _filesFromSnapshot(document.snapshot),
      changes: changes,
      firebaseCapabilities: document.project.firebaseCapabilities,
      remoteRevision: document.revision,
    );
  }
}

Map<String, String> _filesFromSnapshot(WorkspaceSnapshot snapshot) =>
    <String, String>{
      for (final entry in snapshot.entries)
        if (entry.isFile) entry.path: entry.runnerContent,
    };
