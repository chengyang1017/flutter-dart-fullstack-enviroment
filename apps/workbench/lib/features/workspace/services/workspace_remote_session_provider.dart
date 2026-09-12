import 'workspace_remote_persistence.dart';

/// Resolves the remote persistence instance bound to the current auth session.
///
/// Returning null means the user is signed out. Local/temporary Workspaces can
/// continue to use the browser persistence path without a remote session.
abstract interface class WorkspaceRemoteSessionProvider {
  Future<WorkspaceRemotePersistence?> currentRemote();
}
