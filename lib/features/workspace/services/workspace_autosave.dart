import 'dart:async';

import '../controllers/workspace_controller.dart';
import '../models/workspace_snapshot.dart';
import 'workspace_snapshot_store.dart';

class WorkspaceAutosave {
  WorkspaceAutosave({
    required this.workspace,
    required this.store,
    required this.storageKey,
  }) {
    final saved = store.load(storageKey);
    if (saved != null) {
      workspace.restoreSnapshot(saved);
      restoredSnapshot = true;
    }
    workspace.addListener(_handleWorkspaceChanged);
  }

  final WorkspaceController workspace;
  final WorkspaceSnapshotStore store;
  final String storageKey;

  bool restoredSnapshot = false;
  bool _disposed = false;
  bool _saveRequested = false;
  Timer? _debounce;
  Future<void>? _saveLoop;

  void _handleWorkspaceChanged() {
    requestSave();
  }

  void requestSave({
    Duration delay = const Duration(milliseconds: 1200),
  }) {
    if (_disposed) return;
    _saveRequested = true;
    _debounce?.cancel();
    _debounce = Timer(delay, _startSaveLoop);
  }

  void _startSaveLoop() {
    _debounce = null;
    if (_disposed || !_saveRequested) return;
    _saveLoop ??= _drainSaves();
  }

  Future<void> _drainSaves() async {
    try {
      while (_saveRequested && !_disposed) {
        _saveRequested = false;
        final snapshot = workspace.createSnapshot();
        await store.save(storageKey, snapshot);
      }
    } finally {
      _saveLoop = null;
      if (_saveRequested && !_disposed && _debounce == null) {
        _saveLoop = _drainSaves();
      }
    }
  }

  Future<void> flush() async {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    _saveRequested = true;
    _saveLoop ??= _drainSaves();
    await _saveLoop;
  }

  Future<void> clear() async {
    _debounce?.cancel();
    _debounce = null;
    _saveRequested = false;
    await store.delete(storageKey);
  }

  void dispose() {
    if (_disposed) return;
    workspace.removeListener(_handleWorkspaceChanged);
    _debounce?.cancel();
    _debounce = null;
    _saveRequested = false;
    final finalSnapshot = workspace.createSnapshot();
    final pendingSave = _saveLoop;
    _disposed = true;

    if (pendingSave == null) {
      unawaited(store.save(storageKey, finalSnapshot));
    } else {
      unawaited(
        pendingSave.then((_) => store.save(storageKey, finalSnapshot)),
      );
    }
  }
}
