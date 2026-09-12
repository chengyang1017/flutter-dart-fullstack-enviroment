import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/controllers/flutter_runner_controller.dart';
import 'package:flutter_ui_playground/features/runner/models/run_session.dart';
import 'package:flutter_ui_playground/features/runner/models/runner_event.dart';
import 'package:flutter_ui_playground/features/runner/models/workspace_runner_source.dart';
import 'package:flutter_ui_playground/features/runner/services/flutter_runner_client.dart';
import 'package:flutter_ui_playground/features/runner/services/mock_flutter_runner_client.dart';
import 'package:flutter_ui_playground/features/runner/services/workspace_runner_source_provider.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_capability.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_change.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_identity.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_remote_models.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_remote_persistence.dart';

Future<void> settleRunnerEvents() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('remote-backed source persists before exposing Runner source', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);
    workspace.updateFileContent(
      'lib/main.dart',
      'void main() { print("cloud-1"); }',
    );

    final remote = _FakeRemotePersistence(
      document: _document('workspace-a', 'void main() {}', 'r1'),
    );
    final provider = RemoteBackedWorkspaceRunnerSourceProvider(
      workspace: workspace,
      remote: remote,
      project: _project('workspace-a'),
      hydratedDocument: remote.document,
    );

    final first = await provider.prepare();

    expect(first.remoteRevision, 'r2');
    expect(first.files['lib/main.dart'], contains('cloud-1'));
    expect(first.firebaseCapabilities, {FirebaseCapability.firestore});
    expect(remote.expectedSaveRevisions, ['r1']);
    expect(provider.revision, 'r2');

    workspace.updateFileContent(
      'lib/main.dart',
      'void main() { print("cloud-2"); }',
    );
    final second = await provider.prepare();

    expect(second.remoteRevision, 'r3');
    expect(second.files['lib/main.dart'], contains('cloud-2'));
    expect(second.firebaseCapabilities, {FirebaseCapability.firestore});
    expect(remote.expectedSaveRevisions, ['r1', 'r2']);
    expect(provider.revision, 'r3');
  });

  test('remote-backed source creates missing cloud Workspace once', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);
    final remote = _FakeRemotePersistence(document: null);
    final provider = RemoteBackedWorkspaceRunnerSourceProvider(
      workspace: workspace,
      remote: remote,
      project: _project('workspace-a'),
    );

    final first = await provider.prepare();
    final second = await provider.prepare();

    expect(first.remoteRevision, 'r1');
    expect(second.remoteRevision, 'r2');
    expect(remote.createCount, 1);
    expect(remote.expectedSaveRevisions, ['r1']);
  });

  test('runner syncs exactly the source and capabilities prepared by provider',
      () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: '// browser-memory',
    );
    final client = _RecordingRunnerClient();
    final runner = FlutterRunnerController(
      workspace: workspace,
      client: client,
      sourceProvider: _StaticSourceProvider(
        WorkspaceRunnerSource(
          files: const <String, String>{
            'lib/main.dart': '// persisted-r7',
          },
          changes: const <WorkspaceChange>[],
          firebaseCapabilities: const <FirebaseCapability>{
            FirebaseCapability.auth,
            FirebaseCapability.storage,
          },
          remoteRevision: 'r7',
        ),
      ),
    );
    addTearDown(runner.dispose);
    addTearDown(workspace.dispose);

    await runner.run();
    await settleRunnerEvents();

    expect(client.createdFiles['lib/main.dart'], '// persisted-r7');
    expect(client.syncedFiles['lib/main.dart'], '// persisted-r7');
    expect(
      client.createdCapabilities,
      {FirebaseCapability.auth, FirebaseCapability.storage},
    );
    expect(
      client.syncedCapabilities,
      {FirebaseCapability.auth, FirebaseCapability.storage},
    );
    expect(runner.lastSyncedSourceRevision, 'r7');
    expect(
      runner.logs.any(
        (line) => line.contains('persisted Workspace revision r7'),
      ),
      isTrue,
    );
  });
}

