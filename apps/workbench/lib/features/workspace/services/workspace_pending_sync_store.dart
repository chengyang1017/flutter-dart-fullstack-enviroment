/// Optional local capability used by cloud-backed persistence to remember
/// that a Workspace snapshot was saved locally but has not yet been confirmed
/// by the remote service.
///
/// The marker survives browser/tab termination. On the next cloud bootstrap,
/// CloudBackedWorkspacePersistence replays the local snapshot before allowing a
/// remote snapshot to overwrite the browser cache.
abstract interface class WorkspacePendingSyncStore {
  bool isPendingSync(String key);

  Future<void> markPendingSync(String key);

  Future<void> clearPendingSync(String key);
}
