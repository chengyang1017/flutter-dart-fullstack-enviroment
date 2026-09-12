import 'workspace_entry.dart';
import 'workspace_snapshot.dart';

/// Compact transport for syncing one Workspace snapshot against the last
/// server-confirmed snapshot. Large file payloads are only included when an
/// entry was created or changed; small editor/explorer metadata is sent as a
/// manifest on every sync.
class WorkspaceSnapshotDelta {
  const WorkspaceSnapshotDelta({
    required this.entryUpserts,
    required this.entryDeletes,
    required this.baseEntryUpserts,
    required this.baseEntryDeletes,
    required this.manifest,
  });

  static const formatVersion = 1;

  final List<WorkspaceEntry> entryUpserts;
  final List<String> entryDeletes;
  final List<WorkspaceEntry> baseEntryUpserts;
  final List<String> baseEntryDeletes;
  final Map<String, dynamic> manifest;

  factory WorkspaceSnapshotDelta.between(
    WorkspaceSnapshot previous,
    WorkspaceSnapshot current,
  ) {
    final previousEntries = <String, WorkspaceEntry>{
      for (final entry in previous.entries) entry.id: entry,
    };
    final currentEntries = <String, WorkspaceEntry>{
      for (final entry in current.entries) entry.id: entry,
    };
    final previousBaseEntries = <String, WorkspaceEntry>{
      for (final entry in previous.baseEntries) entry.id: entry,
    };
    final currentBaseEntries = <String, WorkspaceEntry>{
      for (final entry in current.baseEntries) entry.id: entry,
    };

    return WorkspaceSnapshotDelta(
      entryUpserts: current.entries
          .where((entry) => !_sameEntry(previousEntries[entry.id], entry))
          .toList(growable: false),
      entryDeletes: previousEntries.keys
          .where((id) => !currentEntries.containsKey(id))
          .toList(growable: false),
      baseEntryUpserts: current.baseEntries
          .where(
            (entry) => !_sameEntry(previousBaseEntries[entry.id], entry),
          )
          .toList(growable: false),
      baseEntryDeletes: previousBaseEntries.keys
          .where((id) => !currentBaseEntries.containsKey(id))
          .toList(growable: false),
      manifest: <String, dynamic>{
        'formatVersion': current.formatVersion,
        'openFiles': current.openFiles,
        'activePath': current.activePath,
        'nextId': current.nextId,
        'savedAt': current.savedAt.toUtc().toIso8601String(),
        'expandedDirectoryIds': current.expandedDirectoryIds,
        'editorStates': current.editorStates.map(
          (id, state) => MapEntry(id, state.toJson()),
        ),
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'formatVersion': formatVersion,
        'manifest': manifest,
        'entries': <String, dynamic>{
          'upsert': entryUpserts.map(_entryToJson).toList(growable: false),
          'deleteIds': entryDeletes,
        },
        'baseEntries': <String, dynamic>{
          'upsert':
              baseEntryUpserts.map(_entryToJson).toList(growable: false),
          'deleteIds': baseEntryDeletes,
        },
      };

  static bool _sameEntry(WorkspaceEntry? previous, WorkspaceEntry current) {
    if (identical(previous, current)) return true;
    return previous != null &&
        previous.path == current.path &&
        previous.type == current.type &&
        previous.content == current.content &&
        previous.encoding == current.encoding;
  }

  static Map<String, dynamic> _entryToJson(WorkspaceEntry entry) =>
      <String, dynamic>{
        'id': entry.id,
        'path': entry.path,
        'type': entry.isDirectory ? 'directory' : 'file',
        'content': entry.content,
        if (entry.isFile) 'encoding': entry.encoding.name,
      };
}
