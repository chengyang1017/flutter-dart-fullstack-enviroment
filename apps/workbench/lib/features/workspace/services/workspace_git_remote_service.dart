import '../models/workspace_git_pull.dart';
import '../models/workspace_git_push.dart';
import '../models/workspace_git_remote_check.dart';

abstract interface class WorkspaceGitRemoteService {
  Future<WorkspaceGitRemoteCheckResult> checkRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  });

  Future<WorkspaceGitPullResult> pullRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  });

  Future<WorkspaceGitPushResult> pushRemote({
    required String workspaceId,
    required String expectedWorkspaceRevision,
    required String expectedRemoteHead,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? secretName,
    String? username,
  });
}
