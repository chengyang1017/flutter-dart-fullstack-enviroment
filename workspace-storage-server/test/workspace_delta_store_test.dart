import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  test('split storage patches only changed entry files', () async {
    final temp = await Directory.systemTemp.createTemp('workspace-delta-test-');
    addTearDown(() => temp.delete(recursive: true));

    final store = FileWorkspaceStore(temp);
    await store.createWorkspace(
      userId: 'alice',
      project: _project('workspace-a'),
      snapshot: _snapshot(),
    );

    final workspaceRoot = _workspaceRoot(temp, 'alice', 'workspace-a');
    final metaFile = File('${workspaceRoot.path}/meta.json');
    final entriesDirectory = Directory('${workspaceRoot.path}/entries');
    final legacyFile = _legacyDocumentFile(temp, 'alice', 'workspace-a');

    expect(await metaFile.exists(), isTrue);
    expect(await legacyFile.exists(), isFalse);

    final meta = jsonDecode(await metaFile.readAsString()) as Map;
    final manifest = meta['snapshot'] as Map;
    expect(manifest.containsKey('entries'), isFalse);
    expect(manifest.containsKey('baseEntries'), isFalse);

    final stableFile = File(
      '${entriesDirectory.path}/${_key('file-stable')}.json',
    );
    final deletedFile = File(
      '${entriesDirectory.path}/${_key('file-old')}.json',
    );
    final changedFile = File(
      '${entriesDirectory.path}/${_key('file-main')}.json',
    );
    final markerTime = DateTime.utc(2001, 2, 3, 4, 5, 6);
    await stableFile.setLastModified(markerTime);
    final stableModifiedBefore = await stableFile.lastModified();

    final result = await store.patchWorkspace(
      userId: 'alice',
      workspaceId: 'workspace-a',
      project: _project('workspace-a'),
      expectedRevision: 'r1',
      delta: _delta(),
    );

    expect(result, <String, dynamic>{'revision': 'r2'});
    expect(await deletedFile.exists(), isFalse);
    expect(await changedFile.exists(), isTrue);
    expect(await stableFile.lastModified(), stableModifiedBefore);

    final restored = await store.loadWorkspace('alice', 'workspace-a');
    final snapshot = restored!['snapshot'] as Map<String, dynamic>;
    final entries = (snapshot['entries'] as List<dynamic>)
        .cast<Map<dynamic, dynamic>>()
        .map((entry) => entry['id'])
        .toSet();
    expect(entries, <Object?>{'file-main', 'file-new', 'file-stable'});
    expect(snapshot['activePath'], 'lib/new.dart');
  });

  test('first PATCH migrates legacy full JSON storage once', () async {
    final temp = await Directory.systemTemp.createTemp('workspace-legacy-test-');
    addTearDown(() => temp.delete(recursive: true));

    final legacyFile = _legacyDocumentFile(temp, 'alice', 'workspace-a');
    await legacyFile.parent.create(recursive: true);
    await legacyFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'project': _project('workspace-a'),
        'snapshot': _snapshot(),
        'revision': 'r1',
      }),
    );

    final store = FileWorkspaceStore(temp);
    final result = await store.patchWorkspace(
      userId: 'alice',
      workspaceId: 'workspace-a',
      project: _project('workspace-a'),
      expectedRevision: 'r1',
      delta: _delta(),
    );

    expect(result, <String, dynamic>{'revision': 'r2'});
    expect(await legacyFile.exists(), isFalse);
    expect(
      await File(
        '${_workspaceRoot(temp, 'alice', 'workspace-a').path}/meta.json',
      ).exists(),
      isTrue,
    );

    final restored = await store.loadWorkspace('alice', 'workspace-a');
    expect(restored!['revision'], 'r2');
    final snapshot = restored['snapshot'] as Map<String, dynamic>;
    expect(snapshot['activePath'], 'lib/new.dart');
  });
}

Map<String, dynamic> _project(String id) => <String, dynamic>{
      'id': id,
      'name': id,
      'slug': id,
      'storageKey': 'workspace:$id',
      'kind': 'practice',
      'lifecycle': 'saved',
      'createdAt': '2026-09-09T00:00:00.000Z',
      'updatedAt': '2026-09-09T00:00:00.000Z',
    };

Map<String, dynamic> _snapshot() => <String, dynamic>{
      'formatVersion': 3,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'file-main',
          'path': 'lib/main.dart',
          'type': 'file',
          'content': 'void main() {}\n',
          'encoding': 'utf8',
        },
        <String, dynamic>{
          'id': 'file-old',
          'path': 'lib/old.dart',
          'type': 'file',
          'content': 'const old = true;\n',
          'encoding': 'utf8',
        },
        <String, dynamic>{
          'id': 'file-stable',
          'path': 'lib/stable.dart',
          'type': 'file',
          'content': 'const stable = true;\n',
          'encoding': 'utf8',
        },
      ],
      'baseEntries': <Map<String, dynamic>>[],
      'openFiles': <String>['lib/main.dart'],
      'activePath': 'lib/main.dart',
      'nextId': 4,
      'savedAt': '2026-09-09T00:00:00.000Z',
      'expandedDirectoryIds': <String>[],
      'editorStates': <String, Object?>{},
    };

Map<String, dynamic> _delta() => <String, dynamic>{
      'formatVersion': 1,
      'manifest': <String, dynamic>{
        'activePath': 'lib/new.dart',
        'openFiles': <String>['lib/new.dart'],
        'savedAt': '2026-09-09T02:00:00.000Z',
      },
      'entries': <String, dynamic>{
        'deleteIds': <String>['file-old'],
        'upsert': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'file-main',
            'path': 'lib/main.dart',
            'type': 'file',
            'content': 'void main() { print("changed"); }\n',
            'encoding': 'utf8',
          },
          <String, dynamic>{
            'id': 'file-new',
            'path': 'lib/new.dart',
            'type': 'file',
            'content': 'const newFile = true;\n',
            'encoding': 'utf8',
          },
        ],
      },
      'baseEntries': <String, dynamic>{
        'deleteIds': <String>[],
        'upsert': <Map<String, dynamic>>[],
      },
    };

Directory _workspaceRoot(Directory root, String userId, String workspaceId) =>
    Directory(
      '${root.path}/users/${_key(userId)}/workspaces/${_key(workspaceId)}',
    );

File _legacyDocumentFile(Directory root, String userId, String workspaceId) =>
    File(
      '${root.path}/users/${_key(userId)}/documents/${_key(workspaceId)}.json',
    );

String _key(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
