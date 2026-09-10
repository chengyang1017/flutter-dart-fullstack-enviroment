import 'dart:convert';
import 'dart:io';

import '../runner_session.dart';
import 'execution_backend.dart';
import 'fly_execution_backend.dart';

/// Windows-safe Fly backend for phase 1.
///
/// `fly ssh console --command` still initializes SSH console terminal handling
/// on Windows and can return `The handle is invalid` after a successful remote
/// command. `fly machine exec --json` is non-interactive and returns the actual
/// remote exit code/stdout/stderr as structured data, so command execution does
/// not depend on a local terminal handle.
class FlyMachineExecExecutionBackend implements RunnerExecutionBackend {
  FlyMachineExecExecutionBackend({
    required this.appName,
    required this.apiToken,
    required this.image,
    this.region = 'sin',
    this.flyctlExecutable = 'flyctl',
    this.tarExecutable = 'tar',
    this.cpuKind = 'shared',
    this.cpus = 1,
    this.memoryMb = 2048,
    this.flutterExecutable = 'flutter',
    this.dartExecutable = 'dart',
    this.dartFrogExecutable = 'dart_frog',
    this.serverpodExecutable = 'serverpod',
    Uri? machinesApiBaseUri,
  }) : _lifecycle = FlyExecutionBackend(
          appName: appName,
          apiToken: apiToken,
          image: image,
          region: region,
          flyctlExecutable: flyctlExecutable,
          tarExecutable: tarExecutable,
          cpuKind: cpuKind,
          cpus: cpus,
          memoryMb: memoryMb,
          flutterExecutable: flutterExecutable,
          dartExecutable: dartExecutable,
          dartFrogExecutable: dartFrogExecutable,
          serverpodExecutable: serverpodExecutable,
          machinesApiBaseUri: machinesApiBaseUri,
        );

  final String appName;
  final String apiToken;
  final String image;
  final String region;
  final String flyctlExecutable;
  final String tarExecutable;
  final String cpuKind;
  final int cpus;
  final int memoryMb;
  final String flutterExecutable;
  final String dartExecutable;
  final String dartFrogExecutable;
  final String serverpodExecutable;
  final FlyExecutionBackend _lifecycle;

  @override
  String get name => 'fly';

  @override
  Future<void> prepareSession(RunnerSession session) {
    return _lifecycle.prepareSession(session);
  }

  @override
  Future<int> runFlutterCommand(
    RunnerSession session,
    List<String> arguments,
  ) {
    return _runRemoteLoggedProcess(
      session,
      executable: flutterExecutable,
      arguments: arguments,
      workingDirectory: '/workspace',
    );
  }

