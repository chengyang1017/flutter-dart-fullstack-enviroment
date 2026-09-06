import '../models/workspace_identity.dart';
import '../models/workspace_project.dart';
import '../models/workspace_remote_models.dart';
import '../models/workspace_snapshot.dart';

/// Remote Workspace storage bound to one authenticated user session.
///
/// Implementations must derive Workspace ownership from their authenticated
/// server credentials. Remote methods intentionally do not accept an owner id,
/// so a client cannot switch owners by changing request metadata.
abstract interface class WorkspaceRemotePersistence {
  WorkspaceIdentity get identity;

  Future<WorkspaceRemoteCatalog> loadCatalog();

  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId);

  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  });

  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  });

  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  });
}
