import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../runner_session.dart';
import 'execution_backend.dart';

class DockerExecutionBackend implements RunnerExecutionBackend {
  DockerExecutionBackend({
    this.dockerExecutable = 'docker',
    this.image = 'flutter-practice-runner:local',
    this.flutterExecutable = 'flutter',
    this.dartExecutable = 'dart',
    this.dartFrogExecutable = 'dart_frog',
    this.serverpodExecutable = 'serverpod',
    this.memoryLimit = '1024m',
    this.cpuLimit = '1.0',
    this.pidsLimit = 256,
    this.network,
    this.runnerOwnership = '10001:10001',
    this.containerWebPort = 8080,
    this.containerBackendPort = 8081,
    this.containerBackendVmServicePort = 8181,
  });

  final String dockerExecutable;
  final String image;
  final String flutterExecutable;
  final String dartExecutable;
  final String dartFrogExecutable;
  final String serverpodExecutable;
  final String memoryLimit;
  final String cpuLimit;
  final int pidsLimit;
  final String? network;
  final String runnerOwnership;
  final int containerWebPort;
  final int containerBackendPort;
  final int containerBackendVmServicePort;

  @override
  String get name => 'docker';

  @override
  Future<void> prepareSession(RunnerSession session) async {
    if (session.runtimeId != null) return;

    final previewPort = await _reservePort();
    final backendPort = await _reservePort();
    final containerName = _containerName(session.id);
    final arguments = <String>[
      'run',
      '--detach',
      '--interactive',
      '--init',
      '--name',
      containerName,
      '--label',
      'flutter-practice-session=${session.id}',
      '--publish',
      '127.0.0.1:$previewPort:$containerWebPort',
      '--publish',
      '127.0.0.1:$backendPort:$containerBackendPort',
      '--memory',
      memoryLimit,
      '--cpus',
      cpuLimit,
      '--pids-limit',
      '$pidsLimit',
      '--cap-drop',
      'ALL',
      '--cap-add',
      'CHOWN',
      '--security-opt',
      'no-new-privileges:true',
      '--stop-timeout',
      '2',
    ];

    final configuredNetwork = network?.trim();
    if (configuredNetwork != null && configuredNetwork.isNotEmpty) {
      arguments
        ..add('--network')
        ..add(configuredNetwork);
    }

    arguments.addAll([
      image,
      'sh',
      '-lc',
      'while :; do sleep 3600; done',
    ]);

    session.addLog(
      '[runner] Creating isolated Docker runtime '
      '(memory=$memoryLimit, cpus=$cpuLimit, pids=$pidsLimit).',
    );

    final result = await _runDocker(arguments);
    if (result.exitCode != 0) {
      _logProcessResult(session, result);
      await _runDocker(['rm', '--force', containerName], logFailure: false);
      throw StateError('docker run exited with code ${result.exitCode}');
    }

    session.runtimeId = containerName;
    session.runtimePreviewPort = previewPort;
    session.runtimeBackendPort = backendPort;
    session.addLog('[runner] Docker runtime is ready.');
  }

  @override
  Future<int> runFlutterCommand(
    RunnerSession session,
    List<String> arguments,
  ) async {
    final container = _requireContainer(session);
    return _runLoggedProcess(
      session,
      [
        'exec',
        '--workdir',
        '/workspace',
        container,
        flutterExecutable,
        ...arguments,
      ],
    );
  }

