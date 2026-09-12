import '../models/workspace_snapshot.dart';
import 'workspace_snapshot_store.dart';

class KeyedWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
  KeyedWorkspaceSnapshotStore({
    required this.delegate,
    required this.storageKey,
  });

  final WorkspaceSnapshotStore delegate;
  final String storageKey;

  bool _writesEnabled = true;

  void disableWrites() {
    _writesEnabled = false;
  }

  @override
  WorkspaceSnapshot? load(String key) => delegate.load(storageKey);

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) {
    if (!_writesEnabled) return Future<void>.value();
    return delegate.save(storageKey, snapshot);
  }

  @override
  Future<void> delete(String key) => delegate.delete(storageKey);
}
