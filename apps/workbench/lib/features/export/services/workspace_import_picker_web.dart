import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_system_access_api/file_system_access_api.dart';

const bool supportsWorkspaceImportPicker = true;
const bool supportsWorkspaceDirectoryPicker = true;

// Keep these exclusions aligned with FlutterProjectDirectoryImportService.
// With File System Access we can skip these directories before Chrome walks
// into them, which avoids enumerating huge generated trees such as node_modules.
const Set<String> _ignoredDirectoryNames = <String>{
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

const Set<String> _ignoredRootFileNames = <String>{
  '.metadata',
  '.packages',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.DS_Store',
};

const int _maxImportedFiles = 6000;
const int _maxSingleFileBytes = 25 * 1024 * 1024;
const int _maxImportedBytes = 120 * 1024 * 1024;
const int _directoryReadBatchSize = 12;

Future<Uint8List?> pickWorkspaceImport() async {
  final input = html.FileUploadInputElement()
    ..accept = '.applykit,.flutterpractice,.zip,application/zip';

  final changed = input.onChange.first;
  input.click();
  await changed;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  return _readFile(files.first);
}

Future<List<({String path, Uint8List bytes})>?> pickWorkspaceDirectory() async {
  if (_supportsFileSystemAccessDirectoryPicker) {
    return _pickWorkspaceDirectoryWithFileSystemAccess();
  }

  return _pickWorkspaceDirectoryWithLegacyInput();
}

bool get _supportsFileSystemAccessDirectoryPicker => FileSystemAccess.supported;

Future<List<({String path, Uint8List bytes})>?>
    _pickWorkspaceDirectoryWithFileSystemAccess() async {
  late final FileSystemDirectoryHandle rootHandle;
  try {
    rootHandle = await html.window.showDirectoryPicker(
      mode: PermissionMode.read,
    );
  } on AbortError {
    return null;
  }

  final rootName = rootHandle.name.trim();
  final selected = <({String path, FileSystemFileHandle handle})>[];
  final enumeratedGitMetadata =
      <({String path, FileSystemFileHandle handle})>[];

  await _collectDirectoryHandles(
    rootHandle,
    prefix: rootName,
    selected: selected,
    gitMetadata: enumeratedGitMetadata,
  );

  final portableFiles = await _readFileSystemHandles(selected);
  final discoveredGitMetadata =
      await _readFileSystemHandles(enumeratedGitMetadata);
  final directGitMetadata = await _readRootGitMetadata(
    rootHandle,
    rootName: rootName,
  );

  final gitMetadataByPath = <String, Uint8List>{};
  for (final entry in <({String path, Uint8List bytes})>[
    ...discoveredGitMetadata,
    ...directGitMetadata,
  ]) {
    gitMetadataByPath[entry.path] = entry.bytes;
  }

  return <({String path, Uint8List bytes})>[
    ...portableFiles,
    for (final entry in gitMetadataByPath.entries)
      (path: entry.key, bytes: entry.value),
  ];
}

Future<List<({String path, Uint8List bytes})>> _readRootGitMetadata(
  FileSystemDirectoryHandle rootHandle, {
  required String rootName,
}) async {
  late final FileSystemDirectoryHandle gitHandle;
  try {
    gitHandle = await rootHandle.getDirectoryHandle('.git');
  } catch (_) {
    return const <({String path, Uint8List bytes})>[];
  }

  final result = <({String path, Uint8List bytes})>[];
  for (final name in const <String>['config', 'HEAD']) {
    try {
      final handle = await gitHandle.getFileHandle(name);
      final file = await handle.getFile();
      if (file.size > 256 * 1024) continue;
      final prefix = rootName.isEmpty ? '' : '$rootName/';
      result.add(
        (
          path: '${prefix}.git/$name',
          bytes: await _readFile(file),
        ),
      );
    } catch (_) {
      // Git metadata is optional. Failure to read one metadata file must not
      // block opening the user's project folder.
    }
  }

  return result;
}

Future<void> _collectDirectoryHandles(
  FileSystemDirectoryHandle directoryHandle, {
  required String prefix,
  required List<({String path, FileSystemFileHandle handle})> selected,
  required List<({String path, FileSystemFileHandle handle})> gitMetadata,
}) async {
  await for (final handle in directoryHandle.values) {
    final name = handle.name.trim();
    if (name.isEmpty) continue;

    final path = prefix.isEmpty ? name : '$prefix/$name';

    if (handle.kind == FileSystemKind.directory) {
      final directory = handle as FileSystemDirectoryHandle;
      if (name == '.git' && _isRootGitDirectoryPath(path)) {
        await _collectRootGitMetadataHandles(
          directory,
          prefix: path,
          selected: gitMetadata,
        );
        continue;
      }
      if (_ignoredDirectoryNames.contains(name)) continue;
      await _collectDirectoryHandles(
        directory,
        prefix: path,
        selected: selected,
        gitMetadata: gitMetadata,
      );
      continue;
    }

    if (handle.kind != FileSystemKind.file ||
        _shouldIgnoreDirectoryPath(path)) {
      continue;
    }

    if (selected.length >= _maxImportedFiles) {
      throw const FormatException(
        'Project contains more than 6000 portable files.',
      );
    }

    selected.add((path: path, handle: handle as FileSystemFileHandle));
  }
}

Future<void> _collectRootGitMetadataHandles(
  FileSystemDirectoryHandle gitHandle, {
  required String prefix,
  required List<({String path, FileSystemFileHandle handle})> selected,
}) async {
  await for (final handle in gitHandle.values) {
    final name = handle.name.trim();
    if (name != 'config' && name != 'HEAD') continue;
    if (handle.kind != FileSystemKind.file) continue;

    selected.add(
      (
        path: '$prefix/$name',
        handle: handle as FileSystemFileHandle,
      ),
    );
  }
}

bool _isRootGitDirectoryPath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return segments.length == 2 && segments.last == '.git';
}

