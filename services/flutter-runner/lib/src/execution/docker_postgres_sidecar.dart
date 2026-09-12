import 'dart:io';
import 'dart:math';

import '../runner_session.dart';

class DockerPostgresSidecar {
  DockerPostgresSidecar({
    this.dockerExecutable = 'docker',
    this.image = 'pgvector/pgvector:pg16',
    this.memoryLimit = '512m',
    this.cpuLimit = '0.5',
    this.pidsLimit = 128,
    this.readyAttempts = 40,
    this.readyDelay = const Duration(milliseconds: 250),
  });

  static const databaseHost = 'postgres';
  static const databasePort = 5432;
  static const databaseName = 'practice';
  static const databaseUser = 'postgres';

  final String dockerExecutable;
  final String image;
  final String memoryLimit;
  final String cpuLimit;
  final int pidsLimit;
  final int readyAttempts;
  final Duration readyDelay;

  Future<bool> workspaceUsesDatabase(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  }) async {
    final libDirectory = Directory(
      _hostWorkingDirectory(session, '$workingDirectory/lib'),
    );
    if (!await libDirectory.exists()) return false;

    await for (final entity in libDirectory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.spy.yaml')) continue;
      final source = await entity.readAsString();
      if (RegExp(r'^\s*table\s*:', multiLine: true).hasMatch(source)) {
        return true;
      }
    }
    return false;
  }

  Future<void> prepare(RunnerSession session) async {
    if (session.databaseRuntimeId != null) return;

    final runtime = session.runtimeId;
    if (runtime == null || runtime.isEmpty) {
      throw StateError(
        'Docker runtime must be prepared before PostgreSQL sidecar setup.',
      );
    }

    final networkName = _networkName(session.id);
    final databaseContainer = _databaseContainerName(session.id);
    final password = _generatePassword();

    session.addLog(
      '[database] Creating isolated PostgreSQL sidecar '
      '(image=$image, memory=$memoryLimit, cpus=$cpuLimit).',
    );

    try {
      final createNetwork = await _runDocker([
        'network',
        'create',
        '--label',
        'flutter-practice-session=${session.id}',
        networkName,
      ]);
      _ensureSuccess(session, createNetwork, 'create database network');

      final connectRuntime = await _runDocker([
        'network',
        'connect',
        networkName,
        runtime,
      ]);
      _ensureSuccess(session, connectRuntime, 'connect runtime to database network');

      final runDatabase = await _runDocker([
        'run',
        '--detach',
        '--name',
        databaseContainer,
        '--label',
        'flutter-practice-session=${session.id}',
        '--network',
        networkName,
        '--network-alias',
        databaseHost,
        '--memory',
        memoryLimit,
        '--cpus',
        cpuLimit,
        '--pids-limit',
        '$pidsLimit',
        '--env',
        'POSTGRES_USER=$databaseUser',
        '--env',
        'POSTGRES_DB=$databaseName',
        '--env',
        'POSTGRES_PASSWORD=$password',
        image,
      ]);
      _ensureSuccess(session, runDatabase, 'start PostgreSQL sidecar');

      await _waitUntilReady(session, databaseContainer);

      session.runtimeNetworkId = networkName;
      session.databaseRuntimeId = databaseContainer;
      session.databasePassword = password;
      session.addLog('[database] PostgreSQL sidecar is ready.');
    } catch (_) {
      await _cleanupPartial(
        session,
        runtime: runtime,
        databaseContainer: databaseContainer,
        networkName: networkName,
      );
      rethrow;
    }
  }

  Map<String, String> serverpodEnvironment(RunnerSession session) {
    final password = session.databasePassword;
    if (session.databaseRuntimeId == null ||
        session.runtimeNetworkId == null ||
        password == null ||
        password.isEmpty) {
      return const <String, String>{};
    }

    return {
      'SERVERPOD_DATABASE_HOST': databaseHost,
      'SERVERPOD_DATABASE_PORT': '$databasePort',
      'SERVERPOD_DATABASE_NAME': databaseName,
      'SERVERPOD_DATABASE_USER': databaseUser,
      'SERVERPOD_DATABASE_MAX_CONNECTION_COUNT': '5',
      'SERVERPOD_PASSWORD_database': password,
      'SERVERPOD_APPLY_MIGRATIONS': 'true',
    };
  }

  Future<void> dispose(RunnerSession session) async {
    final runtime = session.runtimeId;
    final databaseContainer = session.databaseRuntimeId;
    final networkName = session.runtimeNetworkId;

    if (databaseContainer != null) {
      final removeDatabase = await _runDocker(
        ['rm', '--force', databaseContainer],
        logFailure: false,
      );
      if (removeDatabase.exitCode != 0) {
        session.addLog(
          '[database] Warning: PostgreSQL cleanup exited with code '
          '${removeDatabase.exitCode}.',
        );
      }
    }

    if (networkName != null) {
      if (runtime != null) {
        await _runDocker(
          ['network', 'disconnect', '--force', networkName, runtime],
          logFailure: false,
        );
      }
      final removeNetwork = await _runDocker(
        ['network', 'rm', networkName],
        logFailure: false,
      );
      if (removeNetwork.exitCode != 0) {
        session.addLog(
          '[database] Warning: database network cleanup exited with code '
          '${removeNetwork.exitCode}.',
        );
      }
    }

    session.databaseRuntimeId = null;
    session.databasePassword = null;
    session.runtimeNetworkId = null;
  }

  Future<void> _waitUntilReady(
    RunnerSession session,
    String databaseContainer,
  ) async {
    for (var attempt = 1; attempt <= readyAttempts; attempt++) {
      final result = await _runDocker(
        [
          'exec',
          databaseContainer,
          'pg_isready',
          '-U',
          databaseUser,
          '-d',
          databaseName,
        ],
        logFailure: false,
      );
      if (result.exitCode == 0) return;
      if (attempt < readyAttempts) await Future<void>.delayed(readyDelay);
    }

    final logs = await _runDocker(
      ['logs', '--tail', '40', databaseContainer],
      logFailure: false,
    );
    _logProcessResult(session, logs, prefix: '[database] ');
    throw StateError(
      'PostgreSQL sidecar did not become ready after $readyAttempts checks.',
    );
  }

  Future<void> _cleanupPartial(
    RunnerSession session, {
    required String runtime,
    required String databaseContainer,
    required String networkName,
  }) async {
    await _runDocker(
      ['rm', '--force', databaseContainer],
      logFailure: false,
    );
    await _runDocker(
      ['network', 'disconnect', '--force', networkName, runtime],
      logFailure: false,
    );
    await _runDocker(
      ['network', 'rm', networkName],
      logFailure: false,
    );
    session.addLog('[database] Rolled back incomplete PostgreSQL setup.');
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

  void _logProcessResult(
    RunnerSession session,
    ProcessResult result, {
    String prefix = '[docker] ',
  }) {
    final stdoutText = '${result.stdout}'.trim();
    final stderrText = '${result.stderr}'.trim();
    if (stdoutText.isNotEmpty) {
      for (final line in stdoutText.split('\n')) {
        session.addLog('$prefix${line.trimRight()}');
      }
    }
    if (stderrText.isNotEmpty) {
      for (final line in stderrText.split('\n')) {
        session.addLog('$prefix${line.trimRight()}');
      }
    }
  }

  String _hostWorkingDirectory(
    RunnerSession session,
    String relativePath,
  ) {
    if (relativePath.isEmpty || relativePath == '.') {
      return session.directory.path;
    }
    return [
      session.directory.path,
      ...relativePath.split('/'),
    ].join(Platform.pathSeparator);
  }

  String _networkName(String sessionId) {
    return 'flutter-practice-dbnet-${_safeId(sessionId)}';
  }

  String _databaseContainerName(String sessionId) {
    return 'flutter-practice-db-${_safeId(sessionId)}';
  }

  String _safeId(String sessionId) {
    return sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
  }

  String _generatePassword() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
      growable: false,
    ).join();
  }
}
