import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-store-test-');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('persists source documents and isolates users', () async {
    final store = FileWorkspaceStore(temp);
    final created = await store.createWorkspace(
      userId: 'alice',
      project: _project('workspace-a'),
      snapshot: _snapshot('first'),
    );

    expect(created['revision'], 'r1');
    expect((created['snapshot'] as Map)['marker'], 'first');
    expect(
      (await store.loadCatalog('alice'))['revision'],
      'c1',
    );
    expect(
      (await store.loadCatalog('bob'))['projects'],
      isEmpty,
    );
    expect(await store.loadWorkspace('bob', 'workspace-a'), isNull);

    final reopened = FileWorkspaceStore(temp);
    final restored = await reopened.loadWorkspace('alice', 'workspace-a');
    expect(restored, isNotNull);
    expect((restored!['snapshot'] as Map)['marker'], 'first');
  });

  test('save uses optimistic revisions and delete updates catalog', () async {
    final store = FileWorkspaceStore(temp);
    await store.createWorkspace(
      userId: 'alice',
      project: _project('workspace-a'),
      snapshot: _snapshot('first'),
    );

    final saved = await store.saveWorkspace(
      userId: 'alice',
      workspaceId: 'workspace-a',
      project: _project('workspace-a'),
      snapshot: _snapshot('second'),
      expectedRevision: 'r1',
    );
    expect(saved['revision'], 'r2');

    await expectLater(
      store.saveWorkspace(
        userId: 'alice',
        workspaceId: 'workspace-a',
        project: _project('workspace-a'),
        snapshot: _snapshot('stale'),
        expectedRevision: 'r1',
      ),
      throwsA(
        isA<WorkspaceRevisionMismatch>()
            .having((error) => error.expectedRevision, 'expected', 'r1')
            .having((error) => error.actualRevision, 'actual', 'r2'),
      ),
    );

    final catalog = await store.deleteWorkspace(
      userId: 'alice',
      workspaceId: 'workspace-a',
      expectedRevision: 'r2',
    );
    expect(catalog['revision'], 'c3');
    expect(catalog['projects'], isEmpty);
    expect(catalog['deletedWorkspaceIds'], contains('workspace-a'));
    expect(await store.loadWorkspace('alice', 'workspace-a'), isNull);

    await expectLater(
      store.createWorkspace(
        userId: 'alice',
        project: _project('workspace-a'),
        snapshot: _snapshot('resurrected'),
      ),
      throwsA(isA<WorkspaceDeleted>()),
    );
  });

  test('catalog cleanup removes expired temporary Workspaces only', () async {
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = FileWorkspaceStore(
      temp,
      temporaryWorkspaceTtl: const Duration(hours: 24),
      clock: () => now,
    );

    await store.createWorkspace(
      userId: 'alice',
      project: _project(
        'expired-temp',
        lifecycle: 'temporary',
        updatedAt: now.subtract(const Duration(hours: 25)),
      ),
      snapshot: _snapshot('expired'),
    );
    await store.createWorkspace(
      userId: 'alice',
      project: _project(
        'fresh-temp',
        lifecycle: 'temporary',
        updatedAt: now.subtract(const Duration(hours: 23)),
      ),
      snapshot: _snapshot('fresh'),
    );
    await store.createWorkspace(
      userId: 'alice',
      project: _project(
        'old-saved',
        lifecycle: 'saved',
        updatedAt: now.subtract(const Duration(days: 30)),
      ),
      snapshot: _snapshot('saved'),
    );

    final catalog = await store.loadCatalog('alice');
    final ids = (catalog['projects'] as List)
        .cast<Map>()
        .map((project) => project['id'])
        .toList();

    expect(ids, containsAll(<String>['fresh-temp', 'old-saved']));
    expect(ids, isNot(contains('expired-temp')));
    expect(catalog['revision'], 'c4');
    expect(await store.loadWorkspace('alice', 'expired-temp'), isNull);
    expect(await store.loadWorkspace('alice', 'fresh-temp'), isNotNull);
    expect(await store.loadWorkspace('alice', 'old-saved'), isNotNull);
  });

  test('temporary Workspace TTL must be positive', () {
    expect(
      () => FileWorkspaceStore(
        temp,
        temporaryWorkspaceTtl: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}

Map<String, dynamic> _project(
  String id, {
  String lifecycle = 'saved',
  DateTime? updatedAt,
}) {
  final updated = updatedAt ?? DateTime.utc(2026, 9, 3);
  return <String, dynamic>{
    'id': id,
    'name': id,
    'storageKey': 'workspace:$id',
    'kind': 'practice',
    'lifecycle': lifecycle,
    'createdAt': '2026-09-03T00:00:00.000Z',
    'updatedAt': updated.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _snapshot(String marker) => <String, dynamic>{
      'formatVersion': 2,
      'entries': <Object>[],
      'baseEntries': <Object>[],
      'openFiles': <Object>[],
      'activePath': '',
      'nextId': 1,
      'savedAt': '2026-09-03T00:00:00.000Z',
      'expandedDirectoryIds': <Object>[],
      'editorStates': <String, Object?>{},
      'marker': marker,
    };
