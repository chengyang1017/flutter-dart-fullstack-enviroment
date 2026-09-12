import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../models/flutter_project_import_bundle.dart';

class FlutterProjectZipImportService {
  const FlutterProjectZipImportService();

  static const int maxZipBytes = 25 * 1024 * 1024;
  static const int maxImportedFiles = 3000;
  static const int maxSingleTextFileBytes = 5 * 1024 * 1024;
  static const int maxImportedTextBytes = 50 * 1024 * 1024;

  static const Set<String> _ignoredTopLevelDirectories = <String>{
    '.git',
    '.dart_tool',
    '.gradle',
    '.idea',
    'build',
    'coverage',
    'android',
    'ios',
    'linux',
    'macos',
    'windows',
    'web',
  };

  static const Set<String> _ignoredRootFiles = <String>{
    '.metadata',
    '.packages',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  };

  FlutterProjectImportBundle parse(
    Uint8List bytes, {
    DateTime? importedAt,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('Flutter project ZIP is empty.');
    }
    if (bytes.length > maxZipBytes) {
      throw const FormatException(
        'Flutter project ZIP is larger than the 25 MB import limit.',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Unable to read Flutter project ZIP.');
    }

    final filesByPath = <String, ArchiveFile>{};
    for (final file in archive.files) {
      final path = _normalizeArchivePath(file.name);
      if (path.isEmpty || !file.isFile) continue;
      if (filesByPath.containsKey(path)) {
        throw FormatException('ZIP contains duplicate file path: $path');
      }
      filesByPath[path] = file;
    }

    final root = _findFlutterRoot(filesByPath);
    final pubspecPath = root.isEmpty ? 'pubspec.yaml' : '$root/pubspec.yaml';
    final pubspec = _decodeText(pubspecPath, filesByPath[pubspecPath]!);
    final projectName = _projectName(pubspec, root);

    final textFiles = <String, String>{};
    final binaryPaths = <String>[];
    var ignoredFileCount = 0;
    var importedTextBytes = 0;

    for (final entry in filesByPath.entries) {
      final relative = _relativeToRoot(entry.key, root);
      if (relative == null || relative.isEmpty) continue;
      if (_shouldIgnore(relative)) {
        ignoredFileCount += 1;
        continue;
      }

      if (textFiles.length >= maxImportedFiles) {
        throw const FormatException(
          'Flutter project contains more than 3000 portable files.',
        );
      }
      if (entry.value.size > maxSingleTextFileBytes) {
        throw FormatException(
          'File is larger than the 5 MB text-file limit: $relative',
        );
      }

      final content = _tryDecodeText(entry.value);
      if (content == null) {
        binaryPaths.add(relative);
        continue;
      }

      importedTextBytes += entry.value.size;
      if (importedTextBytes > maxImportedTextBytes) {
        throw const FormatException(
          'Flutter project contains more than 50 MB of portable text files.',
        );
      }
      textFiles[relative] = content;
    }

    if (binaryPaths.isNotEmpty) {
      binaryPaths.sort();
      final shown = binaryPaths.take(8).join(', ');
      final suffix =
          binaryPaths.length > 8 ? ' (+${binaryPaths.length - 8} more)' : '';
      throw FormatException(
        'This project contains binary portable assets that the current '
        'Workspace protocol cannot preserve yet: $shown$suffix',
      );
    }

    if (!textFiles.containsKey('pubspec.yaml') ||
        !textFiles.containsKey('lib/main.dart')) {
      throw const FormatException(
        'Imported Flutter project must preserve pubspec.yaml and lib/main.dart.',
      );
    }

    final snapshot = _buildSnapshot(
      textFiles,
      importedAt: importedAt ?? DateTime.now().toUtc(),
    );

    return FlutterProjectImportBundle(
      projectName: projectName,
      snapshot: snapshot,
      importedFileCount: textFiles.length,
      ignoredFileCount: ignoredFileCount,
    );
  }

  String _findFlutterRoot(Map<String, ArchiveFile> filesByPath) {
    final candidates = <String>[];

    for (final path in filesByPath.keys) {
      if (path != 'pubspec.yaml' && !path.endsWith('/pubspec.yaml')) continue;

      final root = path == 'pubspec.yaml'
          ? ''
          : path.substring(0, path.length - '/pubspec.yaml'.length);
      final mainPath = root.isEmpty ? 'lib/main.dart' : '$root/lib/main.dart';
      if (!filesByPath.containsKey(mainPath)) continue;

      final pubspec = _tryDecodeText(filesByPath[path]!);
      if (pubspec == null || !_looksLikeFlutterPubspec(pubspec)) continue;
      candidates.add(root);
    }

    if (candidates.isEmpty) {
      throw const FormatException(
        'ZIP must contain one runnable Flutter project with pubspec.yaml '
        'and lib/main.dart.',
      );
    }
    if (candidates.length > 1) {
      throw const FormatException(
        'ZIP contains multiple runnable Flutter projects. Import one project '
        'per ZIP.',
      );
    }
    return candidates.single;
  }

  bool _looksLikeFlutterPubspec(String content) {
    return RegExp(r'^\s*flutter\s*:\s*$', multiLine: true).hasMatch(content) ||
        RegExp(r'^\s*sdk\s*:\s*flutter\s*$', multiLine: true).hasMatch(content);
  }

  String _projectName(String pubspec, String root) {
    final match = RegExp(
      r'^\s*name\s*:\s*([A-Za-z0-9_\-]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    final fromPubspec = match?.group(1)?.trim();
    if (fromPubspec != null && fromPubspec.isNotEmpty) return fromPubspec;
    if (root.isNotEmpty) return root.split('/').last;
    return 'Imported Flutter Project';
  }

  WorkspaceSnapshot _buildSnapshot(
    Map<String, String> files, {
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
        final depthCompare = _depth(a).compareTo(_depth(b));
        return depthCompare != 0 ? depthCompare : a.compareTo(b);
      });
    final filePaths = files.keys.toList()..sort();

    final entries = <WorkspaceEntry>[];
    final rootDirectoryIds = <String>[];
    var idCounter = 0;

    for (final path in directoryPaths) {
      final id = 'import-${++idCounter}';
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
      entries.add(
        WorkspaceEntry(
          id: 'import-${++idCounter}',
          path: path,
          type: WorkspaceEntryType.file,
          content: files[path]!,
        ),
      );
    }

    return WorkspaceSnapshot(
      entries: entries,
      baseEntries: List<WorkspaceEntry>.of(entries),
      openFiles: const <String>['lib/main.dart', 'pubspec.yaml'],
      activePath: 'lib/main.dart',
      nextId: idCounter + 1,
      savedAt: importedAt.toUtc(),
      expandedDirectoryIds: rootDirectoryIds,
    );
  }

  int _depth(String path) => '/'.allMatches(path).length;

  bool _shouldIgnore(String relativePath) {
    if (_ignoredRootFiles.contains(relativePath)) return true;
    if (relativePath == '.DS_Store' || relativePath.startsWith('__MACOSX/')) {
      return true;
    }
    return _ignoredTopLevelDirectories.contains(relativePath.split('/').first);
  }

  String? _relativeToRoot(String path, String root) {
    if (root.isEmpty) return path;
    final prefix = '$root/';
    if (!path.startsWith(prefix)) return null;
    return path.substring(prefix.length);
  }

  String _decodeText(String path, ArchiveFile file) {
    final content = _tryDecodeText(file);
    if (content == null) {
      throw FormatException('Expected UTF-8 text file: $path');
    }
    return content;
  }

  String? _tryDecodeText(ArchiveFile file) {
    final bytes = file.content;
    if (bytes.any((value) => value == 0)) return null;
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  String _normalizeArchivePath(String rawPath) {
    var value = rawPath.replaceAll('\\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }

    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
      throw FormatException('ZIP contains an absolute path: $rawPath');
    }

    final segments = value.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.any((part) => part == '.' || part == '..')) {
      throw FormatException('ZIP contains an unsafe path: $rawPath');
    }
    return segments.join('/');
  }
}
