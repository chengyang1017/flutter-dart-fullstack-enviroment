import 'dart:convert';
import 'dart:io';

import '../runner_session.dart';
import 'execution_backend.dart';

class FlyExecutionBackend implements RunnerExecutionBackend {
  FlyExecutionBackend({
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
  }) : machinesApiBaseUri =
            machinesApiBaseUri ?? Uri.parse('https://api.machines.dev/v1/');

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
  final Uri machinesApiBaseUri;

  @override
  String get name => 'fly';

  @override
  Future<void> prepareSession(RunnerSession session) async {
    if (session.runtimeId != null) return;

    _validateConfiguration();

    session.addLog(
      '[runner] Creating isolated Fly Machine '
      '(app=$appName, region=$region, cpus=$cpus, memory=${memoryMb}MB).',
    );

    String? machineId;
    try {
      final response = await _machineApiJson(
        'POST',
        _appMachinesUri(),
        body: <String, Object?>{
          'name': _machineName(session.id),
          'region': region,
          'config': <String, Object?>{
            'image': image,
            'guest': <String, Object?>{
              'cpu_kind': cpuKind,
              'cpus': cpus,
              'memory_mb': memoryMb,
            },
            'init': <String, Object?>{
              'exec': <String>[
                '/bin/sh',
                '-lc',
                'while :; do sleep 3600; done',
              ],
            },
            'restart': <String, Object?>{
              'policy': 'no',
            },
            'metadata': <String, String>{
              'flutter_runner_session': session.id,
            },
          },
        },
      );

      machineId = response['id']?.toString();
      if (machineId == null || machineId.isEmpty) {
        throw StateError('Fly Machines API did not return a Machine id.');
      }

      await _machineApiJson(
        'GET',
        _machineWaitUri(machineId),
      );

      session.runtimeId = machineId;
      session.addLog('[runner] Fly Machine $machineId is ready.');
    } catch (_) {
      if (machineId != null && machineId.isNotEmpty) {
        await _deleteMachine(machineId, ignoreFailure: true);
      }
      rethrow;
    }
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
    throw UnsupportedError(
      'Fly preview transport is not enabled in phase 1 yet.',
    );
  }

  @override
  Future<RunnerProcessLaunch> startDartFrog(
    RunnerSession session,
  ) {
    throw UnsupportedError(
      'Fly Dart Frog preview transport is not enabled in phase 1 yet.',
    );
  }

  @override
  Future<RunnerProcessLaunch> startServerpod(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  }) {
    throw UnsupportedError(
      'Fly Serverpod preview transport is not enabled in phase 1 yet.',
    );
  }

  @override
  Future<void> forceStop(
    RunnerSession session,
    Process process,
  ) async {
    process.kill(ProcessSignal.sigterm);
  }

  @override
  Future<void> disposeSession(RunnerSession session) async {
    final machineId = session.runtimeId;
    if (machineId == null || machineId.isEmpty) return;

    session.addLog('[runner] Destroying Fly Machine $machineId...');
    await _deleteMachine(machineId, ignoreFailure: false);

    session.runtimeId = null;
    session.runtimePreviewPort = null;
    session.runtimeBackendPort = null;
    session.addLog('[runner] Fly Machine destroyed.');
  }

  Future<int> _runRemoteLoggedProcess(
    RunnerSession session, {
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    String logPrefix = '',
    String stderrPrefix = '[stderr] ',
  }) async {
    final machineId = _requireMachine(session);
    final command = _remoteCommand(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    );

    final process = await Process.start(
      flyctlExecutable,
      <String>[
        'ssh',
        'console',
        '--app',
        appName,
        '--machine',
        machineId,
        '--user',
        'sandbox',
        '--quiet',
        '--command',
        command,
      ],
      environment: _flyEnvironment(),
      includeParentEnvironment: true,
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
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return exitCode;
  }

  Future<int> _runRemoteShell(
    RunnerSession session,
    String command, {
    bool logFailure = true,
  }) async {
    try {
      final machineId = _requireMachine(session);
      final wrapped = 'sh -lc ${_shellQuote(command)}';
      final result = await _runFlyctl(<String>[
        'ssh',
        'console',
        '--app',
        appName,
        '--machine',
        machineId,
        '--user',
        'sandbox',
        '--quiet',
        '--command',
        wrapped,
      ]);
      if (logFailure && result.exitCode != 0) {
        _logProcessResult(session, result, prefix: '[fly] ');
      }
      return result.exitCode;
    } on ProcessException {
      if (logFailure) rethrow;
      return 127;
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

  Future<Map<String, Object?>> _machineApiJson(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $apiToken')
        ..set(HttpHeaders.acceptHeader, 'application/json');

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseText = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Fly Machines API $method ${uri.path} failed with '
          '${response.statusCode}: ${responseText.trim()}',
          uri: uri,
        );
      }

      if (responseText.trim().isEmpty) {
        return <String, Object?>{};
      }

      final decoded = jsonDecode(responseText);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
      throw FormatException(
        'Fly Machines API returned unexpected JSON for ${uri.path}.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _deleteMachine(
    String machineId, {
    required bool ignoreFailure,
  }) async {
    try {
      await _machineApiJson(
        'DELETE',
        _machineUri(machineId).replace(
          queryParameters: const <String, String>{'force': 'true'},
        ),
      );
    } catch (_) {
      if (!ignoreFailure) rethrow;
    }
  }

  Uri _appMachinesUri() {
    return machinesApiBaseUri.resolve(
      'apps/${Uri.encodeComponent(appName)}/machines',
    );
  }

  Uri _machineUri(String machineId) {
    return machinesApiBaseUri.resolve(
      'apps/${Uri.encodeComponent(appName)}/machines/'
      '${Uri.encodeComponent(machineId)}',
    );
  }

  Uri _machineWaitUri(String machineId) {
    final machineUri = _machineUri(machineId);
    return machineUri.replace(
      path: '${machineUri.path}/wait',
      queryParameters: const <String, String>{
        'state': 'started',
      },
    );
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

    return 'sh -lc ${_shellQuote(command)}';
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

  String _machineName(String sessionId) {
    final safe = _safeId(sessionId).toLowerCase();
    final trimmed = safe.length <= 45 ? safe : safe.substring(safe.length - 45);
    return 'runner-$trimmed';
  }

  String _safeId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  }

  void _validateConfiguration() {
    if (appName.trim().isEmpty) {
      throw const FormatException('FLY_RUNTIME_APP cannot be empty.');
    }
    if (apiToken.trim().isEmpty) {
      throw const FormatException('FLY_API_TOKEN cannot be empty.');
    }
    if (image.trim().isEmpty) {
      throw const FormatException('FLY_RUNTIME_IMAGE cannot be empty.');
    }
    if (cpus < 1 || cpus > 8) {
      throw RangeError.range(cpus, 1, 8, 'cpus');
    }
    if (memoryMb < 256 || memoryMb % 256 != 0) {
      throw RangeError(
        'memoryMb must be at least 256 and a multiple of 256.',
      );
    }
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
    final stdoutText = '${result.stdout}'.trim();
    final stderrText = '${result.stderr}'.trim();

    if (stdoutText.isNotEmpty) {
      for (final line in const LineSplitter().convert(stdoutText)) {
        session.addLog('$prefix$line');
      }
    }
    if (stderrText.isNotEmpty) {
      for (final line in const LineSplitter().convert(stderrText)) {
        session.addLog('$prefix$line');
      }
    }
  }
}
