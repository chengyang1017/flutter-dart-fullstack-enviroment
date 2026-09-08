import 'dart:async';

import '../../workspace/models/workspace_capability.dart';
import '../../workspace/models/workspace_change.dart';
import '../models/run_session.dart';
import '../models/runner_event.dart';
import '../models/runner_pub_get_result.dart';
import 'flutter_runner_client.dart';

class MockFlutterRunnerClient
    implements FlutterRunnerClient, FlutterPackageRunnerClient {
  final Map<String, StreamController<RunnerEvent>> _streams = {};
  int _nextSession = 1;

  @override
  String get displayName => 'Mock Flutter Runner';

  @override
  bool get isMock => true;

  @override
  Future<RunSession> createSession({
    required Map<String, String> files,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  }) async {
    final now = DateTime.now();
    final id = 'mock-${_nextSession++}';
    _streams[id] = StreamController<RunnerEvent>.broadcast();

    return RunSession(
      id: id,
      status: RunnerStatus.ready,
      createdAt: now,
      lastActivityAt: now,
      firebaseCapabilities: firebaseCapabilities,
    );
  }

  @override
  Stream<RunnerEvent> watchSession(String sessionId) {
    final controller = _streams[sessionId];
    if (controller == null) {
      throw StateError('Unknown runner session: $sessionId');
    }
    return controller.stream;
  }

  @override
  Future<void> syncWorkspace({
    required String sessionId,
    required Map<String, String> files,
    required List<WorkspaceChange> changes,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  }) async {
    _emitStatus(sessionId, RunnerStatus.syncing);
    final firebaseLabel = FirebaseCapabilityCodec.encode(firebaseCapabilities);
    _emitLog(
      sessionId,
      '[mock] Synced ${files.length} files (${changes.length} workspace changes; '
      'Firebase: ${firebaseLabel.isEmpty ? 'none' : firebaseLabel.join(', ')}).',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  @override
  Future<RunnerPubGetResult> pubGet(String sessionId) async {
    _emitStatus(sessionId, RunnerStatus.syncing);
    _emitLog(sessionId, '[mock] flutter pub get');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _emitStatus(sessionId, RunnerStatus.ready);
    return const RunnerPubGetResult(
      hasPackageConfig: true,
    );
  }

  @override
  Future<void> run(String sessionId) async {
    _emitStatus(sessionId, RunnerStatus.starting);
    _emitLog(sessionId, '[mock] flutter pub get');
    _emitLog(sessionId, '[mock] flutter run -d web-server');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _emitStatus(sessionId, RunnerStatus.running);
    _emitLog(
      sessionId,
      '[mock] Runner protocol is connected. Real Flutter SDK execution comes in Phase 4.',
    );
  }

  @override
  Future<void> hotReload(String sessionId) async {
    _emitStatus(sessionId, RunnerStatus.reloading);
    _emitLog(sessionId, '[mock] Hot reload requested.');
    await Future<void>.delayed(const Duration(milliseconds: 70));
    _emitStatus(sessionId, RunnerStatus.running);
  }

  @override
  Future<void> hotRestart(String sessionId) async {
    _emitStatus(sessionId, RunnerStatus.restarting);
    _emitLog(sessionId, '[mock] Hot restart requested.');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    _emitStatus(sessionId, RunnerStatus.running);
  }

  @override
  Future<void> stop(String sessionId) async {
    _emitStatus(sessionId, RunnerStatus.stopping);
    _emitLog(sessionId, '[mock] Stopping Flutter runner.');
    await Future<void>.delayed(const Duration(milliseconds: 70));
    _emitStatus(sessionId, RunnerStatus.stopped);
  }

  @override
  Future<void> disposeSession(String sessionId) async {
    final controller = _streams.remove(sessionId);
    await controller?.close();
  }

  void _emitStatus(String sessionId, RunnerStatus status) {
    _streams[sessionId]?.add(RunnerEvent.status(status));
  }

  void _emitLog(String sessionId, String message) {
    _streams[sessionId]?.add(RunnerEvent.log(message));
  }
}
