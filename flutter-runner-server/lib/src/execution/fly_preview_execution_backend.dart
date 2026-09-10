import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../runner_session.dart';
import 'execution_backend.dart';
import 'fly_machine_exec_execution_backend.dart';

/// Fly backend with a real Flutter Web preview tunnel.
///
/// The Flutter process runs inside the session Machine on port 8080. A local
/// `fly proxy` process opens a WireGuard tunnel to that exact Machine using its
/// machine-scoped `.internal` hostname. The existing Runner HTTP gateway can
/// then continue proxying to a loopback port exactly as it does for Docker.
class FlyPreviewExecutionBackend extends FlyMachineExecExecutionBackend {
  FlyPreviewExecutionBackend({
    required super.appName,
    required super.apiToken,
    required super.image,
    super.region,
    super.flyctlExecutable,
    super.tarExecutable,
    super.cpuKind,
    super.cpus,
    super.memoryMb,
    super.flutterExecutable,
    super.dartExecutable,
    super.dartFrogExecutable,
    super.serverpodExecutable,
    super.machinesApiBaseUri,
    this.remotePreviewPort = 8080,
    this.previewStartupTimeout = const Duration(seconds: 120),
  });

  final int remotePreviewPort;
  final Duration previewStartupTimeout;

  final Map<String, Process> _previewProxyProcesses = <String, Process>{};

  @override
  Future<RunnerProcessLaunch> startFlutterWeb(
    RunnerSession session, {
    Map<String, String> dartDefines = const <String, String>{},
  }) async {
    final machineId = _requireMachineId(session);

    await _stopTrackedProxy(session.id);
    await _stopRemoteFlutter(session, ignoreFailure: true);

    final flutterArguments = <String>[
      'run',
      '-d',
      'web-server',
      '--web-hostname=::',
      '--web-port=$remotePreviewPort',
      for (final entry in dartDefines.entries)
        '--dart-define=${entry.key}=${entry.value}',
    ];

    session.addLog(
      '[runner] Starting Flutter Web inside Fly Machine $machineId '
      'on port $remotePreviewPort...',
    );

    final remoteCommand = <String>[
      'cd /workspace',
      'git config --global --add safe.directory /opt/flutter '
          '>/dev/null 2>&1 || true',
      'rm -f /tmp/flutter-preview.log /tmp/flutter-preview.pid',
      'nohup ${_shellQuote(flutterExecutable)} '
          '${flutterArguments.map(_shellQuote).join(' ')} '
          '> /tmp/flutter-preview.log 2>&1 < /dev/null '
          r'& echo $! > /tmp/flutter-preview.pid',
    ].join('; ');

    final startResult = await _machineExec(
      session,
      _asSandboxShell(remoteCommand),
    );
    if (startResult.exitCode != 0) {
      throw StateError(
        'Failed to launch remote Flutter preview '
        '(exit ${startResult.exitCode}): ${startResult.stderr.trim()}',
      );
    }

    final localPort = await _reserveLoopbackPort();
    final remoteHost = '$machineId.vm.$appName.internal';

    final proxy = await Process.start(
      flyctlExecutable,
      <String>[
        'proxy',
        '$localPort:$remotePreviewPort',
        remoteHost,
        '--app',
        appName,
        '--bind-addr',
        '127.0.0.1',
        '--quiet',
      ],
      environment: _flyEnvironment(),
      includeParentEnvironment: true,
      runInShell: false,
    );
    _previewProxyProcesses[session.id] = proxy;

    int? proxyExitCode;
    unawaited(proxy.exitCode.then((value) => proxyExitCode = value));

    try {
      await _waitForPreview(
        localPort,
        timeout: previewStartupTimeout,
        proxyExitCode: () => proxyExitCode,
      );
    } catch (error) {
      final remoteLog = await _readRemotePreviewLog(session);
      await _stopTrackedProxy(session.id);
      await _stopRemoteFlutter(session, ignoreFailure: true);
      if (remoteLog.isNotEmpty) {
        for (final line in const LineSplitter().convert(remoteLog)) {
          session.addLog('[flutter remote] $line');
        }
      }
      throw StateError('Fly Flutter preview failed to become ready: $error');
    }

    final remoteLog = await _readRemotePreviewLog(session);
    if (remoteLog.isNotEmpty) {
      for (final line in const LineSplitter().convert(remoteLog)) {
        session.addLog('[flutter remote] $line');
      }
    }

    session.addLog(
      '[runner] Fly preview tunnel ready: '
      '127.0.0.1:$localPort -> $remoteHost:$remotePreviewPort.',
    );

    session.setStatus('running');

    return RunnerProcessLaunch(
      process: proxy,
      previewPort: localPort,
      description:
          'Fly Flutter Web preview on Machine $machineId '
          '(remote $remotePreviewPort, tunnel localhost:$localPort)',
    );
  }

