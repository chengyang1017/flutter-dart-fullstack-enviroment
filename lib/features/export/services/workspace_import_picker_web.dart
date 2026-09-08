import 'dart:html' as html;
import 'dart:typed_data';

const bool supportsWorkspaceImportPicker = true;
const bool supportsWorkspaceDirectoryPicker = true;

Future<Uint8List?> pickWorkspaceImport() async {
  final input = html.FileUploadInputElement()
    ..accept = '.applykit,.flutterpractice,.zip,application/zip';

  input.click();
  await input.onChange.first;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  return _readFile(files.first);
}

Future<List<({String path, Uint8List bytes})>?> pickWorkspaceDirectory() async {
  final input = html.FileUploadInputElement()
    ..multiple = true;

  input.attributes['webkitdirectory'] = '';
  input.attributes['directory'] = '';
  input.click();
  await input.onChange.first;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final result = <({String path, Uint8List bytes})>[];
  for (final file in files) {
    final relativePath = file.relativePath?.trim();
    final path = relativePath == null || relativePath.isEmpty
        ? file.name
        : relativePath;
    result.add((path: path, bytes: await _readFile(file)));
  }
  return result;
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
