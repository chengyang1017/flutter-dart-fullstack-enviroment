import 'package:hive/hive.dart';

import 'hive_workspace_project_catalog_store.dart';
import 'hive_workspace_snapshot_store.dart';
import 'workspace_persistence.dart';
import 'workspace_project_catalog_store.dart';
import 'workspace_snapshot_store.dart';

class HiveWorkspacePersistence implements WorkspacePersistence {
  HiveWorkspacePersistence({
    required Box<dynamic> snapshotBox,
    required Box<dynamic> libraryBox,
  })  : catalogStore = HiveWorkspaceProjectCatalogStore(libraryBox),
        snapshotStore = HiveWorkspaceSnapshotStore(snapshotBox);

  static const snapshotBoxName = 'workspace_snapshots';
  static const libraryBoxName = 'workspace_library';

  @override
  final WorkspaceProjectCatalogStore catalogStore;

  @override
  final WorkspaceSnapshotStore snapshotStore;

  static Future<void> openBoxes() async {
    if (!Hive.isBoxOpen(snapshotBoxName)) {
      await Hive.openBox<dynamic>(snapshotBoxName);
    }
    if (!Hive.isBoxOpen(libraryBoxName)) {
      await Hive.openBox<dynamic>(libraryBoxName);
    }
  }

  static HiveWorkspacePersistence? tryFromOpenBoxes() {
    if (!Hive.isBoxOpen(snapshotBoxName) || !Hive.isBoxOpen(libraryBoxName)) {
      return null;
    }

    return HiveWorkspacePersistence(
      snapshotBox: Hive.box<dynamic>(snapshotBoxName),
      libraryBox: Hive.box<dynamic>(libraryBoxName),
    );
  }
}