  @override
  Future<void> forceStop(RunnerSession session, Process process) async {
    await _stopRemoteFlutter(session, ignoreFailure: true);

    final tracked = _previewProxyProcesses.remove(session.id);
    final proxy = tracked ?? process;
    if (proxy.kill(ProcessSignal.sigterm)) {
      try {
        await proxy.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        proxy.kill(ProcessSignal.sigkill);
      }
    }
  }

  @override
  Future<void> disposeSession(RunnerSession session) async {
    await _stopTrackedProxy(session.id);
    await _stopRemoteFlutter(session, ignoreFailure: true);
    await super.disposeSession(session);
  }

  Future<void> _stopTrackedProxy(String sessionId) async {
    final process = _previewProxyProcesses.remove(sessionId);
    if (process == null) return;

    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<void> _stopRemoteFlutter(
    RunnerSession session, {
    required bool ignoreFailure,
  }) async {
    if (session.runtimeId == null || session.runtimeId!.isEmpty) return;

    final command = <String>[
      'if [ -f /tmp/flutter-preview.pid ]; then',
      r'pid="$(cat /tmp/flutter-preview.pid 2>/dev/null || true)"',
      r'if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi',
      'fi',
      'rm -f /tmp/flutter-preview.pid',
    ].join(' ')
      ..replaceAll(r'\"', '"');

    try {
      final result = await _machineExec(
        session,
        '/bin/sh -lc ${_shellQuote(command)}',
      );
      if (!ignoreFailure && result.exitCode != 0) {
        throw StateError(
          'Failed to stop remote Flutter preview: ${result.stderr.trim()}',
        );
      }
    } catch (_) {
      if (!ignoreFailure) rethrow;
    }
  }

  Future<String> _readRemotePreviewLog(RunnerSession session) async {
    try {
      final result = await _machineExec(
        session,
        _asSandboxShell(
          'tail -n 80 /tmp/flutter-preview.log 2>/dev/null || true',
        ),
      );
      return result.stdout.trimRight();
    } catch (_) {
      return '';
    }
  }

  Future<_MachineExecResult> _machineExec(
    RunnerSession session,
    String command,
  ) async {
    final machineId = _requireMachineId(session);
    final processResult = await Process.run(
      flyctlExecutable,
      <String>[
        'machine',
        'exec',
        machineId,
        command,
        '--app',
        appName,
        '--json',
      ],
      environment: _flyEnvironment(),
      includeParentEnvironment: true,
      runInShell: false,
    );

    if (processResult.exitCode != 0) {
      return _MachineExecResult(
        exitCode: processResult.exitCode,
        stdout: '${processResult.stdout}',
        stderr: '${processResult.stderr}',
      );
    }

    final raw = '${processResult.stdout}'.trim();
    if (raw.isEmpty) {
      return const _MachineExecResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('fly machine exec returned non-object JSON.');
    }

    final rawExitCode = decoded['exit_code'];
    final remoteExitCode = switch (rawExitCode) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 1,
      null => 0,
      _ => 1,
    };

    return _MachineExecResult(
      exitCode: remoteExitCode,
      stdout: decoded['stdout']?.toString() ?? '',
      stderr: decoded['stderr']?.toString() ?? '',
    );
  }

  Map<String, String> _flyEnvironment() {
    return <String, String>{
      'FLY_API_TOKEN': apiToken,
      'FLY_APP': appName,
    };
  }

  String _asSandboxShell(String command) {
    final quoted = _shellQuote(command);
    final selector = r'if [ "$(id -u)" = "0" ]; then '
        'exec su -s /bin/sh sandbox -c $quoted; '
        'else exec /bin/sh -lc $quoted; fi';
    return '/bin/sh -lc ${_shellQuote(selector)}';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _requireMachineId(RunnerSession session) {
    final machineId = session.runtimeId;
    if (machineId == null || machineId.isEmpty) {
      throw StateError('Fly Machine runtime has not been prepared.');
    }
    return machineId;
  }

  Future<int> _reserveLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _waitForPreview(
    int localPort, {
    required Duration timeout,
    required int? Function() proxyExitCode,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      final proxyCode = proxyExitCode();
      if (proxyCode != null) {
        throw StateError('fly proxy exited early with code $proxyCode');
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$localPort/'),
        );
        final response = await request.close().timeout(
              const Duration(seconds: 5),
            );
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return;
        lastError = 'HTTP ${response.statusCode}';
      } catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    throw TimeoutException(
      'Flutter preview did not become reachable. Last error: $lastError',
      timeout,
    );
  }
}

class _MachineExecResult {
  const _MachineExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
