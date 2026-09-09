import 'dart:convert';
import 'dart:io';

import 'runner_authenticator.dart';
import 'runner_session.dart';
import 'session_manager.dart';

class RunnerServer {
  RunnerServer({
    required this.manager,
    required this.authenticator,
    this.allowedOrigin = '*',
  });

  static const _supportedFirebaseCapabilities = <String>{
    'auth',
    'firestore',
    'storage',
    'messaging',
    'functions',
  };
  static const _binaryFilePrefix = '\u0000workspace-base64:';

  final SessionManager manager;
  final RunnerAuthenticator authenticator;
  final String allowedOrigin;
  final Map<String, String> _sessionOwners = <String, String>{};

  Future<void> handle(HttpRequest request) async {
    if (request.method == 'OPTIONS') {
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' &&
          segments.length == 1 &&
          segments.first == 'health') {
        await _sendJson(request.response, HttpStatus.ok, {
          'status': 'ok',
          'activeSessions': manager.sessions.length,
        });
        return;
      }

      if (segments.isEmpty || segments.first != 'sessions') {
        await _sendError(
          request.response,
          HttpStatus.notFound,
          'Route not found.',
        );
        return;
      }

      final userId = await authenticator.authenticate(request);
      if (userId == null) {
        await _sendError(
          request.response,
          HttpStatus.unauthorized,
          'Authentication required.',
        );
        return;
      }

      if (segments.length == 1 && request.method == 'POST') {
        final body = await _readJsonObject(request);
        final files = _readFiles(body['files']);
        final capabilities = _readFirebaseCapabilities(
          body['firebaseCapabilities'],
        );
        final projectName = _readOptionalProjectName(
          body['projectName'],
        );
        final platforms = _readOptionalPlatforms(
          body['platforms'],
        );
        final includeWorkspace = body['includeWorkspace'] == true;

        final session = await manager.createSession(
          files,
          projectName: projectName ?? 'flutter_practice',
          platforms: platforms ?? const <String>['web'],
        );

        await _restoreBinaryFiles(session, files);
        _sessionOwners[session.id] = userId;
        session.setFirebaseCapabilities(
          capabilities ?? const <String>{},
        );

        final responseBody = <String, Object?>{
          'session': session.toJson(),
        };

        if (includeWorkspace) {
          responseBody['workspace'] = await manager.readWorkspaceTree(session);
        }

        await _sendJson(
          request.response,
          HttpStatus.created,
          responseBody,
        );
        return;
      }

      if (segments.length < 2) {
        await _sendError(
          request.response,
          HttpStatus.notFound,
          'Route not found.',
        );
        return;
      }

      final sessionId = segments[1];

      if (segments.length == 2 && request.method == 'GET') {
        final session = _requireOwnedSession(sessionId, userId);
        session.touch();
        final afterLog = int.tryParse(
              request.uri.queryParameters['afterLog'] ?? '0',
            ) ??
            0;
        final safeCursor = afterLog.clamp(0, session.logs.length).toInt();
        final logs = session.logs
            .skip(safeCursor)
            .map((entry) => entry.toJson())
            .toList(growable: false);
        await _sendJson(request.response, HttpStatus.ok, {
          'session': session.toJson(),
          'logs': logs,
          'nextLogIndex': session.logs.length,
        });
        return;
      }

      if (segments.length == 2 && request.method == 'DELETE') {
        _requireOwnedSession(sessionId, userId);
        await manager.disposeSession(sessionId);
        _sessionOwners.remove(sessionId);
        await _sendEmpty(request.response, HttpStatus.noContent);
        return;
      }

      if (segments.length == 3 &&
          segments[2] == 'workspace' &&
          request.method == 'PUT') {
        final session = _requireOwnedSession(sessionId, userId);
        final body = await _readJsonObject(request);
        final files = _readFiles(body['files']);
        final capabilities = _readFirebaseCapabilities(
          body['firebaseCapabilities'],
        );
        await manager.syncWorkspace(session, files);
        await _restoreBinaryFiles(session, files);
        if (capabilities != null) {
          session.setFirebaseCapabilities(capabilities);
        }
        await _sendJson(
          request.response,
          HttpStatus.ok,
          {'session': session.toJson()},
        );
        return;
      }

      if (segments.length == 3 && request.method == 'POST') {
        final session = _requireOwnedSession(sessionId, userId);
        switch (segments[2]) {
          case 'pub-get':
            final result = await _runPubGet(session);
            await _sendJson(
              request.response,
              HttpStatus.ok,
              result,
            );
            return;
          case 'command':
            final body = await _readJsonObject(request);
            final command = _readTerminalCommand(body['command']);
            final exitCode = await _runTerminalCommand(session, command);
            await _sendJson(
              request.response,
              HttpStatus.ok,
              <String, Object?>{
                'session': session.toJson(),
                'exitCode': exitCode,
              },
            );
            return;
          case 'run':
            await manager.run(session);
            await _sendAccepted(request.response, session);
            return;
          case 'hot-reload':
            await manager.hotReload(session);
            await _sendAccepted(request.response, session);
            return;
          case 'hot-restart':
            await manager.hotRestart(session);
            await _sendAccepted(request.response, session);
            return;
          case 'stop':
            await manager.stop(session);
            await _sendAccepted(request.response, session);
            return;
        }
      }

      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Route not found.',
      );
    } on RunnerSessionNotFound catch (error) {
      await _sendError(request.response, HttpStatus.notFound, error.toString());
    } on FormatException catch (error) {
      await _sendError(request.response, HttpStatus.badRequest, error.toString());
    } on StateError catch (error) {
      await _sendError(request.response, HttpStatus.conflict, error.toString());
    } catch (error, stackTrace) {
      stderr.writeln('Runner request failed: $error');
      stderr.writeln(stackTrace);
      await _sendError(
        request.response,
        HttpStatus.internalServerError,
        error.toString(),
      );
    }
  }

  Future<int> _runTerminalCommand(
    RunnerSession session,
    String command,
  ) async {
    session.touch();

    final Process process;
    if (manager.executionBackend.name == 'docker') {
      await manager.executionBackend.prepareSession(session);
      final runtimeId = session.runtimeId;
      if (runtimeId == null || runtimeId.isEmpty) {
        throw StateError('Docker Runner terminal is not ready.');
      }
      process = await Process.start(
        'docker',
        <String>[
          'exec',
          '--interactive',
          '--workdir',
          '/workspace',
          runtimeId,
          'sh',
          '-lc',
          command,
        ],
        runInShell: false,
      );
    } else if (Platform.isWindows) {
      const utf8Preamble =
          r'[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); ';
      process = await Process.start(
        'powershell.exe',
        <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '$utf8Preamble$command',
        ],
        workingDirectory: session.directory.path,
        runInShell: false,
      );
    } else {
      process = await Process.start(
        '/bin/sh',
        <String>['-lc', command],
        workingDirectory: session.directory.path,
        runInShell: false,
      );
    }

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(session.addLog);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => session.addLog('[terminal stderr] $line'));
    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return exitCode;
  }

  String _readTerminalCommand(Object? value) {
    if (value is! String) {
      throw const FormatException('command must be a string.');
    }
    final command = value.trim();
    if (command.isEmpty) {
      throw const FormatException('command cannot be empty.');
    }
    if (command.length > 4096) {
      throw const FormatException('command is too long.');
    }
    return command;
  }

  Future<Map<String, Object?>> _runPubGet(
    RunnerSession session,
  ) async {
    if (session.process != null || session.backendProcess != null) {
      throw StateError(
        'Stop the running Flutter/backend process before flutter pub get.',
      );
    }

    final previousStatus = session.status;
    session.setStatus('syncing');
    session.addLog('[runner] flutter pub get');

    try {
      final exitCode = await manager.executionBackend.runFlutterCommand(
        session,
        const <String>['pub', 'get'],
      );

      if (exitCode != 0) {
        throw StateError(
          'flutter pub get exited with code $exitCode',
        );
      }

      await manager.executionBackend.pullWorkspace(session);

      final lockFile = _workspaceFile(session, 'pubspec.lock');
      final packageConfig = _workspaceFile(
        session,
        '.dart_tool/package_config.json',
      );

      final lockContent = await lockFile.exists()
          ? await lockFile.readAsString()
          : null;
      final hasPackageConfig = await packageConfig.exists();

      session.setStatus(
        previousStatus == 'stopped' ? 'stopped' : 'ready',
      );
      session.addLog('[runner] flutter pub get completed.');

      return <String, Object?>{
        'session': session.toJson(),
        'lockFile': lockContent,
        'hasPackageConfig': hasPackageConfig,
      };
    } catch (_) {
      session.setStatus('error');
      rethrow;
    }
  }

  File _workspaceFile(
    RunnerSession session,
    String path,
  ) {
    return File(
      <String>[
        session.directory.path,
        ...path.split('/'),
      ].join(Platform.pathSeparator),
    );
  }

  String? _readOptionalProjectName(Object? value) {
    if (value == null) return null;

    if (value is! String) {
      throw const FormatException(
        'projectName must be a string.',
      );
    }

    return value;
  }

  List<String>? _readOptionalPlatforms(Object? value) {
    if (value == null) return null;

    if (value is! Iterable) {
      throw const FormatException(
        'platforms must be a JSON array.',
      );
    }

    final platforms = <String>[];

    for (final item in value) {
      if (item is! String) {
        throw const FormatException(
          'Every platform must be a string.',
        );
      }

      platforms.add(item);
    }

    return platforms;
  }

  RunnerSession _requireOwnedSession(String sessionId, String userId) {
    if (_sessionOwners[sessionId] != userId) {
      throw RunnerSessionNotFound(sessionId);
    }
    try {
      return manager.requireSession(sessionId);
    } on RunnerSessionNotFound {
      _sessionOwners.remove(sessionId);
      rethrow;
    }
  }

  Future<void> _restoreBinaryFiles(
    RunnerSession session,
    Map<String, String> files,
  ) async {
    var restored = 0;
    for (final entry in files.entries) {
      if (!entry.value.startsWith(_binaryFilePrefix)) continue;

      final encoded = entry.value.substring(_binaryFilePrefix.length);
      final List<int> bytes;
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw FormatException(
          'Invalid binary Workspace payload: ${entry.key}',
        );
      }

      final file = File(
        <String>[
          session.directory.path,
          ...entry.key.split('/'),
        ].join(Platform.pathSeparator),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      restored += 1;
    }

    if (restored == 0) return;

    await manager.executionBackend.syncWorkspace(
      session,
      removedPaths: const <String>{},
    );
    session.addLog('[runner] Restored $restored binary Workspace assets.');
  }

  Future<void> _sendAccepted(HttpResponse response, RunnerSession session) {
    return _sendJson(
      response,
      HttpStatus.accepted,
      {'session': session.toJson()},
    );
  }

  Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
    final source = await utf8.decoder.bind(request).join();
    if (source.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Request body must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, String> _readFiles(Object? value) {
    if (value is! Map) {
      throw const FormatException('files must be a JSON object.');
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
          'Workspace files must map string paths to string contents.',
        );
      }
      result[entry.key as String] = entry.value as String;
    }
    return result;
  }

  Set<String>? _readFirebaseCapabilities(Object? value) {
    if (value == null) return null;
    if (value is! Iterable) {
      throw const FormatException(
        'firebaseCapabilities must be a JSON array.',
      );
    }
    final result = <String>{};
    for (final item in value) {
      if (item is! String || !_supportedFirebaseCapabilities.contains(item)) {
        throw FormatException('Unsupported Firebase capability: $item');
      }
      result.add(item);
    }
    return result;
  }

  Future<void> _sendError(
    HttpResponse response,
    int statusCode,
    String message,
  ) {
    return _sendJson(response, statusCode, {'error': message});
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    _setCors(response);
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _sendEmpty(HttpResponse response, int statusCode) async {
    _setCors(response);
    response.statusCode = statusCode;
    await response.close();
  }

  void _setCors(HttpResponse response) {
    response.headers.set('access-control-allow-origin', allowedOrigin);
    response.headers.set(
      'access-control-allow-methods',
      'GET, POST, PUT, DELETE, OPTIONS',
    );
    response.headers.set(
      'access-control-allow-headers',
      'authorization, content-type, accept',
    );
    response.headers.set('cache-control', 'no-store');
  }
}
