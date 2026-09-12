import 'workspace_project_catalog_store.dart';
import 'workspace_snapshot_store.dart';

abstract interface class WorkspacePersistence {
  WorkspaceProjectCatalogStore get catalogStore;

  WorkspaceSnapshotStore get snapshotStore;
}
