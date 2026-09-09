import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/workspace_change.dart';
import '../models/workspace_entry.dart';
import '../models/workspace_snapshot.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController._({
    required List<WorkspaceEntry> entries,
    List<WorkspaceEntry>? baseEntries,
    required this.activePath,
    List<String>? openFiles,
    int nextId = 1,
    Set<String>? expandedDirectoryIds,
    Map<String, WorkspaceEditorState>? editorStates,
  })  : _entries = {for (final entry in entries) entry.id: entry},
        _baseEntries = {
          for (final entry in baseEntries ?? entries) entry.id: entry,
        },
        _openFiles = List<String>.of(openFiles ?? <String>[activePath]),
        _expandedDirectoryIds = Set<String>.of(
          expandedDirectoryIds ??
              entries
                  .where(
                    (entry) => entry.isDirectory && entry.parentPath.isEmpty,
                  )
                  .map((entry) => entry.id),
        ),
        _editorStates = Map<String, WorkspaceEditorState>.of(
          editorStates ?? const <String, WorkspaceEditorState>{},
        ),
        _nextId = nextId;

  factory WorkspaceController.flutterPlayground({
    required String mainDartContent,
  }) {
    return WorkspaceController._(
      activePath: 'lib/main.dart',
      entries: [
        const WorkspaceEntry(
          id: 'dir-lib',
          path: 'lib',
          type: WorkspaceEntryType.directory,
        ),
        WorkspaceEntry(
          id: 'file-main',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: mainDartContent,
        ),
        const WorkspaceEntry(
          id: 'dir-assets',
          path: 'assets',
          type: WorkspaceEntryType.directory,
        ),
        const WorkspaceEntry(
          id: 'dir-test',
          path: 'test',
          type: WorkspaceEntryType.directory,
        ),
        const WorkspaceEntry(
          id: 'file-pubspec',
          path: 'pubspec.yaml',
          type: WorkspaceEntryType.file,
          content: '''name: flutter_practice
description: Lightweight Flutter practice workspace.
publish_to: none

environment:
  sdk: ^3.4.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/
''',
        ),
        const WorkspaceEntry(
          id: 'file-analysis-options',
          path: 'analysis_options.yaml',
          type: WorkspaceEntryType.file,
          content: 'include: package:flutter_lints/flutter.yaml\n',
        ),
      ],
    );
  }

  final Map<String, WorkspaceEntry> _baseEntries;
  final Map<String, WorkspaceEntry> _entries;
  final List<String> _openFiles;
  final Set<String> _expandedDirectoryIds;
  final Map<String, WorkspaceEditorState> _editorStates;
  final Set<String> _stagedPaths = <String>{};

  Timer? _contentNotificationDebounce;
  int _nextId;
  String activePath;

  List<WorkspaceEntry> get entries {
    final values = _entries.values.toList()
      ..sort((a, b) {
        if (a.parentPath == b.parentPath && a.type != b.type) {
          return a.isDirectory ? -1 : 1;
        }
        return a.path.compareTo(b.path);
      });
    return List.unmodifiable(values);
  }

  List<String> get openFiles => List.unmodifiable(_openFiles);

  WorkspaceEntry? get activeEntry => entryAt(activePath);

  WorkspaceEntry? entryAt(String path) {
    for (final entry in _entries.values) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  WorkspaceEntry? entryById(String id) => _entries[id];

  bool get isDirty => changes.isNotEmpty;

  List<WorkspaceChange> get stagedChanges => List.unmodifiable(
        changes.where((change) => _stagedPaths.contains(change.path)),
      );

  List<WorkspaceChange> get unstagedChanges => List.unmodifiable(
        changes.where((change) => !_stagedPaths.contains(change.path)),
      );

  bool get hasStagedChanges => stagedChanges.isNotEmpty;

  bool isPathStaged(String path) =>
      changes.any((change) => change.path == path) && _stagedPaths.contains(path);

  WorkspaceChange? changeForPath(String path) {
    for (final change in changes) {
      if (change.path == path) return change;
    }
    return null;
  }

  WorkspaceEntry? baseEntryForChange(WorkspaceChange change) {
    final sourcePath = change.previousPath ?? change.path;
    for (final entry in _baseEntries.values) {
      if (entry.path == sourcePath) return entry;
    }
    return null;
  }

  String? baseContentForChange(WorkspaceChange change) {
    final entry = baseEntryForChange(change);
    return entry != null && entry.isFile ? entry.content : null;
  }

  String? currentContentForChange(WorkspaceChange change) {
    final entry = entryAt(change.path);
    return entry != null && entry.isFile ? entry.content : null;
  }

  void stagePath(String path) {
    if (!changes.any((change) => change.path == path)) return;
    if (_stagedPaths.add(path)) notifyListeners();
  }

  void unstagePath(String path) {
    if (_stagedPaths.remove(path)) notifyListeners();
  }

  void stageAll() {
    final next = changes.map((change) => change.path).toSet();
    if (next.difference(_stagedPaths).isEmpty &&
        _stagedPaths.difference(next).isEmpty) {
      return;
    }
    _stagedPaths
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void unstageAll() {
    if (_stagedPaths.isEmpty) return;
    _stagedPaths.clear();
    notifyListeners();
  }

  bool commitStagedChanges() {
    final staged = stagedChanges;
    if (staged.isEmpty) return false;

    for (final change in staged) {
      if (change.type == WorkspaceChangeType.deleted) {
        final base = baseEntryForChange(change);
        if (base != null) _baseEntries.remove(base.id);
        continue;
      }

      final current = entryAt(change.path);
      if (current != null) {
        _baseEntries[current.id] = current;
      }
    }

    _stagedPaths.removeAll(staged.map((change) => change.path));
    notifyListeners();
    return true;
  }

  bool isFileDirty(String path) {
    final current = entryAt(path);
    if (current == null || !current.isFile) return false;

    final base = _baseEntries[current.id];
    if (base == null) return true;

    return base.path != current.path || base.content != current.content;
  }

  bool isDirectoryExpanded(String path) {
    final entry = entryAt(path);
    return entry != null &&
        entry.isDirectory &&
        _expandedDirectoryIds.contains(entry.id);
  }

  void setDirectoryExpanded(String path, bool expanded) {
    final entry = entryAt(path);
    if (entry == null || !entry.isDirectory) return;

    final changed = expanded
        ? _expandedDirectoryIds.add(entry.id)
        : _expandedDirectoryIds.remove(entry.id);
    if (changed) notifyListeners();
  }

  WorkspaceEditorState? editorStateForPath(String path) {
    final entry = entryAt(path);
    if (entry == null || !entry.isFile) return null;
    return _editorStates[entry.id];
  }

  WorkspaceEditorState? editorStateForEntryId(String id) => _editorStates[id];

  void updateEditorStateByEntryId(String id, WorkspaceEditorState state) {
    final entry = _entries[id];
    if (entry == null || !entry.isFile) return;
    _editorStates[id] = state;
  }

  List<WorkspaceChange> get changes {
    final result = <WorkspaceChange>[];

    for (final base in _baseEntries.values) {
      final current = _entries[base.id];
      if (current == null) {
        result.add(
          WorkspaceChange(
            type: WorkspaceChangeType.deleted,
            path: base.path,
          ),
        );
        continue;
      }

      if (base.path != current.path) {
        result.add(
          WorkspaceChange(
            type: base.parentPath == current.parentPath
                ? WorkspaceChangeType.renamed
                : WorkspaceChangeType.moved,
            path: current.path,
            previousPath: base.path,
          ),
        );
      }

      if (current.isFile && base.content != current.content) {
        result.add(
          WorkspaceChange(
            type: WorkspaceChangeType.modified,
            path: current.path,
          ),
        );
      }
    }

    for (final current in _entries.values) {
      if (!_baseEntries.containsKey(current.id)) {
        result.add(
          WorkspaceChange(
            type: WorkspaceChangeType.created,
            path: current.path,
          ),
        );
      }
    }

    result.sort((a, b) => a.path.compareTo(b.path));
    return List.unmodifiable(result);
  }

  WorkspaceSnapshot createSnapshot() {
    final currentIds = _entries.keys.toSet();
    return WorkspaceSnapshot(
      entries: List<WorkspaceEntry>.of(_entries.values),
      baseEntries: List<WorkspaceEntry>.of(_baseEntries.values),
      openFiles: List<String>.of(_openFiles),
      activePath: activePath,
      nextId: _nextId,
      savedAt: DateTime.now().toUtc(),
      expandedDirectoryIds: _expandedDirectoryIds
          .where(currentIds.contains)
          .toList(growable: false),
      editorStates: <String, WorkspaceEditorState>{
        for (final entry in _editorStates.entries)
          if (currentIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  void restoreSnapshot(WorkspaceSnapshot snapshot) {
    _validateSnapshotEntries(snapshot.entries, label: 'entries');
    _validateSnapshotEntries(snapshot.baseEntries, label: 'baseEntries');

    _contentNotificationDebounce?.cancel();
    _contentNotificationDebounce = null;
    _stagedPaths.clear();

    _entries
      ..clear()
      ..addEntries(snapshot.entries.map((entry) => MapEntry(entry.id, entry)));
    _baseEntries
      ..clear()
      ..addEntries(
        snapshot.baseEntries.map((entry) => MapEntry(entry.id, entry)),
      );

    final availableFiles = _entries.values
        .where((entry) => entry.isFile)
        .map((entry) => entry.path)
        .toSet();
    final availableIds = _entries.keys.toSet();
    final directoryIds = _entries.values
        .where((entry) => entry.isDirectory)
        .map((entry) => entry.id)
        .toSet();
    final fileIds = _entries.values
        .where((entry) => entry.isFile)
        .map((entry) => entry.id)
        .toSet();

    _openFiles
      ..clear()
      ..addAll(
        snapshot.openFiles.where(availableFiles.contains).toSet(),
      );

    if (availableFiles.contains(snapshot.activePath)) {
      activePath = snapshot.activePath;
    } else if (_openFiles.isNotEmpty) {
      activePath = _openFiles.last;
    } else {
      final fallback = availableFiles.toList()..sort();
      activePath = fallback.isEmpty ? '' : fallback.first;
    }

    if (activePath.isNotEmpty && !_openFiles.contains(activePath)) {
      _openFiles.add(activePath);
    }

    _expandedDirectoryIds
      ..clear()
      ..addAll(snapshot.expandedDirectoryIds.where(directoryIds.contains));
    _editorStates
      ..clear()
      ..addEntries(
        snapshot.editorStates.entries.where(
          (entry) =>
              fileIds.contains(entry.key) && availableIds.contains(entry.key),
        ),
      );

    _nextId = snapshot.nextId > 0 ? snapshot.nextId : 1;
    notifyListeners();
  }

  List<WorkspaceEntry> childrenOf(String parentPath) {
    final children = _entries.values
        .where((entry) => entry.parentPath == parentPath)
        .toList()
      ..sort((a, b) {
        if (a.type != b.type) return a.isDirectory ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return List.unmodifiable(children);
  }

  void openFile(String path) {
    final entry = entryAt(path);
    if (entry == null || !entry.isFile) return;

    if (!_openFiles.contains(path)) {
      _openFiles.add(path);
    }
    activePath = path;
    notifyListeners();
  }

  void closeFile(String path) {
    final index = _openFiles.indexOf(path);
    if (index == -1) return;

    _openFiles.removeAt(index);
    if (_openFiles.isEmpty) {
      final fallback = _entries.values
          .where((entry) => entry.isFile)
          .map((entry) => entry.path)
          .toList()
        ..sort();
      if (fallback.isNotEmpty) {
        _openFiles.add(fallback.first);
      }
    }

    if (activePath == path && _openFiles.isNotEmpty) {
      final nextIndex =
          index < _openFiles.length ? index : _openFiles.length - 1;
      activePath = _openFiles[nextIndex];
    }
    notifyListeners();
  }

  void updateFileContent(String path, String content) {
    if (!_replaceFileContent(path, content)) return;
    _contentNotificationDebounce?.cancel();
    notifyListeners();
  }

  void updateFileContentFromEditor(String path, String content) {
    if (!_replaceFileContent(path, content)) return;

    _contentNotificationDebounce?.cancel();
    _contentNotificationDebounce = Timer(
      const Duration(milliseconds: 180),
      () {
        _contentNotificationDebounce = null;
        notifyListeners();
      },
    );
  }

  String createFile(String parentPath, String name, {String content = ''}) {
    final path = _join(parentPath, name);
    _assertCreatablePath(path);
    if (parentPath.isNotEmpty) _assertDirectory(parentPath);

    final entry = WorkspaceEntry(
      id: _newId(),
      path: path,
      type: WorkspaceEntryType.file,
      content: content,
    );
    _entries[entry.id] = entry;
    _openFiles.add(path);
    activePath = path;
    notifyListeners();
    return path;
  }

  String createDirectory(String parentPath, String name) {
    final path = _join(parentPath, name);
    _assertCreatablePath(path);
    if (parentPath.isNotEmpty) _assertDirectory(parentPath);

    final entry = WorkspaceEntry(
      id: _newId(),
      path: path,
      type: WorkspaceEntryType.directory,
    );
    _entries[entry.id] = entry;
    _expandedDirectoryIds.add(entry.id);
    notifyListeners();
    return path;
  }

  void deleteEntry(String path) {
    final entry = entryAt(path);
    if (entry == null) return;

    final removedEntries = _entries.values
        .where((candidate) =>
            candidate.path == path || candidate.path.startsWith('$path/'))
        .toList(growable: false);
    final removedPaths = removedEntries.map((entry) => entry.path).toSet();
    final removedIds = removedEntries.map((entry) => entry.id).toSet();

    _entries.removeWhere(
      (_, candidate) => removedPaths.contains(candidate.path),
    );
    _openFiles.removeWhere(removedPaths.contains);
    _expandedDirectoryIds.removeAll(removedIds);
    _editorStates.removeWhere((id, _) => removedIds.contains(id));

    if (removedPaths.contains(activePath)) {
      if (_openFiles.isNotEmpty) {
        activePath = _openFiles.last;
      } else {
        final fallback = _entries.values
            .where((candidate) => candidate.isFile)
            .map((candidate) => candidate.path)
            .toList()
          ..sort();
        if (fallback.isNotEmpty) {
          activePath = fallback.first;
          _openFiles.add(activePath);
        } else {
          activePath = '';
        }
      }
    }
    notifyListeners();
  }

  void renameEntry(String path, String newName) {
    final entry = entryAt(path);
    if (entry == null) return;
    final target = _join(entry.parentPath, newName);
    _movePath(path, target);
  }

  void moveEntry(String path, String newParentPath) {
    final entry = entryAt(path);
    if (entry == null) return;
    if (newParentPath.isNotEmpty) _assertDirectory(newParentPath);

    if (entry.isDirectory &&
        (newParentPath == path || newParentPath.startsWith('$path/'))) {
      throw ArgumentError('Cannot move a directory into itself.');
    }

    final target = _join(newParentPath, entry.name);
    _movePath(path, target);
  }

  void relocateEntry(String sourcePath, String targetPath) {
    final entry = entryAt(sourcePath);
    if (entry == null) {
      throw ArgumentError('Workspace entry does not exist: $sourcePath');
    }

    final separator = targetPath.lastIndexOf('/');
    final targetParent =
        separator == -1 ? '' : targetPath.substring(0, separator);
    if (targetParent.isNotEmpty) {
      _assertDirectory(targetParent);
    }

    if (entry.isDirectory &&
        (targetPath == sourcePath || targetPath.startsWith('$sourcePath/'))) {
      throw ArgumentError('Cannot move a directory into itself.');
    }

    _movePath(sourcePath, targetPath);
  }

  void resetFile(String path) {
    final current = entryAt(path);
    if (current == null || !current.isFile) return;
    final base = _baseEntries[current.id];
    if (base == null) {
      deleteEntry(path);
      return;
    }

    final oldPath = current.path;
    _entries[current.id] = base;
    _replaceOpenPath(oldPath, base.path);
    if (activePath == oldPath) activePath = base.path;
    notifyListeners();
  }

  void resetWorkspace() {
    _entries
      ..clear()
      ..addAll(_baseEntries);
    _openFiles
      ..clear()
      ..add('lib/main.dart');
    _expandedDirectoryIds
      ..clear()
      ..addAll(
        _baseEntries.values
            .where((entry) => entry.isDirectory && entry.parentPath.isEmpty)
            .map((entry) => entry.id),
      );
    _editorStates.clear();
    _stagedPaths.clear();
    activePath = 'lib/main.dart';
    notifyListeners();
  }

  bool commitChanges() {
    if (!isDirty) return false;

    _baseEntries
      ..clear()
      ..addEntries(
        _entries.entries.map(
          (entry) => MapEntry(entry.key, entry.value),
        ),
      );
    _stagedPaths.clear();
    notifyListeners();
    return true;
  }

  bool _replaceFileContent(String path, String content) {
    final entry = entryAt(path);
    if (entry == null || !entry.isFile || entry.content == content) {
      return false;
    }

    _stagedPaths.remove(path);
    _entries[entry.id] = entry.copyWith(content: content);
    return true;
  }

  void _movePath(String source, String target) {
    if (source == target) return;
    _validatePath(target);

    final affected = _entries.values
        .where((entry) =>
            entry.path == source || entry.path.startsWith('$source/'))
        .toList();
    final affectedIds = affected.map((entry) => entry.id).toSet();

    for (final entry in affected) {
      final suffix = entry.path.substring(source.length);
      final nextPath = '$target$suffix';
      final collision = _entries.values.any(
        (candidate) =>
            !affectedIds.contains(candidate.id) && candidate.path == nextPath,
      );
      if (collision) {
        throw ArgumentError('Path already exists: $nextPath');
      }
    }

    for (final entry in affected) {
      final suffix = entry.path.substring(source.length);
      _entries[entry.id] = entry.copyWith(path: '$target$suffix');
    }

    for (var i = 0; i < _openFiles.length; i++) {
      final open = _openFiles[i];
      if (open == source || open.startsWith('$source/')) {
        _openFiles[i] = '$target${open.substring(source.length)}';
      }
    }

    if (activePath == source || activePath.startsWith('$source/')) {
      activePath = '$target${activePath.substring(source.length)}';
    }
    notifyListeners();
  }

  void _replaceOpenPath(String oldPath, String newPath) {
    final index = _openFiles.indexOf(oldPath);
    if (index != -1) _openFiles[index] = newPath;
  }

  void _validateSnapshotEntries(
    List<WorkspaceEntry> entries, {
    required String label,
  }) {
    final ids = <String>{};
    final paths = <String>{};
    for (final entry in entries) {
      _validatePath(entry.path);
      if (!ids.add(entry.id)) {
        throw FormatException('Duplicate workspace id in $label: ${entry.id}');
      }
      if (!paths.add(entry.path)) {
        throw FormatException(
          'Duplicate workspace path in $label: ${entry.path}',
        );
      }
    }
  }

  void _assertDirectory(String path) {
    final parent = entryAt(path);
    if (parent == null || !parent.isDirectory) {
      throw ArgumentError('Directory does not exist: $path');
    }
  }

  void _assertCreatablePath(String path) {
    _validatePath(path);
    final collision = _entries.values.any((entry) => entry.path == path);
    if (collision) throw ArgumentError('Path already exists: $path');
  }

  void _validatePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      throw ArgumentError('Workspace paths must be relative POSIX paths.');
    }
    if (path.split('/').any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError('Invalid workspace path: $path');
    }
  }

  String _newId() => 'workspace-${_nextId++}';

  String _join(String parent, String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.contains('/') ||
        cleanName.contains('\\')) {
      throw ArgumentError('Name must be a single path segment.');
    }
    return parent.isEmpty ? cleanName : '$parent/$cleanName';
  }

  @override
  void dispose() {
    _contentNotificationDebounce?.cancel();
    super.dispose();
  }
}
