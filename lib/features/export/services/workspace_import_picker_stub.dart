import 'dart:typed_data';

const bool supportsWorkspaceImportPicker = false;
const bool supportsWorkspaceDirectoryPicker = false;

Future<Uint8List?> pickWorkspaceImport() async => null;

Future<List<({String path, Uint8List bytes})>?> pickWorkspaceDirectory() async =>
    null;
