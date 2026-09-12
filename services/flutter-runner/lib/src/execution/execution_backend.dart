import 'dart:io';

import '../runner_session.dart';

class RunnerProcessLaunch {
  const RunnerProcessLaunch({
    required this.process,
    required this.previewPort,
    required this.description,
  });

  final Process process;
  final int previewPort;
  final String description;
}

abstract interface class RunnerExecutionBackend {
  String get name;

  Future<void> prepareSession(RunnerSession session);

  Future<int> runFlutterCommand(
    RunnerSession session,
    List<String> arguments,
  );

  Future<int> runDartCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'backend',
  });

  Future<int> runServerpodCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'serverpod/practice_server',
  });

  /// Pulls /workspace from the execution environment back to the host.
  /// Local mode is a no-op; Docker copies the generated files out.
  Future<void> pullWorkspace(RunnerSession session);

  Future<void> syncWorkspace(
    RunnerSession session, {
    required Set<String> removedPaths,
  });

  Future<RunnerProcessLaunch> startFlutterWeb(
    RunnerSession session, {
    Map<String, String> dartDefines = const <String, String>{},
  });

  Future<RunnerProcessLaunch> startDartFrog(
    RunnerSession session,
  );

  Future<RunnerProcessLaunch> startServerpod(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  });

  Future<void> forceStop(
    RunnerSession session,
    Process process,
  );

  Future<void> disposeSession(RunnerSession session);
}
