import '../models/workspace_project.dart';
import '../models/workspace_snapshot_delta.dart';

class WorkspaceRemoteMutationResult {
  const WorkspaceRemoteMutationResult({required this.revision});

  final String revision;

  factory WorkspaceRemoteMutationResult.fromJson(Map<dynamic, dynamic> json) {
    final revision = json['revision'];
    if (revision is! String || revision.isEmpty) {
      throw const FormatException('Invalid remote Workspace mutation result.');
    }
    return WorkspaceRemoteMutationResult(revision: revision);
  }
}

/// Optional remote capability for compact Workspace delta transport.
/// Remotes that only implement the existing full-snapshot API continue to
/// work through CloudBackedWorkspacePersistence's fallback path.
abstract interface class WorkspaceDeltaRemotePersistence {
  Future<WorkspaceRemoteMutationResult> patchWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshotDelta delta,
    required String expectedRevision,
  });
}
