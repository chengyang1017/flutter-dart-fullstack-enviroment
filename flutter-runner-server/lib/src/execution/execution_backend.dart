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

  /// 把运行环境中的 /workspace 拉回宿主机。
  ///
  /// Local 模式本来就在宿主机，所以是 no-op。
  /// Docker 模式需要 docker cp。
  
  //Future<void> pullWorkspace(RunnerSession session);

  @override
  Future<void> pullWorkspace(RunnerSession session) async {
    // Local runner 本身就在 session.directory 中运行。
    // 不需要复制任何东西。
  }

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