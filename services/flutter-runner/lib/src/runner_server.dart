import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'runner_authenticator.dart';
import 'runner_session.dart';
import 'session_manager.dart';

class RunnerServer {
  RunnerServer({
    required this.manager,
    required this.authenticator,
    this.allowedOrigin = '*',
    this.allowTerminalCommands = false,
    this.maxSessionsPerUser = 2,
    this.maxTotalSessions = 4,
    this.maxRequestBytes = 32 * 1024 * 1024,
    this.maxWorkspaceFiles = 5000,
    this.maxFileBytes = 8 * 1024 * 1024,
    this.maxWorkspaceBytes = 24 * 1024 * 1024,
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
  final bool allowTerminalCommands;
  final int maxSessionsPerUser;
  final int maxTotalSessions;
  final int maxRequestBytes;
  final int maxWorkspaceFiles;
  final int maxFileBytes;
  final int maxWorkspaceBytes;
  final Map<String, String> _sessionOwners = <String, String>{};
  final HttpClient _proxyClient = HttpClient();

  void close() {
    _proxyClient.close(force: true);
  }

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

      if (segments.isNotEmpty &&
          (segments.first == 'preview' || segments.first == 'backend')) {
        await _proxyRuntimeGateway(request, segments);
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

        if (manager.sessions.length >= maxTotalSessions) {
          await _sendError(
            request.response,
            HttpStatus.tooManyRequests,
            'Runner is at its active session limit. Try again later.',
          );
          return;
        }

        if (_activeSessionCountForUser(userId) >= maxSessionsPerUser) {
          await _sendError(
            request.response,
            HttpStatus.tooManyRequests,
            'You already have the maximum number of active Runner sessions.',
          );
          return;
        }

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
            if (!allowTerminalCommands) {
              await _sendError(
                request.response,
                HttpStatus.forbidden,
                'Terminal commands are disabled on this Runner.',
              );
              return;
            }
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
    } on RunnerPayloadTooLarge catch (error) {
      await _sendError(
        request.response,
        HttpStatus.requestEntityTooLarge,
        error.message,
      );
    } on FormatException catch (error) {
      await _sendError(
          request.response, HttpStatus.badRequest, error.toString());
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

  Future<void> _proxyRuntimeGateway(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (segments.length < 3) {
      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Runtime gateway route not found.',
      );
      return;
    }

    final kind = segments[0];
    final sessionId = segments[1];
    final accessKey = segments[2];

    RunnerSession session;
    try {
      session = manager.requireSession(sessionId);
    } on RunnerSessionNotFound {
      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Runtime session not found.',
      );
      return;
    }

    if (session.publicAccessKey != accessKey) {
      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Runtime session not found.',
      );
      return;
    }

    final targetPort = kind == 'preview'
        ? session.previewGatewayPort
        : session.backendGatewayPort;
    if (targetPort == null) {
      await _sendError(
        request.response,
        HttpStatus.serviceUnavailable,
        '$kind runtime is not running.',
      );
      return;
    }

    session.touch();

    final remainingSegments = segments.skip(3).toList(growable: false);
    final targetPath =
        remainingSegments.isEmpty ? '/' : '/${remainingSegments.join('/')}';
    final targetUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: targetPort,
      path: targetPath,
      query: request.uri.query.isEmpty ? null : request.uri.query,
    );
    final gatewayBasePath = '/$kind/$sessionId/$accessKey/';

    if (WebSocketTransformer.isUpgradeRequest(request)) {
      await _proxyRuntimeWebSocket(request, targetUri);
      return;
    }

