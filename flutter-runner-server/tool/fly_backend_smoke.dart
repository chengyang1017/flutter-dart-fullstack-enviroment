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
    'fly-backend-smoke-',
  );
  final session = RunnerSession(
    id: 'fly-smoke-${DateTime.now().microsecondsSinceEpoch}',
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

  try {
    stdout.writeln('[smoke] Creating Fly Machine...');
    await backend.prepareSession(session);

    stdout.writeln('[smoke] flutter --version');
    final versionExit = await backend.runFlutterCommand(
      session,
      const <String>['--version'],
    );
    if (versionExit != 0) {
      throw StateError('flutter --version exited with $versionExit');
    }

    stdout.writeln('[smoke] flutter create');
    final createExit = await backend.runFlutterCommand(
      session,
      const <String>[
        'create',
        '--no-pub',
        '--platforms=web',
        '--project-name=fly_backend_smoke',
        '.',
      ],
    );
    if (createExit != 0) {
      throw StateError('flutter create exited with $createExit');
    }

    stdout.writeln('[smoke] Pulling /workspace with Fly SFTP...');
    await backend.pullWorkspace(session);

    final pubspec = File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (!await pubspec.exists()) {
      throw StateError('pubspec.yaml was not pulled back from Fly.');
    }

    final probe = File(
      '${directory.path}${Platform.pathSeparator}fly_backend_probe.dart',
    );
    await probe.writeAsString(
      "void main() { print('FLY_BACKEND_SMOKE_OK'); }\n",
      flush: true,
    );

    stdout.writeln('[smoke] Pushing workspace back to Fly...');
    await backend.syncWorkspace(
      session,
      removedPaths: const <String>{},
    );

    stdout.writeln('[smoke] Running Dart file from synced workspace...');
    final dartExit = await backend.runDartCommand(
      session,
      const <String>['fly_backend_probe.dart'],
      workingDirectory: '.',
    );
    if (dartExit != 0) {
      throw StateError('remote Dart probe exited with $dartExit');
    }

    for (final log in session.logs) {
      stdout.writeln(log.message);
    }

    stdout.writeln('FLY_EXECUTION_BACKEND_PHASE1_OK');
  } catch (error, stackTrace) {
    for (final log in session.logs) {
      stderr.writeln(log.message);
    }
    stderr.writeln('[smoke] FAILED: $error');
    stderr.writeln(stackTrace);
    rethrow;
  } finally {
    try {
      await backend.disposeSession(session);
    } catch (error) {
      stderr.writeln('[smoke] cleanup warning: $error');
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
