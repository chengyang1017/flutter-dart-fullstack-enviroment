import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../models/export_manifest.dart';
import '../models/workspace_export_bundle.dart';

class WorkspaceExportService {
  const WorkspaceExportService();

  WorkspaceExportBundle build(
    WorkspaceController workspace, {
    DateTime? exportedAt,
  }) {
    final snapshot = workspace.createSnapshot();

    final currentFilePaths = snapshot.entries
        .where((entry) => entry.isFile)
        .map((entry) => entry.path)
        .toSet();

    final baseFilePaths = snapshot.baseEntries
        .where((entry) => entry.isFile)
        .map((entry) => entry.path)
        .toSet();

    final filteredChanges = workspace.changes.where((change) {
      switch (change.type.name) {
        case 'created':
        case 'modified':
          return currentFilePaths.contains(change.path);

        case 'deleted':
          return baseFilePaths.contains(change.path);

        case 'renamed':
        case 'moved':
          return currentFilePaths.contains(change.path) ||
              (change.previousPath != null &&
                  baseFilePaths.contains(change.previousPath));

        default:
          return false;
      }
    }).toList(growable: false);

    final renamedOrMovedPaths = filteredChanges
        .where(
          (change) =>
              change.type.name == 'renamed' ||
              change.type.name == 'moved',
        )
        .map((change) => change.path)
        .toSet();

    final changes = filteredChanges
        .where(
          (change) =>
              !(change.type.name == 'modified' &&
                  renamedOrMovedPaths.contains(change.path)),
        )
        .toList(growable: false);

    final changedPaths = changes
        .where(
          (change) => change.type.name != 'deleted',
        )
        .map((change) => change.path)
        .toSet();

    final payloadEntries = snapshot.entries
        .where(
          (entry) =>
              entry.isFile &&
              changedPaths.contains(entry.path),
        )
        .toList()
      ..sort(
        (a, b) => a.path.compareTo(b.path),
      );

    final payloadFiles = payloadEntries
        .map((entry) => entry.path)
        .toList(growable: false);

    final basePayloadPaths = <String>{};

    for (final change in changes) {
      switch (change.type.name) {
        case 'modified':
        case 'deleted':
          basePayloadPaths.add(change.path);
          break;

        case 'renamed':
        case 'moved':
          final previousPath = change.previousPath;

          if (previousPath != null) {
            basePayloadPaths.add(previousPath);
          }
          break;

        case 'created':
          break;
      }
    }

    final basePayloadEntries = snapshot.baseEntries
        .where(
          (entry) =>
              entry.isFile &&
              basePayloadPaths.contains(entry.path),
        )
        .toList()
      ..sort(
        (a, b) => a.path.compareTo(b.path),
      );

    final basePayloadFiles = basePayloadEntries
        .map((entry) => entry.path)
        .toList(growable: false);

    final projectType = _projectType(workspace);
    final projectName = _projectName(workspace);
    final flutterPlatforms = _flutterPlatforms(workspace);

    final manifest = ExportManifest(
      exportedAt: exportedAt ?? DateTime.now(),
      changes: changes,
      payloadFiles: payloadFiles,
      basePayloadFiles: basePayloadFiles,
      projectType: projectType,
      projectName: projectName,
      flutterPlatforms: flutterPlatforms,
      template: 'flutter-playground',
    );

    final archive = Archive();

    _addTextFile(
      archive,
      'manifest.json',
      const JsonEncoder.withIndent('  ').convert(
        manifest.toJson(),
      ),
    );

    for (final entry in payloadEntries) {
      if (entry.isBinary) {
        final bytes = entry.bytes;

        archive.addFile(
          ArchiveFile(
            entry.path,
            bytes.length,
            bytes,
          ),
        );
      } else {
        _addTextFile(
          archive,
          entry.path,
          entry.content,
        );
      }
    }

    for (final entry in basePayloadEntries) {
      final archivePath =
          '.applykit/base/${entry.path}';

      if (entry.isBinary) {
        final bytes = entry.bytes;

        archive.addFile(
          ArchiveFile(
            archivePath,
            bytes.length,
            bytes,
          ),
        );
      } else {
        _addTextFile(
          archive,
          archivePath,
          entry.content,
        );
      }
    }

    final encoded = ZipEncoder().encodeBytes(archive);

    final stamp = manifest.exportedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    return WorkspaceExportBundle(
      fileName: 'applykit-$stamp.applykit',
      bytes: Uint8List.fromList(encoded),
      manifest: manifest,
    );
  }

  List<String> _flutterPlatforms(
    WorkspaceController workspace,
  ) {
    const platformOrder = <String>[
      'android',
      'ios',
      'web',
      'windows',
      'macos',
      'linux',
    ];

    final platforms = platformOrder
        .where(
          (platform) => workspace.entries.any(
            (entry) =>
                entry.path == platform ||
                entry.path.startsWith('$platform/'),
          ),
        )
        .toList(growable: false);

    if (platforms.isEmpty) {
      return const ['web'];
    }

    return platforms;
  }

  String _projectName(
    WorkspaceController workspace,
  ) {
    final pubspec = workspace.entryAt('pubspec.yaml');

    if (pubspec == null ||
        !pubspec.isFile ||
        pubspec.isBinary) {
      throw const FormatException(
        'Flutter Workspace is missing pubspec.yaml.',
      );
    }

    final match = RegExp(
      r'^\s*name\s*:\s*([a-z][a-z0-9_]*)\s*$',
      multiLine: true,
    ).firstMatch(pubspec.content);

    if (match == null) {
      throw const FormatException(
        'pubspec.yaml does not contain a valid project name.',
      );
    }

    return match.group(1)!;
  }

  String _projectType(
    WorkspaceController workspace,
  ) {
    final hasServerpod = workspace
            .entryAt(
              'serverpod/practice_server/config/generator.yaml',
            )
            ?.isFile ==
        true;

    if (hasServerpod) {
      return 'flutter-serverpod-mini';
    }

    final hasDartFrog =
        workspace.entryAt('backend/pubspec.yaml')?.isFile == true &&
            workspace.entries.any(
              (entry) =>
                  entry.isFile &&
                  entry.path.startsWith('backend/routes/') &&
                  entry.path.endsWith('.dart'),
            );

    if (hasDartFrog) {
      return 'flutter-dart-frog';
    }

    return 'flutter';
  }

  void _addTextFile(
    Archive archive,
    String path,
    String content,
  ) {
    final bytes = utf8.encode(content);

    archive.addFile(
      ArchiveFile(
        path,
        bytes.length,
        bytes,
      ),
    );
  }
}