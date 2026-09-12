import 'dart:async';
import 'dart:io';

import 'package:flutter_practice_runner_server/src/execution/docker_execution_backend.dart';
import 'package:flutter_practice_runner_server/src/execution/execution_backend.dart';
import 'package:flutter_practice_runner_server/src/execution/fly_preview_execution_backend.dart';
import 'package:flutter_practice_runner_server/src/execution/local_execution_backend.dart';
import 'package:flutter_practice_runner_server/src/runner_authenticator.dart';
import 'package:flutter_practice_runner_server/src/runner_server.dart';
import 'package:flutter_practice_runner_server/src/session_manager.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final platformPort = environment['PORT'];
  final host = environment['RUNNER_HOST'] ??
      (platformPort == null || platformPort.isEmpty ? '127.0.0.1' : '0.0.0.0');
  final port = int.tryParse(
        environment['RUNNER_PORT'] ?? platformPort ?? '',
      ) ??
      8787;
  final allowedOrigin = environment['RUNNER_ALLOWED_ORIGIN'] ?? '*';
  final idleMinutes = int.tryParse(
        environment['RUNNER_IDLE_MINUTES'] ?? '',
      ) ??
      20;
  final allowTerminalCommands =
      (environment['RUNNER_ENABLE_TERMINAL'] ?? '').trim().toLowerCase() ==
          'true';
  final maxSessionsPerUser = (int.tryParse(
            environment['RUNNER_MAX_SESSIONS_PER_USER'] ?? '',
          ) ??
          2)
      .clamp(1, 16)
      .toInt();
  final maxTotalSessions = (int.tryParse(
            environment['RUNNER_MAX_TOTAL_SESSIONS'] ?? '',
          ) ??
          4)
      .clamp(1, 64)
      .toInt();
  final maxRequestBytes = (int.tryParse(
            environment['RUNNER_MAX_REQUEST_BYTES'] ?? '',
          ) ??
          32 * 1024 * 1024)
      .clamp(1024, 128 * 1024 * 1024)
      .toInt();
  final maxWorkspaceFiles = (int.tryParse(
            environment['RUNNER_MAX_WORKSPACE_FILES'] ?? '',
          ) ??
          5000)
      .clamp(1, 20000)
      .toInt();
  final maxFileBytes = (int.tryParse(
            environment['RUNNER_MAX_FILE_BYTES'] ?? '',
          ) ??
          8 * 1024 * 1024)
      .clamp(1024, 32 * 1024 * 1024)
      .toInt();
  final maxWorkspaceBytes = (int.tryParse(
            environment['RUNNER_MAX_WORKSPACE_BYTES'] ?? '',
          ) ??
          24 * 1024 * 1024)
      .clamp(1024, 96 * 1024 * 1024)
      .toInt();
  final publicBaseUrl = _normalizePublicBaseUrl(
    environment['RUNNER_PUBLIC_BASE_URL'] ?? 'http://localhost:$port',
  );
  final previewUrlTemplate = environment['RUNNER_PREVIEW_URL_TEMPLATE'] ??
      '$publicBaseUrl/preview/{sessionId}/{accessKey}/';
  final backendUrlTemplate = environment['RUNNER_BACKEND_URL_TEMPLATE'] ??
      '$publicBaseUrl/backend/{sessionId}/{accessKey}/';
  final workspaceRoot = Directory(
    environment['RUNNER_WORKSPACE_ROOT'] ??
        '${Directory.systemTemp.path}${Platform.pathSeparator}flutter-practice-runner',
  );
  final workspaceStorageApiUrl =
      (environment['WORKSPACE_STORAGE_API_URL'] ?? '').trim();
  final staticAuthTokens = (environment['RUNNER_AUTH_TOKENS'] ?? '').trim();
  final requestedAuthMode = (environment['RUNNER_AUTH_MODE'] ?? '').trim();
  final authMode = requestedAuthMode.isNotEmpty
      ? requestedAuthMode.toLowerCase()
      : workspaceStorageApiUrl.isNotEmpty
          ? 'workspace'
          : 'static';
  final authCacheSeconds = int.tryParse(
        environment['RUNNER_AUTH_CACHE_SECONDS'] ?? '',
      ) ??
      15;

  late final RunnerAuthenticator authenticator;
  late final String authenticationLabel;

  try {
    switch (authMode) {
      case 'workspace':
        if (workspaceStorageApiUrl.isEmpty) {
          throw const FormatException(
            'WORKSPACE_STORAGE_API_URL is required when '
            'RUNNER_AUTH_MODE=workspace.',
          );
        }
        authenticator = WorkspaceAccountRunnerAuthenticator(
          baseUri: Uri.parse(workspaceStorageApiUrl),
          cacheTtl: Duration(
            seconds: authCacheSeconds.clamp(0, 300).toInt(),
          ),
        );
        authenticationLabel = 'workspace account bearer';
        break;
      case 'static':
        if (staticAuthTokens.isEmpty) {
          throw const FormatException(
            'RUNNER_AUTH_TOKENS is required when RUNNER_AUTH_MODE=static.',
          );
        }
        authenticator =
            StaticBearerRunnerAuthenticator.fromJson(staticAuthTokens);
        authenticationLabel = 'static bearer';
        break;
      default:
        throw FormatException(
          'RUNNER_AUTH_MODE must be workspace or static: $authMode',
        );
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final executionBackend = _createExecutionBackend(environment);

  final publicUri = Uri.tryParse(publicBaseUrl);
  final publicWorkspaceRunner = authMode == 'workspace' &&
      publicUri != null &&
      publicUri.scheme.toLowerCase() == 'https';
  final allowLocalPublicExecution =
      (environment['RUNNER_ALLOW_LOCAL_PUBLIC_EXECUTION'] ?? '')
              .trim()
              .toLowerCase() ==
          'true';

  if (publicWorkspaceRunner &&
      executionBackend.name != 'docker' &&
      executionBackend.name != 'fly' &&
      !allowLocalPublicExecution) {
    stderr.writeln(
      'Refusing public Workspace Runner startup with '
      '${executionBackend.name} execution. Set RUNNER_EXECUTION_MODE=docker or fly. '
      'RUNNER_ALLOW_LOCAL_PUBLIC_EXECUTION=true is an explicit unsafe override.',
    );
    exitCode = 64;
    if (authenticator is WorkspaceAccountRunnerAuthenticator) {
      authenticator.close();
    }
    return;
  }

  final manager = SessionManager(
    rootDirectory: workspaceRoot,
    executionBackend: executionBackend,
    previewUrlTemplate: previewUrlTemplate,
    backendUrlTemplate: backendUrlTemplate,
  );
  final runnerServer = RunnerServer(
    manager: manager,
    authenticator: authenticator,
    allowedOrigin: allowedOrigin,
    allowTerminalCommands: allowTerminalCommands,
    maxSessionsPerUser: maxSessionsPerUser,
    maxTotalSessions: maxTotalSessions,
    maxRequestBytes: maxRequestBytes,
    maxWorkspaceFiles: maxWorkspaceFiles,
    maxFileBytes: maxFileBytes,
    maxWorkspaceBytes: maxWorkspaceBytes,
  );

  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'Flutter Practice Runner listening on http://$host:${server.port}',
  );
  stdout.writeln('Workspace root: ${workspaceRoot.path}');
  stdout.writeln('Execution backend: ${executionBackend.name}');
  stdout.writeln('Idle session timeout: $idleMinutes minutes');
  stdout.writeln('Runner authentication: $authenticationLabel');
  stdout.writeln(
    'Runner limits: sessions/user=$maxSessionsPerUser, '
    'total sessions=$maxTotalSessions, '
    'request bytes=$maxRequestBytes, '
    'workspace files=$maxWorkspaceFiles.',
  );
  stdout.writeln(
    'Runner terminal: ${allowTerminalCommands ? 'enabled' : 'disabled'}',
  );
  if (publicWorkspaceRunner && allowedOrigin == '*') {
    stderr.writeln(
      'Warning: RUNNER_ALLOWED_ORIGIN is *. '
      'Set it to the production web origin before public launch.',
    );
  }
  stdout.writeln('Public runtime gateway: $publicBaseUrl');

  final cleanupTimer = Timer.periodic(
    const Duration(minutes: 1),
    (_) {
      unawaited(() async {
        final removed = await manager.disposeIdleSessions(
          Duration(minutes: idleMinutes),
        );
        if (removed > 0) {
          stdout.writeln('Disposed $removed idle runner session(s).');
        }
      }());
    },
  );

  var shuttingDown = false;
  Future<void> shutdown() async {
    if (shuttingDown) return;
    shuttingDown = true;
    cleanupTimer.cancel();
    stdout.writeln('Stopping Flutter Practice Runner...');
    await server.close(force: true);
    runnerServer.close();
    if (authenticator is WorkspaceAccountRunnerAuthenticator) {
      authenticator.close();
    }
    await manager.dispose();
  }

  ProcessSignal.sigint.watch().listen((_) {
    unawaited(shutdown());
  });

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      unawaited(shutdown());
    });
  }

  await for (final request in server) {
    unawaited(runnerServer.handle(request));
  }
}

