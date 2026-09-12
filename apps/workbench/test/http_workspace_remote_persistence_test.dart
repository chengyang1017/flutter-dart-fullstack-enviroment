import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_remote_persistence.dart';
import 'package:flutter_ui_playground/features/workspace/services/http_workspace_remote_session_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP persistence sends bearer auth without client owner id', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'projects': <Object>[],
          'revision': 'c1',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final remote = HttpWorkspaceRemotePersistence(
      identity: const WorkspaceIdentity(userId: 'alice'),
      baseUri: Uri.parse('https://workspace.example/api/'),
      accessToken: 'alice-token',
      client: client,
    );

    final catalog = await remote.loadCatalog();

    expect(catalog.revision, 'c1');
    expect(captured.url.toString(), 'https://workspace.example/api/workspaces');
    expect(captured.headers['authorization'], 'Bearer alice-token');
    expect(captured.url.queryParameters.containsKey('ownerId'), isFalse);
    expect(captured.body.contains('alice'), isFalse);
  });

  test('HTTP persistence maps 404 Workspace loads to null', () async {
    final client = MockClient((request) async => http.Response('{}', 404));
    final remote = _remote(client);

    expect(await remote.loadWorkspace('missing'), isNull);
  });

  test('HTTP persistence maps structured 409 to revision conflict', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'code': 'revision_conflict',
          'workspaceId': 'workspace-a',
          'expectedRevision': 'r1',
          'actualRevision': 'r2',
        }),
        409,
      );
    });
    final remote = _remote(client);

    await expectLater(
      remote.saveWorkspace(
        project: _project('workspace-a'),
        snapshot: _snapshot(),
        expectedRevision: 'r1',
      ),
      throwsA(
        isA<WorkspaceRevisionConflict>()
            .having((error) => error.expectedRevision, 'expected', 'r1')
            .having((error) => error.actualRevision, 'actual', 'r2'),
      ),
    );
  });

  test('HTTP session provider binds remote to resolved auth session', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer session-token');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'projects': <Object>[],
          'revision': 'c0',
        }),
        200,
      );
    });
    final provider = HttpWorkspaceRemoteSessionProvider(
      baseUri: Uri.parse('https://workspace.example/'),
      client: client,
      resolveSession: () async => const WorkspaceRemoteAuthSession(
        identity: WorkspaceIdentity(userId: 'alice'),
        accessToken: 'session-token',
      ),
    );

    final remote = await provider.currentRemote();
    expect(remote?.identity.userId, 'alice');
    expect((await remote!.loadCatalog()).revision, 'c0');
  });

  test('HTTP session provider returns null while signed out', () async {
    final provider = HttpWorkspaceRemoteSessionProvider(
      baseUri: Uri.parse('https://workspace.example/'),
      client: MockClient((request) async => http.Response('{}', 500)),
      resolveSession: () async => null,
    );

    expect(await provider.currentRemote(), isNull);
  });
}

HttpWorkspaceRemotePersistence _remote(http.Client client) =>
    HttpWorkspaceRemotePersistence(
      identity: const WorkspaceIdentity(userId: 'alice'),
      baseUri: Uri.parse('https://workspace.example/'),
      accessToken: 'alice-token',
      client: client,
    );

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

WorkspaceSnapshot _snapshot() => WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[],
      baseEntries: const <WorkspaceEntry>[],
      openFiles: const <String>[],
      activePath: '',
      nextId: 1,
      savedAt: DateTime.utc(2026, 9, 3),
    );