    try {
      final upstreamRequest = await _proxyClient.openUrl(
        request.method,
        targetUri,
      );

      _copyProxyRequestHeaders(request.headers, upstreamRequest.headers);
      upstreamRequest.headers.set(
        'x-forwarded-prefix',
        gatewayBasePath.substring(0, gatewayBasePath.length - 1),
      );

      await upstreamRequest.addStream(request);
      final upstreamResponse = await upstreamRequest.close();

      final response = request.response;
      response.statusCode = upstreamResponse.statusCode;
      _copyProxyResponseHeaders(
        upstreamResponse.headers,
        response.headers,
        gatewayBasePath: gatewayBasePath,
      );
      _setCors(response);

      final isPreviewHtml = kind == 'preview' &&
          upstreamResponse.headers.contentType?.mimeType == 'text/html';

      if (isPreviewHtml) {
        final bytes = <int>[];
        await for (final chunk in upstreamResponse) {
          bytes.addAll(chunk);
        }
        final source = utf8.decode(bytes, allowMalformed: true);
        final rewritten = _rewritePreviewHtml(
          source,
          gatewayBasePath,
        );
        response.headers.contentType = ContentType.html;
        response.write(rewritten);
      } else {
        await response.addStream(upstreamResponse);
      }

      await response.close();
    } on SocketException catch (error) {
      try {
        await _sendError(
          request.response,
          HttpStatus.badGateway,
          'Runtime gateway connection failed: ${error.message}',
        );
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _proxyRuntimeWebSocket(
    HttpRequest request,
    Uri targetUri,
  ) async {
    final protocolsHeader = request.headers.value(
      'sec-websocket-protocol',
    );
    final protocols = protocolsHeader
        ?.split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final upstream = await WebSocket.connect(
      targetUri.replace(scheme: 'ws').toString(),
      protocols: protocols == null || protocols.isEmpty ? null : protocols,
    );

    final selectedProtocol = upstream.protocol;
    final downstream = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: selectedProtocol == null
          ? null
          : (offered) =>
              offered.contains(selectedProtocol) ? selectedProtocol : null,
    );

    downstream.listen(
      upstream.add,
      onError: (_) => upstream.close(),
      onDone: () {
        upstream.close();
      },
      cancelOnError: true,
    );
    upstream.listen(
      downstream.add,
      onError: (_) => downstream.close(),
      onDone: () {
        downstream.close();
      },
      cancelOnError: true,
    );
  }

  void _copyProxyRequestHeaders(
    HttpHeaders source,
    HttpHeaders target,
  ) {
    source.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_isHopByHopHeader(lower) ||
          lower == HttpHeaders.hostHeader ||
          lower == HttpHeaders.contentLengthHeader ||
          lower == HttpHeaders.acceptEncodingHeader) {
        return;
      }
      for (final value in values) {
        target.add(name, value);
      }
    });
  }

  void _copyProxyResponseHeaders(
    HttpHeaders source,
    HttpHeaders target, {
    required String gatewayBasePath,
  }) {
    source.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_isHopByHopHeader(lower) ||
          lower == HttpHeaders.contentLengthHeader ||
          lower == HttpHeaders.contentEncodingHeader) {
        return;
      }

      if (lower == HttpHeaders.locationHeader && values.isNotEmpty) {
        final location = values.first;
        if (location.startsWith('/')) {
          target.set(
            HttpHeaders.locationHeader,
            '$gatewayBasePath${location.substring(1)}',
          );
          return;
        }
      }

      for (final value in values) {
        target.add(name, value);
      }
    });
  }

  bool _isHopByHopHeader(String name) {
    return name == HttpHeaders.connectionHeader ||
        name == 'keep-alive' ||
        name == 'proxy-authenticate' ||
        name == 'proxy-authorization' ||
        name == 'te' ||
        name == 'trailers' ||
        name == HttpHeaders.transferEncodingHeader ||
        name == HttpHeaders.upgradeHeader;
  }

  String _rewritePreviewHtml(
    String source,
    String gatewayBasePath,
  ) {
    final baseTag = RegExp(
      r'''<base\s+href=(["'])(.*?)\1\s*/?>''',
      caseSensitive: false,
    );

    if (baseTag.hasMatch(source)) {
      return source.replaceFirst(
        baseTag,
        '<base href="$gatewayBasePath">',
      );
    }

    final headTag = RegExp(
      r'<head(?:\s[^>]*)?>',
      caseSensitive: false,
    );
    if (!headTag.hasMatch(source)) return source;

    return source.replaceFirstMapped(
      headTag,
      (match) => '${match.group(0)}\n<base href="$gatewayBasePath">',
    );
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

      final lockContent =
          await lockFile.exists() ? await lockFile.readAsString() : null;
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
    final declaredLength = request.contentLength;
    if (declaredLength > maxRequestBytes) {
      await request.drain<void>();
      throw RunnerPayloadTooLarge(
        'Request body exceeds the $maxRequestBytes byte limit.',
      );
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    var tooLarge = false;

    await for (final chunk in request) {
      received += chunk.length;

      if (received > maxRequestBytes) {
        tooLarge = true;
        continue;
      }

      if (!tooLarge) {
        builder.add(chunk);
      }
    }

    if (tooLarge) {
      throw RunnerPayloadTooLarge(
        'Request body exceeds the $maxRequestBytes byte limit.',
      );
    }

    final source = utf8.decode(
      builder.takeBytes(),
      allowMalformed: false,
    );
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

    if (value.length > maxWorkspaceFiles) {
      throw RunnerPayloadTooLarge(
        'Workspace contains more than $maxWorkspaceFiles files.',
      );
    }

    final result = <String, String>{};
    var workspaceBytes = 0;

    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
          'Workspace files must map string paths to string contents.',
        );
      }

      final path = entry.key as String;
      final content = entry.value as String;
      final fileBytes = utf8.encode(content).length;

      if (fileBytes > maxFileBytes) {
        throw RunnerPayloadTooLarge(
          'Workspace file exceeds the $maxFileBytes byte limit: $path',
        );
      }

      workspaceBytes += fileBytes;
      if (workspaceBytes > maxWorkspaceBytes) {
        throw RunnerPayloadTooLarge(
          'Workspace payload exceeds the $maxWorkspaceBytes byte limit.',
        );
      }

      result[path] = content;
    }

    return result;
  }

  int _activeSessionCountForUser(String userId) {
    var count = 0;
    for (final session in manager.sessions) {
      if (_sessionOwners[session.id] == userId) {
        count += 1;
      }
    }
    return count;
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

class RunnerPayloadTooLarge implements Exception {
  const RunnerPayloadTooLarge(this.message);

  final String message;

  @override
  String toString() => message;
}
