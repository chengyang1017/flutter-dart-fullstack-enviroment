import 'dart:html' as html;
import 'dart:typed_data';

const bool supportsWorkspaceImportPicker = true;

Future<Uint8List?> pickWorkspaceImport() async {
  final input = html.FileUploadInputElement()
    ..accept = '.applykit,.flutterpractice,.zip,application/zip';

  input.click();

  await input.onChange.first;

  final files = input.files;

  if (files == null || files.isEmpty) {
    return null;
  }

  final reader = html.FileReader();

  reader.readAsArrayBuffer(files.first);

  await reader.onLoad.first;

  final result = reader.result;

  if (result is ByteBuffer) {
    return Uint8List.view(result);
  }

  if (result is Uint8List) {
    return result;
  }

  throw const FormatException(
    'Unable to read workspace package.',
  );
}