import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_change.dart';
import '../models/export_manifest.dart';

class WorkspaceImportService {
  const WorkspaceImportService();

  ExportManifest apply(
    Uint8List bytes,
    WorkspaceController workspace,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.files.where(
      (file) => file.isFile && file.name == 'manifest.json',
    );
    if (manifestFile.length != 1) {
      throw const FormatException(
        'Workspace package must contain exactly one manifest.json.',
      );
    }

    final manifestJson = jsonDecode(
      utf8.decode(manifestFile.single.content),
    );
    if (manifestJson is! Map) {
      throw const FormatException('Invalid manifest.json.');
    }

    final manifest = ExportManifest.fromJson(
      Map<String, dynamic>.from(manifestJson),
    );
    _validateManifest(manifest);

    final payloads = <String, String>{};
    for (final path in manifest.payloadFiles) {
      final matches = archive.files.where(
        (file) => file.isFile && file.name == path,
      );
      if (matches.length != 1) {
        throw FormatException('Missing payload file: $path');
      }
      payloads[path] = utf8.decode(matches.single.content);
    }

    workspace.resetWorkspace();

    final relocations = manifest.changes
        .where(
          (change) =>
              change.type == WorkspaceChangeType.moved ||
              change.type == WorkspaceChangeType.renamed,
        )
        .toList();
    final createdDirectories = manifest.changes
        .where(
          (change) =>
              change.type == WorkspaceChangeType.created &&
              !manifest.payloadFiles.contains(change.path),
        )
        .toList();

    _applyStructure(
      workspace,
      relocations: relocations,
      createdDirectories: createdDirectories,
    );

    for (final change in manifest.changes.where(
      (change) =>
          change.type == WorkspaceChangeType.created &&
          manifest.payloadFiles.contains(change.path),
    )) {
      if (workspace.entryAt(change.path) != null) continue;
      final parent = _parentPath(change.path);
      _requireDirectory(workspace, parent, change.path);
      workspace.createFile(
        parent,
        _name(change.path),
        content: payloads[change.path] ?? '',
      );
    }

    for (final change in manifest.changes.where(
      (change) => change.type == WorkspaceChangeType.modified,
    )) {
      final entry = workspace.entryAt(change.path);
      if (entry == null || !entry.isFile) {
        throw FormatException(
          'Cannot apply modified file: ${change.path}',
        );
      }
      final content = payloads[change.path];
      if (content == null) {
        throw FormatException(
          'Missing modified file payload: ${change.path}',
        );
      }
      workspace.updateFileContent(change.path, content);
    }

    for (final change in manifest.changes.where(
      (change) => change.type == WorkspaceChangeType.deleted,
    )) {
      final path = _currentPathForDeleted(
        change.path,
        relocations,
        workspace,
      );
      workspace.deleteEntry(path);
    }

    return manifest;
  }

  void _applyStructure(
    WorkspaceController workspace, {
    required List<WorkspaceChange> relocations,
    required List<WorkspaceChange> createdDirectories,
  }) {
    final pendingMoves = [...relocations];
    final pendingDirectories = [...createdDirectories];

    while (pendingMoves.isNotEmpty || pendingDirectories.isNotEmpty) {
      var progressed = false;

      for (final change in [...pendingMoves]) {
        final previousPath = change.previousPath;
        if (previousPath == null) {
          throw FormatException(
            'Relocation is missing previousPath: ${change.path}',
          );
        }

        if (workspace.entryAt(change.path) != null) {
          pendingMoves.remove(change);
          progressed = true;
          continue;
        }

        final source = workspace.entryAt(previousPath);
        if (source == null) continue;

        final parent = _parentPath(change.path);
        if (parent.isNotEmpty &&
            workspace.entryAt(parent)?.isDirectory != true) {
          continue;
        }

        workspace.relocateEntry(previousPath, change.path);
        pendingMoves.remove(change);
        progressed = true;
      }

      for (final change in [...pendingDirectories]) {
        if (workspace.entryAt(change.path) != null) {
          pendingDirectories.remove(change);
          progressed = true;
          continue;
        }

        final parent = _parentPath(change.path);
        if (parent.isNotEmpty &&
            workspace.entryAt(parent)?.isDirectory != true) {
          continue;
        }

        workspace.createDirectory(parent, _name(change.path));
        pendingDirectories.remove(change);
        progressed = true;
      }

      if (!progressed) {
        final blocked = [
          ...pendingMoves.map((change) => change.path),
          ...pendingDirectories.map((change) => change.path),
        ].join(', ');
        throw FormatException(
          'Cannot rebuild workspace structure: $blocked',
        );
      }
    }
  }

  String _currentPathForDeleted(
    String originalPath,
    List<WorkspaceChange> relocations,
    WorkspaceController workspace,
  ) {
    if (workspace.entryAt(originalPath) != null) {
      return originalPath;
    }

    final candidates = relocations.where((change) {
      final previous = change.previousPath;
      return previous != null &&
          (originalPath == previous || originalPath.startsWith('$previous/'));
    }).toList()
      ..sort((a, b) =>
          (b.previousPath?.length ?? 0).compareTo(a.previousPath?.length ?? 0));

    for (final relocation in candidates) {
      final previous = relocation.previousPath!;
      final suffix = originalPath.substring(previous.length);
      final candidate = '${relocation.path}$suffix';
      if (workspace.entryAt(candidate) != null) {
        return candidate;
      }
    }

    return originalPath;
  }

  void _validateManifest(ExportManifest manifest) {
    if (manifest.formatVersion != 2) {
      throw FormatException(
        'Unsupported workspace package version: ${manifest.formatVersion}',
      );
    }

    const supportedProjectTypes = <String>{
      'flutter',
      'flutter-dart-frog',
      'flutter-serverpod-mini',
    };
    if (!supportedProjectTypes.contains(manifest.projectType) ||
        manifest.template != 'flutter-playground') {
      throw const FormatException(
        'This package is not a Flutter playground workspace.',
      );
    }
  }

  void _requireDirectory(
    WorkspaceController workspace,
    String parent,
    String child,
  ) {
    if (parent.isNotEmpty && workspace.entryAt(parent)?.isDirectory != true) {
      throw FormatException(
        'Missing parent directory for $child: $parent',
      );
    }
  }

  String _parentPath(String path) {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? '' : path.substring(0, separator);
  }

  String _name(String path) {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? path : path.substring(separator + 1);
  }
}
