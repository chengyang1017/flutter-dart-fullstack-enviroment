import '../controllers/workspace_controller.dart';
import '../models/workspace_git_pull.dart';
import '../services/workspace_git_remote_service.dart';
import '../services/workspace_project_library.dart';

class WorkspaceGitPullCoordinator {
  const WorkspaceGitPullCoordinator({
    required this.workspace,
    required this.projects,
    required this.git,
  });

  final WorkspaceController workspace;
  final WorkspaceProjectLibrary projects;
  final WorkspaceGitRemoteService git;

  Future<WorkspaceGitPullResult> pullCurrent({
    String? secretName,
    String? username,
    bool allowDirtyOverwrite = false,
  }) async {
    final project = projects.activeProject;
    final remote = project.gitRemote;
    if (remote == null) {
      throw StateError('Workspace has no Git remote binding.');
    }
    if (workspace.isDirty && !allowDirtyOverwrite) {
      throw StateError(
        'Workspace has local changes. Save, export, commit, or explicitly '
        'confirm overwrite before pulling from Git.',
      );
    }

    final original = workspace.createSnapshot();
    final result = await git.pullRemote(
      workspaceId: project.id,
      secretName: secretName,
      username: username,
    );
    if (result.repositoryUrl != remote.repositoryUrl ||
        result.branch != remote.branch) {
      throw StateError(
        'Git pull result does not match the Workspace remote binding.',
      );
    }

    final pulled = result.toSnapshot();
    try {
      workspace.restoreSnapshot(pulled);
      await projects.snapshotStore.save(project.storageKey, pulled);
      await projects.markGitPullSynced(
        project.id,
        remoteHead: result.remoteHead,
        projectPath: result.projectPath,
      );
      return result;
    } catch (_) {
      workspace.restoreSnapshot(original);
      await projects.snapshotStore.save(project.storageKey, original);
      rethrow;
    }
  }
}
