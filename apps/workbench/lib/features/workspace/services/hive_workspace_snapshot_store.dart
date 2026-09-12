import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/workspace_entry.dart';
import '../models/workspace_snapshot.dart';
import 'workspace_pending_sync_store.dart';
import 'workspace_snapshot_store.dart';

/// Hive-backed Workspace snapshots stored as one small manifest plus one value
/// per entry.
///
/// Older versions stored the complete [WorkspaceSnapshot] under [key]. The
/// first save after upgrading migrates that legacy value into split storage.
/// Later saves compare entry payloads and only write files that actually
/// changed, while the small editor/explorer manifest is refreshed every time.
class HiveWorkspaceSnapshotStore
    implements WorkspaceSnapshotStore, WorkspacePendingSyncStore {
  HiveWorkspaceSnapshotStore(this.box);

  static const _storageFormat = 1;
  static const _namespace = '__workspace_snapshot_split_v1__';
  static const _pendingNamespace = '__workspace_cloud_pending_v1__';

  final Box<dynamic> box;

  @override
  bool isPendingSync(String key) => box.get(_pendingKey(key)) == true;

  @override
  Future<void> markPendingSync(String key) => box.put(_pendingKey(key), true);

  @override
  Future<void> clearPendingSync(String key) => box.delete(_pendingKey(key));

  @override
  WorkspaceSnapshot? load(String key) {
    final split = _loadSplit(key);
    if (split != null) return split;

    final raw = box.get(key);
    if (raw is! Map) return null;

    try {
      return WorkspaceSnapshot.fromJson(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    final rawMeta = box.get(_metaKey(key));
    final previousMeta = _readMeta(rawMeta);

    final entryIds = snapshot.entries.map((entry) => entry.id).toList();
    final baseEntryIds = snapshot.baseEntries.map((entry) => entry.id).toList();

    for (final entry in snapshot.entries) {
      await _putEntryIfChanged(
        _entryKey(key, entry.id),
        _entryToJson(entry),
      );
    }
    for (final entry in snapshot.baseEntries) {
      await _putEntryIfChanged(
        _baseEntryKey(key, entry.id),
        _entryToJson(entry),
      );
    }

    await box.put(
      _metaKey(key),
      <String, dynamic>{
        'storageFormat': _storageFormat,
        'manifest': _manifestToJson(snapshot),
        'entryIds': entryIds,
        'baseEntryIds': baseEntryIds,
      },
    );

    if (previousMeta != null) {
      await _deleteRemovedEntries(
        previousMeta.entryIds,
        entryIds,
        (id) => _entryKey(key, id),
      );
      await _deleteRemovedEntries(
        previousMeta.baseEntryIds,
        baseEntryIds,
        (id) => _baseEntryKey(key, id),
      );
    }

    // The split manifest is authoritative after a successful save. Remove the
    // old whole-snapshot value so future browser saves cannot rewrite it.
    if (box.containsKey(key)) {
      await box.delete(key);
    }
  }

  @override
  Future<void> delete(String key) async {
    final meta = _readMeta(box.get(_metaKey(key)));
    if (meta != null) {
      for (final id in meta.entryIds) {
        await box.delete(_entryKey(key, id));
      }
      for (final id in meta.baseEntryIds) {
        await box.delete(_baseEntryKey(key, id));
      }
      await box.delete(_metaKey(key));
    }

    if (box.containsKey(key)) {
      await box.delete(key);
    }
    await clearPendingSync(key);
  }

  WorkspaceSnapshot? _loadSplit(String key) {
    final meta = _readMeta(box.get(_metaKey(key)));
    if (meta == null) return null;

    try {
      final entries = <Map<String, dynamic>>[];
      for (final id in meta.entryIds) {
        final raw = box.get(_entryKey(key, id));
        if (raw is! Map) {
          throw FormatException('Workspace Hive entry is missing: $id');
        }
        entries.add(Map<String, dynamic>.from(raw));
      }

      final baseEntries = <Map<String, dynamic>>[];
      for (final id in meta.baseEntryIds) {
        final raw = box.get(_baseEntryKey(key, id));
        if (raw is! Map) {
          throw FormatException('Workspace Hive base entry is missing: $id');
        }
        baseEntries.add(Map<String, dynamic>.from(raw));
      }

      return WorkspaceSnapshot.fromJson(
        <String, dynamic>{
          ...meta.manifest,
          'entries': entries,
          'baseEntries': baseEntries,
        },
      );
    } on FormatException {
      return null;
    }
  }

  _SplitSnapshotMeta? _readMeta(Object? value) {
    if (value is! Map || value['storageFormat'] != _storageFormat) {
      return null;
    }

    final rawManifest = value['manifest'];
    final rawEntryIds = value['entryIds'];
    final rawBaseEntryIds = value['baseEntryIds'];
    if (rawManifest is! Map ||
        rawEntryIds is! Iterable ||
        rawBaseEntryIds is! Iterable) {
      return null;
    }

    final entryIds = rawEntryIds.whereType<String>().toList(growable: false);
    final baseEntryIds =
        rawBaseEntryIds.whereType<String>().toList(growable: false);
    if (entryIds.length != rawEntryIds.length ||
        baseEntryIds.length != rawBaseEntryIds.length) {
      return null;
    }

    return _SplitSnapshotMeta(
      manifest: Map<String, dynamic>.from(rawManifest),
      entryIds: entryIds,
      baseEntryIds: baseEntryIds,
    );
  }

  Future<void> _putEntryIfChanged(
    String storageKey,
    Map<String, dynamic> next,
  ) async {
    final previous = box.get(storageKey);
    if (_sameEntryJson(previous, next)) return;
    await box.put(storageKey, next);
  }

  Future<void> _deleteRemovedEntries(
    List<String> previousIds,
    List<String> currentIds,
    String Function(String id) keyForId,
  ) async {
    final current = currentIds.toSet();
    for (final id in previousIds) {
      if (!current.contains(id)) {
        await box.delete(keyForId(id));
      }
    }
  }

  static bool _sameEntryJson(Object? previous, Map<String, dynamic> current) {
    if (previous is! Map) return false;
    return previous['id'] == current['id'] &&
        previous['path'] == current['path'] &&
        previous['type'] == current['type'] &&
        previous['content'] == current['content'] &&
        previous['encoding'] == current['encoding'];
  }

  static Map<String, dynamic> _manifestToJson(WorkspaceSnapshot snapshot) =>
      <String, dynamic>{
        'formatVersion': snapshot.formatVersion,
        'openFiles': snapshot.openFiles,
        'activePath': snapshot.activePath,
        'nextId': snapshot.nextId,
        'savedAt': snapshot.savedAt.toUtc().toIso8601String(),
        'expandedDirectoryIds': snapshot.expandedDirectoryIds,
        'editorStates': snapshot.editorStates.map(
          (id, state) => MapEntry(id, state.toJson()),
        ),
      };

  static Map<String, dynamic> _entryToJson(WorkspaceEntry entry) =>
      <String, dynamic>{
        'id': entry.id,
        'path': entry.path,
        'type': entry.isDirectory ? 'directory' : 'file',
        'content': entry.content,
        if (entry.isFile) 'encoding': entry.encoding.name,
      };

  static String _pendingKey(String key) =>
      '$_pendingNamespace:${_token(key)}';

  static String _metaKey(String key) => '$_namespace:meta:${_token(key)}';

  static String _entryKey(String key, String id) =>
      '$_namespace:entry:${_token(key)}:${_token(id)}';

  static String _baseEntryKey(String key, String id) =>
      '$_namespace:base:${_token(key)}:${_token(id)}';

  static String _token(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

class _SplitSnapshotMeta {
  const _SplitSnapshotMeta({
    required this.manifest,
    required this.entryIds,
    required this.baseEntryIds,
  });

  final Map<String, dynamic> manifest;
  final List<String> entryIds;
  final List<String> baseEntryIds;
}
