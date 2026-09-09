import 'dart:convert';
import 'dart:typed_data';

import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../models/flutter_project_import_bundle.dart';

class FlutterProjectDirectoryImportService {
  const FlutterProjectDirectoryImportService();

  static const int maxImportedFiles = 6000;
  static const int maxSingleFileBytes = 25 * 1024 * 1024;
  static const int maxImportedBytes = 120 * 1024 * 1024;

  static const Set<String> _ignoredDirectoryNames = <String>{
    '.git',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.symlinks',
    '.plugin_symlinks',
    'build',
    'coverage',
    'node_modules',
    'Pods',
  };

  static const Set<String> _ignoredRootFiles = <String>{
    '.metadata',
    '.packages',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.DS_Store',
  };

  FlutterProjectImportBundle parse(
    List<({String path, Uint8List bytes})> pickedFiles, {
    DateTime? importedAt,
  }) {
    if (pickedFiles.isEmpty) {
      throw const FormatException('Selected folder is empty.');
    }

    final normalized = <({String path, Uint8List bytes})>[];
    for (final file in pickedFiles) {
      final path = _normalizePath(file.path);
      if (path.isEmpty) continue;
      normalized.add((path: path, bytes: file.bytes));
    }
    if (normalized.isEmpty) {
      throw const FormatException('Selected folder contains no readable files.');
    }

    final projectRoot = _detectFlutterProjectRoot(normalized);
    final rootName = _projectRootName(projectRoot);
    final retained = <String, Uint8List>{};
    var ignoredFileCount = 0;
    var importedBytes = 0;

    for (final file in normalized) {
      final relative = _relativeToProjectRoot(file.path, projectRoot);
      if (relative == null) {
        ignoredFileCount += 1;
        continue;
      }
      if (relative.isEmpty) continue;
      if (_shouldIgnore(relative)) {
        ignoredFileCount += 1;
        continue;
      }
      if (retained.containsKey(relative)) {
        throw FormatException('Folder contains duplicate path: $relative');
      }
      if (retained.length >= maxImportedFiles) {
        throw const FormatException(
          'Project contains more than 6000 portable files.',
        );
      }
      if (file.bytes.length > maxSingleFileBytes) {
        throw FormatException(
          'File is larger than the 25 MB per-file limit: $relative',
        );
      }

      importedBytes += file.bytes.length;
      if (importedBytes > maxImportedBytes) {
        throw const FormatException(
          'Project is larger than the 120 MB folder-import limit.',
        );
      }
      retained[relative] = file.bytes;
    }

    final pubspecBytes = retained['pubspec.yaml'];
    if (pubspecBytes == null) {
      throw const FormatException(
        'Flutter pubspec.yaml was detected, but could not be imported.',
      );
    }
    final pubspec = _decodeRequiredText('pubspec.yaml', pubspecBytes);
    if (!_looksLikeFlutterPubspec(pubspec)) {
      throw const FormatException(
        'The selected folder does not look like a Flutter project.',
      );
    }

    final snapshot = _buildSnapshot(
      retained,
      importedAt: importedAt ?? DateTime.now().toUtc(),
    );

    return FlutterProjectImportBundle(
      projectName: _projectName(pubspec, rootName),
      snapshot: snapshot,
      importedFileCount: retained.length,
      ignoredFileCount: ignoredFileCount,
    );
  }

  WorkspaceSnapshot _buildSnapshot(
    Map<String, Uint8List> files, {
    required DateTime importedAt,
  }) {
    final directories = <String>{};
    for (final path in files.keys) {
      final parts = path.split('/');
      for (var index = 1; index < parts.length; index++) {
        directories.add(parts.take(index).join('/'));
      }
    }

    final directoryPaths = directories.toList()
      ..sort((a, b) {
        final depth = _depth(a).compareTo(_depth(b));
        return depth != 0 ? depth : a.compareTo(b);
      });
    final filePaths = files.keys.toList()..sort();

    final entries = <WorkspaceEntry>[];
    final rootDirectoryIds = <String>[];
    final textPaths = <String>{};
    var idCounter = 0;

    for (final path in directoryPaths) {
      final id = 'folder-${++idCounter}';
      entries.add(
        WorkspaceEntry(
          id: id,
          path: path,
          type: WorkspaceEntryType.directory,
        ),
      );
      if (!path.contains('/')) rootDirectoryIds.add(id);
    }

    for (final path in filePaths) {
      final bytes = files[path]!;
      final text = _tryDecodeText(bytes);
      if (text == null) {
        entries.add(
          WorkspaceEntry.binary(
            id: 'folder-${++idCounter}',
            path: path,
            bytes: bytes,
          ),
        );
      } else {
        textPaths.add(path);
        entries.add(
          WorkspaceEntry(
            id: 'folder-${++idCounter}',
            path: path,
            type: WorkspaceEntryType.file,
            content: text,
          ),
        );
      }
    }

    final dartPaths = textPaths.where((path) => path.endsWith('.dart')).toList()
      ..sort();
    final activePath = textPaths.contains('lib/main.dart')
        ? 'lib/main.dart'
        : dartPaths.isNotEmpty
            ? dartPaths.first
            : 'pubspec.yaml';
    final openFiles = <String>[
      activePath,
      if (activePath != 'pubspec.yaml') 'pubspec.yaml',
    ];

    return WorkspaceSnapshot(
      entries: entries,
      baseEntries: List<WorkspaceEntry>.of(entries),
      openFiles: openFiles,
      activePath: activePath,
      nextId: idCounter + 1,
      savedAt: importedAt.toUtc(),
      expandedDirectoryIds: rootDirectoryIds,
    );
  }

