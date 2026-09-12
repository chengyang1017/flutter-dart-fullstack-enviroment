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

  static WorkspacePersistence? _runtimePersistence;

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

  /// Raw browser persistence used as the local cache beneath cloud storage.
  static HiveWorkspacePersistence? localFromOpenBoxes() {
    if (!Hive.isBoxOpen(snapshotBoxName) || !Hive.isBoxOpen(libraryBoxName)) {
      return null;
    }

    return HiveWorkspacePersistence(
      snapshotBox: Hive.box<dynamic>(snapshotBoxName),
      libraryBox: Hive.box<dynamic>(libraryBoxName),
    );
  }

  /// Normal application persistence boundary.
  ///
  /// When cloud storage is configured this returns the cloud-backed adapter;
  /// otherwise it falls back to the browser Hive implementation.
  static WorkspacePersistence? tryFromOpenBoxes() =>
      _runtimePersistence ?? localFromOpenBoxes();

  static void useRuntimePersistence(WorkspacePersistence persistence) {
    _runtimePersistence = persistence;
  }

  static void clearRuntimePersistence() {
    _runtimePersistence = null;
  }

  /// Removes the browser cache when switching authenticated accounts.
  ///
  /// Remote storage remains authoritative, so clearing these boxes never
  /// deletes cloud projects. It prevents one account from seeing another
  /// account's stale local project metadata or snapshots on the same browser.
  static Future<void> clearLocalCache() async {
    clearRuntimePersistence();
    if (Hive.isBoxOpen(snapshotBoxName)) {
      await Hive.box<dynamic>(snapshotBoxName).clear();
    }
    if (Hive.isBoxOpen(libraryBoxName)) {
      await Hive.box<dynamic>(libraryBoxName).clear();
    }
  }
}
