import 'dart:typed_data';

import 'workspace_import_picker_stub.dart'
    if (dart.library.html) 'workspace_import_picker_web.dart' as implementation;

typedef WorkspacePickedFile = ({
  String path,
  Uint8List bytes,
});

bool get supportsWorkspaceImportPicker =>
    implementation.supportsWorkspaceImportPicker;

bool get supportsWorkspaceDirectoryPicker =>
    implementation.supportsWorkspaceDirectoryPicker;

Future<Uint8List?> pickWorkspaceImport() =>
    implementation.pickWorkspaceImport();

Future<List<WorkspacePickedFile>?> pickWorkspaceDirectory() =>
    implementation.pickWorkspaceDirectory();
