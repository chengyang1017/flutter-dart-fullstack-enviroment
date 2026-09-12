import '../models/workspace_git_remote_check.dart';
import '../models/workspace_project.dart';
import '../models/workspace_secret.dart';
import '../models/workspace_snapshot.dart';
import 'workspace_git_remote_service.dart';
import 'workspace_remote_persistence.dart';
import 'workspace_secret_service.dart';

class WorkspaceGitConnectionCheck {
  const WorkspaceGitConnectionCheck({
    required this.result,
    this.savedSecret,
  });

  final WorkspaceGitRemoteCheckResult result;
  final WorkspaceSecretMetadata? savedSecret;
}

class WorkspaceGitConnectionCoordinator {
  const WorkspaceGitConnectionCoordinator({
    required this.remote,
    required this.secrets,
    required this.git,
  });

  final WorkspaceRemotePersistence remote;
  final WorkspaceSecretService secrets;
  final WorkspaceGitRemoteService git;

  Future<List<WorkspaceSecretMetadata>> listGitSecrets({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    await _stageWorkspace(project: project, snapshot: snapshot);
    final values = await secrets.listSecrets(project.id);
    return values
        .where((secret) => secret.contexts.contains(WorkspaceSecretContext.git))
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<WorkspaceGitConnectionCheck> check({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    String? secretName,
    String? secretValue,
    String? username,
  }) async {
    final remoteBinding = project.gitRemote;
    if (remoteBinding == null) {
      throw StateError('Workspace has no Git remote binding.');
    }

    await _stageWorkspace(project: project, snapshot: snapshot);

    final normalizedSecretName = _normalizeOptional(secretName);
    final normalizedSecretValue = _normalizeSecretValue(secretValue);
    if (normalizedSecretValue != null && normalizedSecretName == null) {
      throw const FormatException(
        'Secret name is required when saving a Git credential.',
      );
    }

    WorkspaceSecretMetadata? savedSecret;
    if (normalizedSecretValue != null) {
      savedSecret = await secrets.putSecret(
        workspaceId: project.id,
        name: normalizedSecretName!,
        value: normalizedSecretValue,
        contexts: const <WorkspaceSecretContext>{WorkspaceSecretContext.git},
      );
    }

    final result = await git.checkRemote(
      workspaceId: project.id,
      secretName: normalizedSecretName,
      username: _normalizeOptional(username),
    );

    if (result.repositoryUrl != remoteBinding.repositoryUrl ||
        result.branch != remoteBinding.branch) {
      throw StateError(
        'Git remote check result does not match the active Workspace binding.',
      );
    }

    return WorkspaceGitConnectionCheck(
      result: result,
      savedSecret: savedSecret,
    );
  }

  Future<void> _stageWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    final existing = await remote.loadWorkspace(project.id);
    if (existing == null) {
      await remote.createWorkspace(project: project, snapshot: snapshot);
      return;
    }

    await remote.saveWorkspace(
      project: project,
      snapshot: existing.snapshot,
      expectedRevision: existing.revision,
    );
  }

  String? _normalizeOptional(String? value) {
    if (value == null) return null;
    final source = value.trim();
    return source.isEmpty ? null : source;
  }

  String? _normalizeSecretValue(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