  @override
  Future<int> runDartCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'backend',
  }) async {
    final container = _requireContainer(session);
    return _runLoggedProcess(
      session,
      [
        'exec',
        '--workdir',
        _containerWorkingDirectory(workingDirectory),
        container,
        dartExecutable,
        ...arguments,
      ],
      logPrefix: '[backend] ',
      stderrPrefix: '[backend stderr] ',
    );
  }

  @override
  Future<int> runServerpodCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'serverpod/practice_server',
  }) async {
    final container = _requireContainer(session);
    return _runLoggedProcess(
      session,
      [
        'exec',
        '--workdir',
        _containerWorkingDirectory(workingDirectory),
        container,
        serverpodExecutable,
        ...arguments,
      ],
      logPrefix: '[serverpod] ',
      stderrPrefix: '[serverpod stderr] ',
    );
  }

    @override
  Future<void> pullWorkspace(RunnerSession session) async {
    final container = _requireContainer(session);

    final result = await _runDocker([
      'cp',
      '$container:/workspace/.',
      session.directory.path,
    ]);

    _ensureSuccess(
      session,
      result,
      'copy generated Flutter workspace from container',
    );
  }

  @override
  Future<void> syncWorkspace(
    RunnerSession session, {
    required Set<String> removedPaths,
  }) async {
    final container = _requireContainer(session);

    if (removedPaths.isNotEmpty) {
      final result = await _runDocker([
        'exec',
        '--workdir',
        '/workspace',
        container,
        'rm',
        '-rf',
        '--',
        ...removedPaths,
      ]);
      _ensureSuccess(session, result, 'remove deleted workspace files');
    }

    final source = '${session.directory.path}${Platform.pathSeparator}.';
    final copyResult = await _runDocker([
      'cp',
      source,
      '$container:/workspace',
    ]);
    _ensureSuccess(session, copyResult, 'copy workspace into container');

    final ownershipResult = await _runDocker([
      'exec',
      '--user',
      '0',
      container,
      'chown',
      '-R',
      runnerOwnership,
      '/workspace',
    ]);
    _ensureSuccess(session, ownershipResult, 'restore workspace ownership');
  }

  @override
  Future<RunnerProcessLaunch> startFlutterWeb(
    RunnerSession session, {
    Map<String, String> dartDefines = const <String, String>{},
  }) async {
    final container = _requireContainer(session);
    final previewPort = session.runtimePreviewPort;
    if (previewPort == null) {
      throw StateError('Docker preview port is not available.');
    }

    final flutterArguments = <String>[
      'run',
      '-d',
      'web-server',
      '--web-hostname=0.0.0.0',
      '--web-port=$containerWebPort',
      for (final entry in dartDefines.entries)
        '--dart-define=${entry.key}=${entry.value}',
    ];

    final process = await Process.start(
      dockerExecutable,
      [
        'exec',
        '--interactive',
        '--workdir',
        '/workspace',
        container,
        flutterExecutable,
        ...flutterArguments,
      ],
      runInShell: false,
    );

    return RunnerProcessLaunch(
      process: process,
      previewPort: previewPort,
      description:
          'docker exec $container flutter ${flutterArguments.join(' ')} '
          '(host port $previewPort)',
    );
  }

  @override
  Future<RunnerProcessLaunch> startDartFrog(RunnerSession session) async {
    final container = _requireContainer(session);
    final backendPort = _requireBackendPort(session);
    final arguments = <String>[
      'dev',
      '--host',
      '0.0.0.0',
      '--port',
      '$containerBackendPort',
      '--dart-vm-service-port',
      '$containerBackendVmServicePort',
    ];

    final process = await Process.start(
      dockerExecutable,
      [
        'exec',
        '--interactive',
        '--workdir',
        '/workspace/backend',
        container,
        dartFrogExecutable,
        ...arguments,
      ],
      runInShell: false,
    );

    return RunnerProcessLaunch(
      process: process,
      previewPort: backendPort,
      description:
          'docker exec $container dart_frog ${arguments.join(' ')} '
          '(host port $backendPort)',
    );
  }

  @override
  Future<RunnerProcessLaunch> startServerpod(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  }) async {
    final container = _requireContainer(session);
    final backendPort = _requireBackendPort(session);
    final process = await Process.start(
      dockerExecutable,
      [
        'exec',
        '--interactive',
        '--workdir',
        _containerWorkingDirectory(workingDirectory),
        '--env',
        'SERVERPOD_API_SERVER_PORT=$containerBackendPort',
        '--env',
        'SERVERPOD_API_SERVER_PUBLIC_PORT=$containerBackendPort',
        '--env',
        'SERVERPOD_API_SERVER_PUBLIC_HOST=localhost',
        '--env',
        'SERVERPOD_API_SERVER_PUBLIC_SCHEME=http',
        container,
        dartExecutable,
        'bin/main.dart',
        '--mode',
        'development',
      ],
      runInShell: false,
    );

    return RunnerProcessLaunch(
      process: process,
      previewPort: backendPort,
      description:
          'docker exec $container dart bin/main.dart --mode development '
          '(host port $backendPort)',
    );
  }

  @override
  Future<void> forceStop(
    RunnerSession session,
    Process process,
  ) async {
    final container = session.runtimeId;
    if (container == null) {
      process.kill();
      return;
    }

    session.addLog(
      '[runner] Restarting Docker runtime to terminate active processes.',
    );
    final result = await _runDocker([
      'restart',
      '--time',
      '1',
      container,
    ]);
    _ensureSuccess(session, result, 'restart Docker runtime');

    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill();
    }
  }

  @override
  Future<void> disposeSession(RunnerSession session) async {
    final container = session.runtimeId;
    if (container == null) return;

    final result = await _runDocker(
      ['rm', '--force', container],
      logFailure: false,
    );
    if (result.exitCode != 0) {
      session.addLog(
        '[runner] Warning: Docker cleanup exited with code '
        '${result.exitCode}.',
      );
      _logProcessResult(session, result);
    }

    session.runtimeId = null;
    session.runtimePreviewPort = null;
    session.runtimeBackendPort = null;
  }

  Future<int> _runLoggedProcess(
    RunnerSession session,
    List<String> dockerArguments, {
    String logPrefix = '',
    String stderrPrefix = '[stderr] ',
  }) async {
    final process = await Process.start(
      dockerExecutable,
      dockerArguments,
      runInShell: false,
    );

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => session.addLog('$logPrefix$line'));
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => session.addLog('$stderrPrefix$line'));
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return exitCode;
  }

  Future<ProcessResult> _runDocker(
    List<String> arguments, {
    bool logFailure = true,
  }) async {
    try {
      return await Process.run(
        dockerExecutable,
        arguments,
        runInShell: false,
      );
    } on ProcessException {
      if (logFailure) rethrow;
      return ProcessResult(-1, 127, '', 'Docker executable not available.');
    }
  }

  void _ensureSuccess(
    RunnerSession session,
    ProcessResult result,
    String operation,
  ) {
    if (result.exitCode == 0) return;
    _logProcessResult(session, result);
    throw StateError(
      'Failed to $operation (docker exit code ${result.exitCode}).',
    );
  }

  void _logProcessResult(RunnerSession session, ProcessResult result) {
    final stdoutText = '${result.stdout}'.trim();
    final stderrText = '${result.stderr}'.trim();
    if (stdoutText.isNotEmpty) {
      for (final line in const LineSplitter().convert(stdoutText)) {
        session.addLog('[docker] $line');
      }
    }
    if (stderrText.isNotEmpty) {
      for (final line in const LineSplitter().convert(stderrText)) {
        session.addLog('[docker stderr] $line');
      }
    }
  }

  String _requireContainer(RunnerSession session) {
    final container = session.runtimeId;
    if (container == null || container.isEmpty) {
      throw StateError('Docker runtime has not been prepared.');
    }
    return container;
  }

  int _requireBackendPort(RunnerSession session) {
    final port = session.runtimeBackendPort;
    if (port == null) {
      throw StateError('Docker backend port is not available.');
    }
    return port;
  }

  String _containerWorkingDirectory(String relativePath) {
    if (relativePath.isEmpty || relativePath == '.') return '/workspace';
    return '/workspace/$relativePath';
  }

  String _containerName(String sessionId) {
    final safe = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
    return 'flutter-practice-$safe';
  }

  Future<int> _reservePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