  @override
  Future<int> runDartCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'backend',
  }) {
    return _runRemoteLoggedProcess(
      session,
      executable: dartExecutable,
      arguments: arguments,
      workingDirectory: _remoteWorkingDirectory(workingDirectory),
      logPrefix: '[backend] ',
      stderrPrefix: '[backend stderr] ',
    );
  }

  @override
  Future<int> runServerpodCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'serverpod/practice_server',
  }) {
    return _runRemoteLoggedProcess(
      session,
      executable: serverpodExecutable,
      arguments: arguments,
      workingDirectory: _remoteWorkingDirectory(workingDirectory),
      logPrefix: '[serverpod] ',
      stderrPrefix: '[serverpod stderr] ',
    );
  }

  @override
  Future<void> pullWorkspace(RunnerSession session) async {
    final machineId = _requireMachine(session);
    final archiveName = 'flutter-runner-${_safeId(session.id)}-pull.tar';
    final remoteArchive = '/tmp/$archiveName';
    final localArchive = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '$archiveName-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      final packExit = await _runRemoteShell(
        session,
        'tar -C /workspace -cf ${_shellQuote(remoteArchive)} .',
      );
      if (packExit != 0) {
        throw StateError('Failed to archive Fly workspace.');
      }

      final getResult = await _runFlyctl(<String>[
        'ssh',
        'sftp',
        'get',
        remoteArchive,
        localArchive.path,
        '--app',
        appName,
        '--machine',
        machineId,
        '--user',
        'sandbox',
        '--quiet',
      ]);
      _ensureProcessSuccess(session, getResult, 'download Fly workspace');

      await session.directory.create(recursive: true);
      final extractResult = await Process.run(
        tarExecutable,
        <String>[
          '-xf',
          localArchive.path,
          '-C',
          session.directory.path,
        ],
        runInShell: false,
      );
      _ensureProcessSuccess(session, extractResult, 'extract Fly workspace');
    } finally {
      if (await localArchive.exists()) {
        await localArchive.delete();
      }
      await _runRemoteShell(
        session,
        'rm -f -- ${_shellQuote(remoteArchive)}',
        logFailure: false,
      );
    }
  }

  @override
  Future<void> syncWorkspace(
    RunnerSession session, {
    required Set<String> removedPaths,
  }) async {
    final machineId = _requireMachine(session);
    final archiveName = 'flutter-runner-${_safeId(session.id)}-push.tar';
    final remoteArchive = '/tmp/$archiveName';
    final localArchive = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '$archiveName-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      final archiveResult = await Process.run(
        tarExecutable,
        <String>[
          '-C',
          session.directory.path,
          '-cf',
          localArchive.path,
          '.',
        ],
        runInShell: false,
      );
      _ensureProcessSuccess(session, archiveResult, 'archive local workspace');

      final putResult = await _runFlyctl(<String>[
        'ssh',
        'sftp',
        'put',
        localArchive.path,
        remoteArchive,
        '--app',
        appName,
        '--machine',
        machineId,
        '--user',
        'sandbox',
        '--quiet',
      ]);
      _ensureProcessSuccess(session, putResult, 'upload Fly workspace');

      if (removedPaths.isNotEmpty) {
        final removeCommand = <String>[
          'cd /workspace',
          '&&',
          'rm -rf --',
          ...removedPaths.map(_shellQuote),
        ].join(' ');
        final removeExit = await _runRemoteShell(session, removeCommand);
        if (removeExit != 0) {
          throw StateError('Failed to remove deleted Fly workspace files.');
        }
      }

      final extractExit = await _runRemoteShell(
        session,
        'tar -xf ${_shellQuote(remoteArchive)} -C /workspace',
      );
      if (extractExit != 0) {
        throw StateError('Failed to extract Fly workspace.');
      }
    } finally {
      if (await localArchive.exists()) {
        await localArchive.delete();
      }
      await _runRemoteShell(
        session,
        'rm -f -- ${_shellQuote(remoteArchive)}',
        logFailure: false,
      );
    }
  }

  @override
  Future<RunnerProcessLaunch> startFlutterWeb(
    RunnerSession session, {
    Map<String, String> dartDefines = const <String, String>{},
  }) {
    return _lifecycle.startFlutterWeb(session, dartDefines: dartDefines);
  }

  @override
  Future<RunnerProcessLaunch> startDartFrog(RunnerSession session) {
    return _lifecycle.startDartFrog(session);
  }

  @override
  Future<RunnerProcessLaunch> startServerpod(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  }) {
    return _lifecycle.startServerpod(
      session,
      workingDirectory: workingDirectory,
    );
  }

  @override
  Future<void> forceStop(RunnerSession session, Process process) {
    return _lifecycle.forceStop(session, process);
  }

  @override
  Future<void> disposeSession(RunnerSession session) {
    return _lifecycle.disposeSession(session);
  }

  Future<int> _runRemoteLoggedProcess(
    RunnerSession session, {
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    String logPrefix = '',
    String stderrPrefix = '[stderr] ',
  }) async {
    final command = _remoteCommand(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    );
    final result = await _runMachineExec(session, command);

    _logText(session, result.stdout, logPrefix);
    _logText(session, result.stderr, stderrPrefix);
    return result.exitCode;
  }

  Future<int> _runRemoteShell(
    RunnerSession session,
    String command, {
    bool logFailure = true,
  }) async {
    try {
      final result = await _runMachineExec(
        session,
        _asSandboxShell(command),
      );
      if (logFailure && result.exitCode != 0) {
        _logText(session, result.stdout, '[fly] ');
        _logText(session, result.stderr, '[fly] ');
      }
      return result.exitCode;
    } on ProcessException {
      if (logFailure) rethrow;
      return 127;
    }
  }

  Future<_FlyMachineExecResult> _runMachineExec(
    RunnerSession session,
    String command,
  ) async {
    final machineId = _requireMachine(session);
    final result = await _runFlyctl(<String>[
      'machine',
      'exec',
      machineId,
      command,
      '--app',
      appName,
      '--json',
    ]);

    if (result.exitCode != 0) {
      final stdoutText = '${result.stdout}'.trim();
      final stderrText = '${result.stderr}'.trim();
      return _FlyMachineExecResult(
        exitCode: result.exitCode,
        stdout: stdoutText,
        stderr: stderrText.isEmpty
            ? 'fly machine exec failed before a remote result was returned.'
            : stderrText,
      );
    }

    final raw = '${result.stdout}'.trim();
    if (raw.isEmpty) {
      return const _FlyMachineExecResult(
        exitCode: 1,
        stdout: '',
        stderr: 'fly machine exec returned empty JSON output.',
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      final rawExitCode = decoded['exit_code'];
      // Fly's MachineExecResponse uses `json:"exit_code,omitempty"`, so a
      // successful remote command (exit code 0) omits the field entirely.
      final remoteExitCode = switch (rawExitCode) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value) ?? 1,
        _ => 0,
      };
      return _FlyMachineExecResult(
        exitCode: remoteExitCode,
        stdout: decoded['stdout']?.toString() ?? '',
        stderr: decoded['stderr']?.toString() ?? '',
      );
    } on FormatException catch (error) {
      return _FlyMachineExecResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Could not parse fly machine exec JSON: $error\n$raw',
      );
    }
  }

  Future<ProcessResult> _runFlyctl(List<String> arguments) {
    return Process.run(
      flyctlExecutable,
      arguments,
      environment: _flyEnvironment(),
      includeParentEnvironment: true,
      runInShell: false,
    );
  }

  Map<String, String> _flyEnvironment() {
    return <String, String>{
      'FLY_API_TOKEN': apiToken,
      'FLY_APP': appName,
    };
  }

  String _remoteCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) {
    final command = <String>[
      'cd ${_shellQuote(workingDirectory)}',
      'exec ${_shellQuote(executable)} '
          '${arguments.map(_shellQuote).join(' ')}',
    ].join('; ');
    return _asSandboxShell(command);
  }

  String _asSandboxShell(String command) {
    final quoted = _shellQuote(command);
    final selector = r'if [ "$(id -u)" = "0" ]; then '
        'exec su -s /bin/sh sandbox -c $quoted; '
        'else exec /bin/sh -lc $quoted; fi';
    return '/bin/sh -lc ${_shellQuote(selector)}';
  }

  String _remoteWorkingDirectory(String relativePath) {
    if (relativePath.isEmpty || relativePath == '.') return '/workspace';
    return '/workspace/$relativePath';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _requireMachine(RunnerSession session) {
    final machineId = session.runtimeId;
    if (machineId == null || machineId.isEmpty) {
      throw StateError('Fly Machine runtime has not been prepared.');
    }
    return machineId;
  }

  String _safeId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  }

  void _ensureProcessSuccess(
    RunnerSession session,
    ProcessResult result,
    String operation,
  ) {
    if (result.exitCode == 0) return;
    _logProcessResult(session, result, prefix: '[fly] ');
    throw StateError(
      'Failed to $operation (exit code ${result.exitCode}).',
    );
  }

  void _logProcessResult(
    RunnerSession session,
    ProcessResult result, {
    required String prefix,
  }) {
    _logText(session, '${result.stdout}', prefix);
    _logText(session, '${result.stderr}', prefix);
  }

  void _logText(RunnerSession session, String text, String prefix) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    for (final line in const LineSplitter().convert(trimmed)) {
      session.addLog('$prefix$line');
    }
  }
}

class _FlyMachineExecResult {
  const _FlyMachineExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
