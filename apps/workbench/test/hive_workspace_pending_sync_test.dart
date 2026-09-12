import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_ui_playground/features/workspace/services/hive_workspace_snapshot_store.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveWorkspaceSnapshotStore store;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('workspace-pending-sync');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('workspace_pending_sync_test');
    store = HiveWorkspaceSnapshotStore(box);
  });

  tearDown(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  test('pending cloud marker survives until explicitly cleared', () async {
    const key = 'workspace:cloud-app';

    expect(store.isPendingSync(key), isFalse);
    await store.markPendingSync(key);
    expect(store.isPendingSync(key), isTrue);

    await store.clearPendingSync(key);
    expect(store.isPendingSync(key), isFalse);
  });

  test('deleting a workspace also clears its pending marker', () async {
    const key = 'workspace:deleted-app';

    await store.markPendingSync(key);
    await store.delete(key);

    expect(store.isPendingSync(key), isFalse);
  });
}
