import 'dart:html' as html;
import 'dart:typed_data';

const bool supportsWorkspaceExportDownload = true;

Future<void> downloadWorkspaceExport(
  Uint8List bytes,
  String fileName,
) async {
  final blob = html.Blob(
    [bytes],
    'application/zip',
  );
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
