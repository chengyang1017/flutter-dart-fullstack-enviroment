import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/hive_workspace_snapshot_store.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveWorkspaceSnapshotStore store;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('workspace-hive-split');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('workspace_hive_split_test');
    store = HiveWorkspaceSnapshotStore(box);
  });

  tearDown(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  test('migrates a legacy whole snapshot on the first save', () async {
    const key = 'workspace-project-a';
    final legacy = _snapshot(
      savedAt: DateTime.utc(2026, 9, 9, 1),
      mainContent: 'void main() {}',
    );
    await box.put(key, legacy.toJson());

    expect(store.load(key)?.entries.single.content, 'void main() {}');

    final updated = _snapshot(
      savedAt: DateTime.utc(2026, 9, 9, 2),
      mainContent: 'void main() { print("ready"); }',
    );
    await store.save(key, updated);

    expect(box.containsKey(key), isFalse);
    expect(store.load(key)?.entries.single.content, contains('ready'));
    expect(
      box.keys.whereType<String>().any((value) => value.contains(':meta:')),
      isTrue,
    );
  });

  test('rewrites only the changed entry plus the small manifest', () async {
    const key = 'workspace-project-b';
    final first = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'stable',
          path: 'lib/stable.dart',
          type: WorkspaceEntryType.file,
          content: 'const stable = true;',
        ),
        WorkspaceEntry(
          id: 'changed',
          path: 'lib/changed.dart',
          type: WorkspaceEntryType.file,
          content: 'const version = 1;',
        ),
      ],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>['lib/changed.dart'],
      activePath: 'lib/changed.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 1),
    );
    await store.save(key, first);

    final events = <BoxEvent>[];
    final subscription = box.watch().listen(events.add);

    final second = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'stable',
          path: 'lib/stable.dart',
          type: WorkspaceEntryType.file,
          content: 'const stable = true;',
        ),
        WorkspaceEntry(
          id: 'changed',
          path: 'lib/changed.dart',
          type: WorkspaceEntryType.file,
          content: 'const version = 2;',
        ),
      ],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>['lib/changed.dart'],
      activePath: 'lib/changed.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 2),
    );
    await store.save(key, second);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    final entryWrites = events.where((event) {
      final value = event.value;
      return value is Map && value['path'] is String;
    }).toList(growable: false);

    expect(
      entryWrites
          .where((event) => (event.value as Map)['path'] == 'lib/stable.dart'),
      isEmpty,
    );
    expect(
      entryWrites
          .where((event) => (event.value as Map)['path'] == 'lib/changed.dart'),
      hasLength(1),
    );
    expect(store.load(key)?.entries.last.content, 'const version = 2;');
  });

  test('deletes removed split entries and the whole split snapshot', () async {
    const key = 'workspace-project-c';
    final first = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'keep',
          path: 'lib/keep.dart',
          type: WorkspaceEntryType.file,
          content: 'const keep = true;',
        ),
        WorkspaceEntry(
          id: 'remove',
          path: 'lib/remove.dart',
          type: WorkspaceEntryType.file,
          content: 'const remove = true;',
        ),
      ],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>['lib/keep.dart'],
      activePath: 'lib/keep.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 1),
    );
    await store.save(key, first);
    final splitKeyCount = box.keys.length;

    final second = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'keep',
          path: 'lib/keep.dart',
          type: WorkspaceEntryType.file,
          content: 'const keep = true;',
        ),
      ],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>['lib/keep.dart'],
      activePath: 'lib/keep.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 2),
    );
    await store.save(key, second);

    expect(box.keys.length, splitKeyCount - 1);
    expect(store.load(key)?.entries.map((entry) => entry.id), <String>['keep']);

    await store.delete(key);
    expect(store.load(key), isNull);
    expect(box.keys, isEmpty);
  });
}

WorkspaceSnapshot _snapshot({
  required DateTime savedAt,
  required String mainContent,
}) {
  return WorkspaceSnapshot(
    entries: <WorkspaceEntry>[
      WorkspaceEntry(
        id: 'main',
        path: 'lib/main.dart',
        type: WorkspaceEntryType.file,
        content: mainContent,
      ),
    ],
    baseEntries: const <WorkspaceEntry>[],
    openFiles: const <String>['lib/main.dart'],
    activePath: 'lib/main.dart',
    nextId: 2,
    savedAt: savedAt,
  );
}
