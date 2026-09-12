import 'dart:typed_data';

import 'export_manifest.dart';

class WorkspaceExportBundle {
  const WorkspaceExportBundle({
    required this.fileName,
    required this.bytes,
    required this.manifest,
  });

  final String fileName;
  final Uint8List bytes;
  final ExportManifest manifest;
}