WorkspaceIdentity _identity() => const WorkspaceIdentity(userId: 'alice');

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
    firebaseCapabilities: const <FirebaseCapability>{
      FirebaseCapability.firestore,
    },
  );
}

WorkspaceRemoteDocument _document(
  String id,
  String mainDart,
  String revision,
) {
  final workspace = WorkspaceController.flutterPlayground(
    mainDartContent: mainDart,
  );
  final snapshot = workspace.createSnapshot();
  workspace.dispose();
  return WorkspaceRemoteDocument(
    project: _project(id),
    snapshot: snapshot,
    revision: revision,
  );
}

class _FakeRemotePersistence implements WorkspaceRemotePersistence {
  _FakeRemotePersistence({required this.document});

  @override
  final WorkspaceIdentity identity = _identity();

  WorkspaceRemoteDocument? document;
  int createCount = 0;
  final List<String> expectedSaveRevisions = <String>[];

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() async => WorkspaceRemoteCatalog(
        projects: document == null
            ? const <WorkspaceProject>[]
            : <WorkspaceProject>[document!.project],
        revision: 'c1',
      );

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async {
    final current = document;
    return current?.project.id == workspaceId ? current : null;
  }

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    createCount += 1;
    final created = WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r1',
    );
    document = created;
    return created;
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    expectedSaveRevisions.add(expectedRevision);
    final current = document;
    if (current == null) throw StateError('Missing Workspace.');
    if (current.revision != expectedRevision) {
      throw WorkspaceRevisionConflict(
        workspaceId: project.id,
        expectedRevision: expectedRevision,
        actualRevision: current.revision,
      );
    }
    final currentNumber = int.parse(current.revision.substring(1));
    final saved = WorkspaceRemoteDocument(
      project: project,
      snapshot: snapshot,
      revision: 'r${currentNumber + 1}',
    );
    document = saved;
    return saved;
  }

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) {
    throw UnimplementedError();
  }
}

class _StaticSourceProvider implements WorkspaceRunnerSourceProvider {
  const _StaticSourceProvider(this.source);

  final WorkspaceRunnerSource source;

  @override
  Future<WorkspaceRunnerSource> prepare() async => source;
}

class _RecordingRunnerClient implements FlutterRunnerClient {
  final MockFlutterRunnerClient _delegate = MockFlutterRunnerClient();
  Map<String, String> createdFiles = <String, String>{};
  Map<String, String> syncedFiles = <String, String>{};
  Set<FirebaseCapability> createdCapabilities = <FirebaseCapability>{};
  Set<FirebaseCapability> syncedCapabilities = <FirebaseCapability>{};

  @override
  String get displayName => _delegate.displayName;

  @override
  bool get isMock => _delegate.isMock;

  @override
  Future<RunSession> createSession({
    required Map<String, String> files,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  }) {
    createdFiles = Map<String, String>.of(files);
    createdCapabilities = Set<FirebaseCapability>.of(firebaseCapabilities);
    return _delegate.createSession(
      files: files,
      firebaseCapabilities: firebaseCapabilities,
    );
  }

  @override
  Stream<RunnerEvent> watchSession(String sessionId) =>
      _delegate.watchSession(sessionId);

  @override
  Future<void> syncWorkspace({
    required String sessionId,
    required Map<String, String> files,
    required List<WorkspaceChange> changes,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  }) {
    syncedFiles = Map<String, String>.of(files);
    syncedCapabilities = Set<FirebaseCapability>.of(firebaseCapabilities);
    return _delegate.syncWorkspace(
      sessionId: sessionId,
      files: files,
      changes: changes,
      firebaseCapabilities: firebaseCapabilities,
    );
  }

  @override
  Future<void> run(String sessionId) => _delegate.run(sessionId);

  @override
  Future<void> hotReload(String sessionId) => _delegate.hotReload(sessionId);

  @override
  Future<void> hotRestart(String sessionId) => _delegate.hotRestart(sessionId);

  @override
  Future<void> stop(String sessionId) => _delegate.stop(sessionId);

  @override
  Future<void> disposeSession(String sessionId) =>
      _delegate.disposeSession(sessionId);
}
