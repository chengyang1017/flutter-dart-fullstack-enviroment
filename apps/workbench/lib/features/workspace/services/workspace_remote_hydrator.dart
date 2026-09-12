import '../models/workspace_remote_models.dart';
import 'workspace_remote_persistence.dart';

class WorkspaceRemoteHydrator {
  const WorkspaceRemoteHydrator(this.remote);

  final WorkspaceRemotePersistence remote;

  Future<WorkspaceHydrationResult> hydrate({
    String? preferredWorkspaceId,
  }) async {
    final catalog = await remote.loadCatalog();
    if (catalog.projects.isEmpty) {
      return WorkspaceHydrationResult(
        catalog: catalog,
        activeDocument: null,
      );
    }

    final selectedId = catalog.projects.any(
      (project) => project.id == preferredWorkspaceId,
    )
        ? preferredWorkspaceId!
        : catalog.projects.first.id;

    final document = await remote.loadWorkspace(selectedId);
    if (document == null) {
      throw StateError(
        'Remote Workspace catalog references a missing Workspace: $selectedId',
      );
    }
    if (document.project.id != selectedId) {
      throw StateError(
        'Remote Workspace id mismatch: requested $selectedId, '
        'received ${document.project.id}',
      );
    }

    return WorkspaceHydrationResult(
      catalog: catalog,
      activeDocument: document,
    );
  }
}
