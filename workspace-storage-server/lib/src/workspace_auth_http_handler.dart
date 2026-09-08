import 'dart:convert';
import 'dart:io';

import 'workspace_account_store.dart';
import 'workspace_authenticator.dart';
import 'workspace_storage_http_server.dart';

/// Adds register/login/logout routes in front of the existing Workspace API.
class WorkspaceAuthHttpHandler {
  WorkspaceAuthHttpHandler({
    required this.accounts,
    required this.workspaceHandler,
    this.allowedOrigin = '*',
  });

  final FileWorkspaceAccountStore accounts;
  final WorkspaceStorageHttpServer workspaceHandler;
  final String allowedOrigin;

  Future<void> handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.isEmpty || segments.first != 'auth') {
      await workspaceHandler.handle(request);
      return;
    }

    if (request.method == 'OPTIONS') {
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    try {
      if (segments.length == 2 &&
          segments[1] == 'register' &&
          request.method == 'POST') {
        final body = await _readJsonObject(request);
        final session = await accounts.register(
          username: _requiredString(body, 'username'),
          email: _requiredString(body, 'email'),
          password: _requiredString(body, 'password', trim: false),
        );
        await _sendJson(
          request.response,
          HttpStatus.created,
          session.toJson(),
        );
        return;
      }

      if (segments.length == 2 &&
          segments[1] == 'login' &&
          request.method == 'POST') {
        final body = await _readJsonObject(request);
        final session = await accounts.login(
          email: _requiredString(body, 'email'),
          password: _requiredString(body, 'password', trim: false),
        );
        await _sendJson(
          request.response,
          HttpStatus.ok,
          session.toJson(),
        );
        return;
      }

      if (segments.length == 2 &&
          segments[1] == 'logout' &&
          request.method == 'POST') {
        final token = workspaceBearerToken(request);
        if (token == null || !await accounts.logoutToken(token)) {
          await _sendError(
            request.response,
            HttpStatus.unauthorized,
            'Authentication required.',
          );
          return;
        }
        await _sendEmpty(request.response, HttpStatus.noContent);
        return;
      }

      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Route not found.',
      );
    } on WorkspaceAccountConflict catch (error) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        <String, Object?>{
          'code': error.code,
          'error': error.message,
        },
      );
    } on WorkspaceCredentialsRejected {
      await _sendError(
        request.response,
        HttpStatus.unauthorized,
        'Invalid email or password.',
      );
    } on FormatException catch (error) {
      await _sendError(
        request.response,
        HttpStatus.badRequest,
        error.message,
      );
    } catch (error, stackTrace) {
      stderr.writeln('Workspace auth request failed: $error');
      stderr.writeln(stackTrace);
      await _sendError(
        request.response,
        HttpStatus.internalServerError,
        'Internal server error.',
      );
    }
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

  String _requiredString(
    Map<String, dynamic> body,
    String key, {
    bool trim = true,
  }) {
    final value = body[key];
    if (value is! String) {
      throw FormatException('$key is required.');
    }
    final result = trim ? value.trim() : value;
    if (result.isEmpty) {
      throw FormatException('$key is required.');
    }
    return result;
  }

  Future<void> _sendError(
    HttpResponse response,
    int statusCode,
    String message,
  ) {
    return _sendJson(
      response,
      statusCode,
      <String, Object?>{'error': message},
    );
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
