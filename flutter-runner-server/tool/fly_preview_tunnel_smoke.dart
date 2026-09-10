import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_practice_runner_server/src/execution/fly_machine_exec_execution_backend.dart';
import 'package:flutter_practice_runner_server/src/runner_session.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final appName = (environment['FLY_RUNTIME_APP'] ?? '').trim();
  final apiToken = (environment['FLY_API_TOKEN'] ?? '').trim();
  final image = (environment['FLY_RUNTIME_IMAGE'] ?? '').trim();
  final region = (environment['FLY_RUNTIME_REGION'] ?? 'sin').trim();
  final flyctl = (environment['FLYCTL_EXECUTABLE'] ?? 'flyctl').trim();

  if (appName.isEmpty || apiToken.isEmpty || image.isEmpty) {
    stderr.writeln(
      'FLY_RUNTIME_APP, FLY_API_TOKEN, and FLY_RUNTIME_IMAGE are required.',
    );
    exitCode = 64;
    return;
  }

  final directory = await Directory.systemTemp.createTemp(
    'fly-preview-smoke-',
  );
  final session = RunnerSession(
    id: 'fly-preview-${DateTime.now().microsecondsSinceEpoch}',
    directory: directory,
    createdAt: DateTime.now().toUtc(),
  );
  final backend = FlyMachineExecExecutionBackend(
    appName: appName,
    apiToken: apiToken,
    image: image,
    region: region,
    flyctlExecutable: flyctl,
    memoryMb: 2048,
    cpus: 1,
    flutterExecutable: '/opt/flutter/bin/flutter',
    dartExecutable: '/opt/flutter/bin/cache/dart-sdk/bin/dart',
    dartFrogExecutable: '/home/sandbox/.pub-cache/bin/dart_frog',
    serverpodExecutable: '/home/sandbox/.pub-cache/bin/serverpod',
  );

  Process? proxyProcess;
  final proxyStderr = <String>[];

  try {
    stdout.writeln('[preview] Creating Fly Machine...');
    await backend.prepareSession(session);

    stdout.writeln('[preview] Creating Flutter web project...');
    final createExit = await backend.runFlutterCommand(
      session,
      const <String>[
        'create',
        '--no-pub',
        '--platforms=web',
        '--project-name=fly_preview_smoke',
        '.',
      ],
    );
    if (createExit != 0) {
      throw StateError('flutter create exited with $createExit');
    }

    stdout.writeln('[preview] Running flutter pub get...');
    final pubExit = await backend.runFlutterCommand(
      session,
      const <String>['pub', 'get'],
    );
    if (pubExit != 0) {
      throw StateError('flutter pub get exited with $pubExit');
    }

    final machineId = session.runtimeId;
    if (machineId == null || machineId.isEmpty) {
      throw StateError('Fly Machine id is missing.');
    }

    stdout.writeln('[preview] Starting Flutter web-server on remote port 8080...');
    final startCommand = _shellCommand(<String>[
      'cd /workspace',
      'nohup /opt/flutter/bin/flutter run -d web-server '
          '--web-hostname=:: --web-port=8080 '
          '> /tmp/flutter-preview.log 2>&1 < /dev/null & '
          'echo \$! > /tmp/flutter-preview.pid',
    ]);
    final startResult = await _machineExec(
      flyctl: flyctl,
      appName: appName,
      apiToken: apiToken,
      machineId: machineId,
      command: startCommand,
    );
    if (startResult.exitCode != 0) {
      throw StateError(
        'remote Flutter preview launcher exited with '
        '${startResult.exitCode}: ${startResult.stderr}',
      );
    }

    final localPort = await _reservePort();
    final remoteHost = '$machineId.vm.$appName.internal';

    stdout.writeln(
      '[preview] Opening private Fly WireGuard proxy '
      '127.0.0.1:$localPort -> $remoteHost:8080...',
    );

    proxyProcess = await Process.start(
      flyctl,
      <String>[
        'proxy',
        '$localPort:8080',
        remoteHost,
        '--app',
        appName,
        '--bind-addr',
        '127.0.0.1',
        '--quiet',
      ],
      environment: <String, String>{
        'FLY_API_TOKEN': apiToken,
        'FLY_APP': appName,
      },
      includeParentEnvironment: true,
      runInShell: false,
    );

    unawaited(
      proxyProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => stdout.writeln('[fly proxy] $line')),
    );
    unawaited(
      proxyProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        proxyStderr.add(line);
        stderr.writeln('[fly proxy] $line');
      }),
    );

    int? proxyExitCode;
    unawaited(proxyProcess.exitCode.then((value) => proxyExitCode = value));

    stdout.writeln('[preview] Waiting for Flutter preview HTTP 200...');
    final html = await _waitForPreview(
      localPort,
      timeout: const Duration(seconds: 120),
      proxyExitCode: () => proxyExitCode,
    );

    if (!html.toLowerCase().contains('<html')) {
      throw StateError('Preview returned HTTP 200 but did not look like HTML.');
    }

    stdout.writeln('FLY_PRIVATE_PREVIEW_TUNNEL_OK');
  } catch (error, stackTrace) {
    final machineId = session.runtimeId;
    if (machineId != null && machineId.isNotEmpty) {
      try {
        final logs = await _machineExec(
          flyctl: flyctl,
          appName: appName,
          apiToken: apiToken,
          machineId: machineId,
          command: _shellCommand(
            const <String>[
              'cat /tmp/flutter-preview.log 2>/dev/null || true',
            ],
          ),
        );
        if (logs.stdout.trim().isNotEmpty) {
          stderr.writeln('--- remote flutter preview log ---');
          stderr.writeln(logs.stdout.trimRight());
          stderr.writeln('--- end remote flutter preview log ---');
        }
      } catch (_) {}
    }

    if (proxyStderr.isNotEmpty) {
      stderr.writeln('--- fly proxy stderr ---');
      for (final line in proxyStderr) {
        stderr.writeln(line);
      }
      stderr.writeln('--- end fly proxy stderr ---');
    }

    stderr.writeln('[preview] FAILED: $error');
    stderr.writeln(stackTrace);
    rethrow;
  } finally {
    final process = proxyProcess;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }

    try {
      await backend.disposeSession(session);
    } catch (error) {
      stderr.writeln('[preview] cleanup warning: $error');
    }

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<String> _waitForPreview(
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
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.ok) {
        return body;
      }
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

