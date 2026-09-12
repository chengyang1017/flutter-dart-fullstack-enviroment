import 'dart:typed_data';

import 'workspace_export_download_stub.dart'
    if (dart.library.html) 'workspace_export_download_web.dart'
    as implementation;

bool get supportsWorkspaceExportDownload =>
    implementation.supportsWorkspaceExportDownload;

Future<void> downloadWorkspaceExport(
  Uint8List bytes,
  String fileName,
) =>
    implementation.downloadWorkspaceExport(bytes, fileName);