RunnerExecutionBackend _createExecutionBackend(
  Map<String, String> environment,
) {
  final mode =
      (environment['RUNNER_EXECUTION_MODE'] ?? 'local').trim().toLowerCase();

  switch (mode) {
    case 'local':
      return LocalExecutionBackend(
        flutterExecutable: environment['FLUTTER_EXECUTABLE'] ?? 'flutter',
        dartExecutable: environment['DART_EXECUTABLE'] ?? 'dart',
        dartFrogExecutable: environment['DART_FROG_EXECUTABLE'] ?? 'dart_frog',
        serverpodExecutable: environment['SERVERPOD_EXECUTABLE'] ?? 'serverpod',
      );
    case 'docker':
      return DockerExecutionBackend(
        dockerExecutable: environment['DOCKER_EXECUTABLE'] ?? 'docker',
        image: environment['RUNNER_DOCKER_IMAGE'] ??
            'flutter-practice-runner:local',
        flutterExecutable:
            environment['RUNNER_CONTAINER_FLUTTER_EXECUTABLE'] ?? 'flutter',
        dartExecutable:
            environment['RUNNER_CONTAINER_DART_EXECUTABLE'] ?? 'dart',
        dartFrogExecutable:
            environment['RUNNER_CONTAINER_DART_FROG_EXECUTABLE'] ?? 'dart_frog',
        serverpodExecutable:
            environment['RUNNER_CONTAINER_SERVERPOD_EXECUTABLE'] ?? 'serverpod',
        memoryLimit: environment['RUNNER_DOCKER_MEMORY'] ?? '1024m',
        cpuLimit: environment['RUNNER_DOCKER_CPUS'] ?? '1.0',
        pidsLimit: int.tryParse(
              environment['RUNNER_DOCKER_PIDS_LIMIT'] ?? '',
            ) ??
            256,
        network: environment['RUNNER_DOCKER_NETWORK'],
        runnerOwnership:
            environment['RUNNER_DOCKER_RUNNER_OWNERSHIP'] ?? '10001:10001',
      );
    case 'fly':
      return FlyPreviewExecutionBackend(
        appName: environment['FLY_RUNTIME_APP'] ?? '',
        apiToken: environment['FLY_API_TOKEN'] ?? '',
        image: environment['FLY_RUNTIME_IMAGE'] ??
            'docker.io/chengyang1017/flutter-sandbox-runner:cloudflare-20260910155454',
        region: environment['FLY_RUNTIME_REGION'] ?? 'sin',
        flyctlExecutable: environment['FLYCTL_EXECUTABLE'] ?? 'flyctl',
        tarExecutable: environment['TAR_EXECUTABLE'] ?? 'tar',
        cpuKind: environment['FLY_RUNTIME_CPU_KIND'] ?? 'shared',
        cpus: int.tryParse(environment['FLY_RUNTIME_CPUS'] ?? '') ?? 1,
        memoryMb:
            int.tryParse(environment['FLY_RUNTIME_MEMORY_MB'] ?? '') ?? 2048,
        flutterExecutable: environment['RUNNER_CONTAINER_FLUTTER_EXECUTABLE'] ??
            '/opt/flutter/bin/flutter',
        dartExecutable: environment['RUNNER_CONTAINER_DART_EXECUTABLE'] ??
            '/opt/flutter/bin/cache/dart-sdk/bin/dart',
        dartFrogExecutable:
            environment['RUNNER_CONTAINER_DART_FROG_EXECUTABLE'] ??
                '/home/sandbox/.pub-cache/bin/dart_frog',
        serverpodExecutable:
            environment['RUNNER_CONTAINER_SERVERPOD_EXECUTABLE'] ??
                '/home/sandbox/.pub-cache/bin/serverpod',
        remotePreviewPort:
            int.tryParse(environment['FLY_RUNTIME_PREVIEW_PORT'] ?? '') ?? 8080,
      );
    default:
      throw ArgumentError.value(
        mode,
        'RUNNER_EXECUTION_MODE',
        'Expected local, docker, or fly.',
      );
  }
}

String _normalizePublicBaseUrl(String value) {
  var result = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  if (result.isEmpty) {
    throw const FormatException('RUNNER_PUBLIC_BASE_URL cannot be empty.');
  }

  final uri = Uri.tryParse(result);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw FormatException(
      'RUNNER_PUBLIC_BASE_URL must be an absolute http/https URL: $value',
    );
  }

  return result;
}