Future<_ExecResult> _machineExec({
  required String flyctl,
  required String appName,
  required String apiToken,
  required String machineId,
  required String command,
}) async {
  final processResult = await Process.run(
    flyctl,
    <String>[
      'machine',
      'exec',
      machineId,
      command,
      '--app',
      appName,
      '--json',
    ],
    environment: <String, String>{
      'FLY_API_TOKEN': apiToken,
      'FLY_APP': appName,
    },
    includeParentEnvironment: true,
    runInShell: false,
  );

  if (processResult.exitCode != 0) {
    return _ExecResult(
      exitCode: processResult.exitCode,
      stdout: '${processResult.stdout}',
      stderr: '${processResult.stderr}',
    );
  }

  final raw = '${processResult.stdout}'.trim();
  if (raw.isEmpty) {
    return const _ExecResult(exitCode: 0, stdout: '', stderr: '');
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

  return _ExecResult(
    exitCode: remoteExitCode,
    stdout: decoded['stdout']?.toString() ?? '',
    stderr: decoded['stderr']?.toString() ?? '',
  );
}

String _shellCommand(List<String> commands) {
  final body = commands.join('; ');
  return '/bin/sh -lc ${_shellQuote(body)}';
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\\\"'\\\"'")}'";
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _ExecResult {
  const _ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
