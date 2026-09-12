import '../../workspace/models/workspace_snapshot.dart';

class FlutterProjectImportBundle {
  const FlutterProjectImportBundle({
    required this.projectName,
    required this.snapshot,
    required this.importedFileCount,
    required this.ignoredFileCount,
  });

  final String projectName;
  final WorkspaceSnapshot snapshot;
  final int importedFileCount;
  final int ignoredFileCount;
}