Future<List<({String path, Uint8List bytes})>> _readFileSystemHandles(
  List<({String path, FileSystemFileHandle handle})> selected,
) async {
  final result = <({String path, Uint8List bytes})>[];
  var selectedBytes = 0;

  for (var start = 0;
      start < selected.length;
      start += _directoryReadBatchSize) {
    final end =
        (start + _directoryReadBatchSize).clamp(0, selected.length).toInt();
    final batch = selected.sublist(start, end);

    final files = await Future.wait(
      batch.map((entry) => entry.handle.getFile()),
    );

    for (var index = 0; index < batch.length; index += 1) {
      final entry = batch[index];
      final file = files[index];

      if (file.size > _maxSingleFileBytes) {
        throw FormatException(
          'File is larger than the 25 MB per-file limit: ${entry.path}',
        );
      }

      selectedBytes += file.size;
      if (selectedBytes > _maxImportedBytes) {
        throw const FormatException(
          'Project is larger than the 120 MB folder-import limit.',
        );
      }

      result.add((path: entry.path, bytes: await _readFile(file)));
    }
  }

  return result;
}

Future<List<({String path, Uint8List bytes})>?>
    _pickWorkspaceDirectoryWithLegacyInput() async {
  final input = html.FileUploadInputElement()..multiple = true;

  input.attributes['webkitdirectory'] = '';
  input.attributes['directory'] = '';
  final changed = input.onChange.first;
  input.click();
  await changed;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final selected = <({String path, html.File file})>[];
  var selectedBytes = 0;

  for (final file in files) {
    final path = _directoryPath(file);
    final isGitMetadata = _isRootGitMetadataPath(path);
    if (!isGitMetadata && _shouldIgnoreDirectoryPath(path)) continue;

    if (selected.length >= _maxImportedFiles) {
      throw const FormatException(
        'Project contains more than 6000 portable files.',
      );
    }
    if (file.size > _maxSingleFileBytes) {
      throw FormatException(
        'File is larger than the 25 MB per-file limit: $path',
      );
    }

    selectedBytes += file.size;
    if (selectedBytes > _maxImportedBytes) {
      throw const FormatException(
        'Project is larger than the 120 MB folder-import limit.',
      );
    }

    selected.add((path: path, file: file));
  }

  final result = <({String path, Uint8List bytes})>[];
  for (var start = 0;
      start < selected.length;
      start += _directoryReadBatchSize) {
    final end =
        (start + _directoryReadBatchSize).clamp(0, selected.length).toInt();
    final batch = selected.sublist(start, end);
    final bytes = await Future.wait(
      batch.map((entry) => _readFile(entry.file)),
    );

    for (var index = 0; index < batch.length; index += 1) {
      result.add((path: batch[index].path, bytes: bytes[index]));
    }
  }

  return result;
}

String _directoryPath(html.File file) {
  final relativePath = file.relativePath?.trim();
  final source =
      relativePath == null || relativePath.isEmpty ? file.name : relativePath;
  return source.replaceAll('\\', '/');
}

bool _isRootGitMetadataPath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.length < 2 || segments.length > 3) return false;
  return segments[segments.length - 2] == '.git' &&
      (segments.last == 'config' || segments.last == 'HEAD');
}

bool _shouldIgnoreDirectoryPath(String path) {
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return true;

  if (segments.any(_ignoredDirectoryNames.contains)) return true;

  // File System Access and webkitdirectory both include the selected root in
  // the paths passed to the importer.
  if (segments.length <= 2 && _ignoredRootFileNames.contains(segments.last)) {
    return true;
  }

  return false;
}

Future<Uint8List> _readFile(html.File file) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  final result = reader.result;
  if (result is ByteBuffer) return Uint8List.view(result);
  if (result is Uint8List) return result;

  throw FormatException('Unable to read local file: ${file.name}');
}
