import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_hydrator.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';

void main() {
  test('remote Workspace document round-trips metadata snapshot and revision', () {
    final document = WorkspaceRemoteDocument(
      project: _project('workspace-a'),
      snapshot: _snapshot('A'),
      revision: 'opaque-revision-7',
    );

    final restored = WorkspaceRemoteDocument.fromJson(document.toJson());

    expect(restored.project.id, 'workspace-a');
    expect(restored.snapshot.entries.single.content, 'A');
    expect(restored.revision, 'opaque-revision-7');
  });

  test('hydrator loads catalog then only the preferred Workspace', () async {
    final remote = _FakeRemotePersistence(
      projects: [_project('workspace-a'), _project('workspace-b')],
      documents: {
        'workspace-a': _document('workspace-a', 'A'),
        'workspace-b': _document('workspace-b', 'B'),
      },
    );

    final result = await WorkspaceRemoteHydrator(remote).hydrate(
      preferredWorkspaceId: 'workspace-b',
    );

    expect(result.activeDocument?.project.id, 'workspace-b');
    expect(remote.loadedWorkspaceIds, ['workspace-b']);
  });

  test('hydrator falls back to first catalog Workspace for stale preference', () async {
    final remote = _FakeRemotePersistence(
      projects: [_project('workspace-a'), _project('workspace-b')],
      documents: {
        'workspace-a': _document('workspace-a', 'A'),
        'workspace-b': _document('workspace-b', 'B'),
      },
    );

    final result = await WorkspaceRemoteHydrator(remote).hydrate(
      preferredWorkspaceId: 'deleted-workspace',
    );

    expect(result.activeDocument?.project.id, 'workspace-a');
    expect(remote.loadedWorkspaceIds, ['workspace-a']);
  });

  test('empty remote catalog hydrates without requesting source files', () async {
    final remote = _FakeRemotePersistence(
      projects: const [],
      documents: const {},
    );

    final result = await WorkspaceRemoteHydrator(remote).hydrate();

    expect(result.activeDocument, isNull);
    expect(remote.loadedWorkspaceIds, isEmpty);
  });

  test('catalog pointing at a missing remote Workspace fails hydration', () async {
    final remote = _FakeRemotePersistence(
      projects: [_project('workspace-a')],
      documents: const {},
    );

    await expectLater(
      WorkspaceRemoteHydrator(remote).hydrate(),
      throwsA(isA<StateError>()),
    );
  });
}

WorkspaceProject _project(String id) {
  final now = DateTime.utc(2026, 9, 3);
  return WorkspaceProject(
    id: id,
    name: id,
    storageKey: 'workspace:$id',
    kind: WorkspaceProjectKind.practice,
    lifecycle: WorkspaceLifecycle.saved,
    createdAt: now,
    updatedAt: now,
  );
}

WorkspaceSnapshot _snapshot(String content) => WorkspaceSnapshot(
      entries: [
        WorkspaceEntry(
          id: 'file-1',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: content,
        ),
      ],
      baseEntries: const [],
      openFiles: const ['lib/main.dart'],
      activePath: 'lib/main.dart',
      nextId: 2,
      savedAt: DateTime.utc(2026, 9, 3),
    );

WorkspaceRemoteDocument _document(String id, String content) =>
    WorkspaceRemoteDocument(
      project: _project(id),
      snapshot: _snapshot(content),
      revision: 'revision-$id',
    );

class _FakeRemotePersistence implements WorkspaceRemotePersistence {
  _FakeRemotePersistence({
    required List<WorkspaceProject> projects,
    required this.documents,
  }) : catalog = WorkspaceRemoteCatalog(
          projects: projects,
          revision: 'catalog-1',
        );

  @override
  final WorkspaceIdentity identity =
      const WorkspaceIdentity(userId: 'test-user');
  final WorkspaceRemoteCatalog catalog;
  final Map<String, WorkspaceRemoteDocument> documents;
  final List<String> loadedWorkspaceIds = [];

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() async => catalog;

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async {
    loadedWorkspaceIds.add(workspaceId);
    return documents[workspaceId];
  }

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) {
    throw UnimplementedError();
  }
}
