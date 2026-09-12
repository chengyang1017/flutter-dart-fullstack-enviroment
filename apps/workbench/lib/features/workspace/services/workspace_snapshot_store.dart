import '../models/workspace_snapshot.dart';

abstract interface class WorkspaceSnapshotStore {
  WorkspaceSnapshot? load(String key);

  Future<void> save(String key, WorkspaceSnapshot snapshot);

  Future<void> delete(String key);
}
