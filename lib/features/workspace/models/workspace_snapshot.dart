import 'workspace_entry.dart';

class WorkspaceEditorState {
  const WorkspaceEditorState({
    this.baseIndex = 0,
    this.baseOffset = 0,
    this.extentIndex = 0,
    this.extentOffset = 0,
    this.verticalOffset = 0,
    this.horizontalOffset = 0,
  });

  final int baseIndex;
  final int baseOffset;
  final int extentIndex;
  final int extentOffset;
  final double verticalOffset;
  final double horizontalOffset;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseIndex': baseIndex,
        'baseOffset': baseOffset,
        'extentIndex': extentIndex,
        'extentOffset': extentOffset,
        'verticalOffset': verticalOffset,
        'horizontalOffset': horizontalOffset,
      };

  factory WorkspaceEditorState.fromJson(Map<dynamic, dynamic> json) {
    int readInt(String key) {
      final value = json[key];
      return value is int && value >= 0 ? value : 0;
    }

    double readDouble(String key) {
      final value = json[key];
      if (value is num && value.isFinite && value >= 0) {
        return value.toDouble();
      }
      return 0;
    }

    return WorkspaceEditorState(
      baseIndex: readInt('baseIndex'),
      baseOffset: readInt('baseOffset'),
      extentIndex: readInt('extentIndex'),
      extentOffset: readInt('extentOffset'),
      verticalOffset: readDouble('verticalOffset'),
      horizontalOffset: readDouble('horizontalOffset'),
    );
  }
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.entries,
    required this.baseEntries,
    required this.openFiles,
    required this.activePath,
    required this.nextId,
    required this.savedAt,
    this.expandedDirectoryIds = const <String>[],
    this.editorStates = const <String, WorkspaceEditorState>{},
    this.formatVersion = currentFormatVersion,
  });

  static const currentFormatVersion = 3;
  static const oldestSupportedFormatVersion = 1;

  final int formatVersion;
  final List<WorkspaceEntry> entries;
  final List<WorkspaceEntry> baseEntries;
  final List<String> openFiles;
  final String activePath;
  final int nextId;
  final DateTime savedAt;
  final List<String> expandedDirectoryIds;
  final Map<String, WorkspaceEditorState> editorStates;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'formatVersion': formatVersion,
        'entries': entries.map(_entryToJson).toList(growable: false),
        'baseEntries': baseEntries.map(_entryToJson).toList(growable: false),
        'openFiles': openFiles,
        'activePath': activePath,
        'nextId': nextId,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'expandedDirectoryIds': expandedDirectoryIds,
        'editorStates': editorStates.map(
          (id, state) => MapEntry(id, state.toJson()),
        ),
      };

  factory WorkspaceSnapshot.fromJson(Map<dynamic, dynamic> json) {
    final rawVersion = json['formatVersion'];
    final version = rawVersion is int ? rawVersion : oldestSupportedFormatVersion;
    if (version < oldestSupportedFormatVersion ||
        version > currentFormatVersion) {
      throw FormatException('Unsupported workspace snapshot version: $version');
    }

    final entries = _readEntries(json['entries'], version: version);
    final baseEntries = _readEntries(json['baseEntries'], version: version);
    final rawOpenFiles = json['openFiles'];
    final openFiles = rawOpenFiles is Iterable
        ? rawOpenFiles.whereType<String>().toList(growable: false)
        : const <String>[];

    final activePath = json['activePath'];
    final nextId = json['nextId'];
    final savedAt = json['savedAt'];

    return WorkspaceSnapshot(
      formatVersion: version,
      entries: entries,
      baseEntries: baseEntries,
      openFiles: openFiles,
      activePath: activePath is String ? activePath : '',
      nextId: nextId is int && nextId > 0 ? nextId : 1,
      savedAt: savedAt is String
          ? DateTime.tryParse(savedAt)?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      expandedDirectoryIds: _readExpandedDirectoryIds(
        json['expandedDirectoryIds'],
        entries,
      ),
      editorStates: _readEditorStates(json['editorStates']),
    );
  }

  static Map<String, dynamic> _entryToJson(WorkspaceEntry entry) =>
      <String, dynamic>{
        'id': entry.id,
        'path': entry.path,
        'type': entry.isDirectory ? 'directory' : 'file',
        'content': entry.content,
        if (entry.isFile) 'encoding': entry.encoding.name,
      };

  static List<WorkspaceEntry> _readEntries(
    dynamic value, {
    required int version,
  }) {
    if (value is! Iterable) {
      throw const FormatException('Workspace snapshot entries are missing.');
    }

    return value.map((dynamic item) {
      if (item is! Map) {
        throw const FormatException('Invalid workspace snapshot entry.');
      }

      final id = item['id'];
      final path = item['path'];
      final type = item['type'];
      final content = item['content'];

      if (id is! String || path is! String) {
        throw const FormatException('Workspace entry id/path is invalid.');
      }

      final entryType = switch (type) {
        'directory' => WorkspaceEntryType.directory,
        'file' => WorkspaceEntryType.file,
        _ => throw FormatException('Unknown workspace entry type: $type'),
      };
      final encoding = _readEncoding(
        item['encoding'],
        entryType: entryType,
        version: version,
      );
      final payload = content is String ? content : '';
      if (encoding == WorkspaceFileEncoding.base64) {
        try {
          WorkspaceEntry(
            id: id,
            path: path,
            type: entryType,
            content: payload,
            encoding: encoding,
          ).bytes;
        } on FormatException {
          throw FormatException('Invalid base64 Workspace file: $path');
        }
      }

      return WorkspaceEntry(
        id: id,
        path: path,
        type: entryType,
        content: payload,
        encoding: encoding,
      );
    }).toList(growable: false);
  }

  static WorkspaceFileEncoding _readEncoding(
    dynamic value, {
    required WorkspaceEntryType entryType,
    required int version,
  }) {
    if (entryType == WorkspaceEntryType.directory || version < 3) {
      return WorkspaceFileEncoding.utf8;
    }
    return switch (value) {
      null || 'utf8' => WorkspaceFileEncoding.utf8,
      'base64' => WorkspaceFileEncoding.base64,
      _ => throw FormatException('Unknown Workspace file encoding: $value'),
    };
  }

  static List<String> _readExpandedDirectoryIds(
    dynamic value,
    List<WorkspaceEntry> entries,
  ) {
    if (value is Iterable) {
      return value.whereType<String>().toSet().toList(growable: false);
    }

    // v1 snapshots did not store explorer expansion state. Preserve the old
    // visual behavior by expanding root-level directories on first v2+ load.
    return entries
        .where((entry) => entry.isDirectory && entry.parentPath.isEmpty)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  static Map<String, WorkspaceEditorState> _readEditorStates(dynamic value) {
    if (value is! Map) return const <String, WorkspaceEditorState>{};

    final states = <String, WorkspaceEditorState>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value is Map) {
        states[entry.key as String] = WorkspaceEditorState.fromJson(
          entry.value as Map,
        );
      }
    }
    return states;
  }
}
