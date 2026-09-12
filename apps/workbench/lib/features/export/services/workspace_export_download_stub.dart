import 'dart:typed_data';

const bool supportsWorkspaceExportDownload = false;

Future<void> downloadWorkspaceExport(
  Uint8List bytes,
  String fileName,
) {
  throw UnsupportedError(
    'Portable workspace download is currently available in the web build.',
  );
}
