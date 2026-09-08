import '../../workspace/models/workspace_capability.dart';
import '../../workspace/models/workspace_change.dart';
import '../models/run_session.dart';
import '../models/runner_event.dart';
import '../models/runner_pub_get_result.dart';

abstract interface class FlutterRunnerClient {
  String get displayName;
  bool get isMock;

  Future<RunSession> createSession({
    required Map<String, String> files,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  });

  Stream<RunnerEvent> watchSession(String sessionId);

  Future<void> syncWorkspace({
    required String sessionId,
    required Map<String, String> files,
    required List<WorkspaceChange> changes,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
  });

  Future<void> run(String sessionId);

  Future<void> hotReload(String sessionId);

  Future<void> hotRestart(String sessionId);

  Future<void> stop(String sessionId);

  Future<void> disposeSession(String sessionId);
}

/// Optional runner capability used by the visual package manager.
/// Keeping this separate preserves compatibility with lightweight Runner fakes.
abstract interface class FlutterPackageRunnerClient {
  Future<RunnerPubGetResult> pubGet(String sessionId);
}