  String _detectFlutterProjectRoot(
    List<({String path, Uint8List bytes})> files,
  ) {
    final candidates = <String>[];

    for (final file in files) {
      if (file.path != 'pubspec.yaml' && !file.path.endsWith('/pubspec.yaml')) {
        continue;
      }

      final pubspec = _tryDecodeText(file.bytes);
      if (pubspec == null || !_looksLikeFlutterPubspec(pubspec)) continue;

      final slash = file.path.lastIndexOf('/');
      candidates.add(slash == -1 ? '' : file.path.substring(0, slash));
    }

    if (candidates.isEmpty) {
      throw const FormatException(
        'No Flutter pubspec.yaml was found in the selected folder.',
      );
    }

    candidates.sort((a, b) {
      final depth = _depth(a).compareTo(_depth(b));
      return depth != 0 ? depth : a.length.compareTo(b.length);
    });

    final shallowestDepth = _depth(candidates.first);
    final shallowest = candidates
        .where((candidate) => _depth(candidate) == shallowestDepth)
        .toList(growable: false);

    if (shallowest.length > 1) {
      throw FormatException(
        'Multiple Flutter projects were found: '
        '${shallowest.map((path) => path.isEmpty ? '.' : path).join(', ')}',
      );
    }

    return shallowest.single;
  }

  String _projectRootName(String projectRoot) {
    if (projectRoot.isEmpty) return '';
    final slash = projectRoot.lastIndexOf('/');
    return slash == -1 ? projectRoot : projectRoot.substring(slash + 1);
  }

  String? _relativeToProjectRoot(String path, String projectRoot) {
    if (projectRoot.isEmpty) return path;
    if (path == projectRoot) return '';

    final prefix = '$projectRoot/';
    if (!path.startsWith(prefix)) return null;
    return path.substring(prefix.length);
  }

  bool _shouldIgnore(String relativePath) {
    if (_ignoredRootFiles.contains(relativePath)) return true;
    if (relativePath.startsWith('__MACOSX/')) return true;
    final segments = relativePath.split('/');
    return segments.any(_ignoredDirectoryNames.contains);
  }

  bool _looksLikeFlutterPubspec(String content) {
    return RegExp(r'^\s*flutter\s*:\s*$', multiLine: true).hasMatch(content) ||
        RegExp(r'^\s*sdk\s*:\s*flutter\s*$', multiLine: true).hasMatch(content);
  }

  String _projectName(String pubspec, String rootName) {
    final match = RegExp(
      r'^\s*name\s*:\s*([A-Za-z0-9_\-]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    final fromPubspec = match?.group(1)?.trim();
    if (fromPubspec != null && fromPubspec.isNotEmpty) return fromPubspec;
    return rootName.isEmpty ? 'Local Flutter Project' : rootName;
  }

  String _decodeRequiredText(String path, Uint8List bytes) {
    final text = _tryDecodeText(bytes);
    if (text == null) {
      throw FormatException('Expected UTF-8 text file: $path');
    }
    return text;
  }

  String? _tryDecodeText(Uint8List bytes) {
    if (bytes.contains(0)) return null;
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  String _normalizePath(String rawPath) {
    var value = rawPath.replaceAll('\\', '/').trim();
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
      throw FormatException('Folder contains an absolute path: $rawPath');
    }

    final segments = value.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.any((part) => part == '.' || part == '..')) {
      throw FormatException('Folder contains an unsafe path: $rawPath');
    }
    return segments.join('/');
  }

  int _depth(String path) => '/'.allMatches(path).length;
}
