import 'dart:convert';
import 'dart:io';

import 'workspace_admin_agent_service.dart';
import 'workspace_authenticator.dart';

class WorkspaceAdminAgentHttpHandler {
  WorkspaceAdminAgentHttpHandler({
    required this.service,
    required this.authenticator,
    required this.fallback,
    required Iterable<String> adminUsernames,
    this.allowedOrigin = '*',
  }) : adminUsernames = adminUsernames
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet();

  final WorkspaceAdminAgentService service;
  final WorkspaceAuthenticator authenticator;
  final Future<void> Function(HttpRequest request) fallback;
  final Set<String> adminUsernames;
  final String allowedOrigin;

  Future<void> handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final isAgentRoute = segments.length >= 2 &&
        segments[0] == 'admin' &&
        segments[1] == 'agent';

    if (!isAgentRoute) {
      await fallback(request);
      return;
    }

    if (request.method == 'OPTIONS') {
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    try {
      final principal = await authenticator.authenticatePrincipal(request);
      if (principal == null) {
        await _sendError(
          request.response,
          HttpStatus.unauthorized,
          'Authentication required.',
        );
        return;
      }
      if (!adminUsernames.contains(principal.username.toLowerCase())) {
        await _sendError(
          request.response,
          HttpStatus.forbidden,
          'Administrator access required.',
        );
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[2] == 'status') {
        await _sendJson(
          request.response,
          HttpStatus.ok,
          <String, Object?>{
            'configured': service.isConfigured,
            'model': service.model,
          },
        );
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments[2] == 'chat') {
        final body = await _readJsonObject(request);
        final rawMessages = body['messages'];
        if (rawMessages is! Iterable) {
          throw const FormatException('messages must be an array.');
        }

        final messages = <Map<String, dynamic>>[];
        for (final raw in rawMessages) {
          if (raw is Map) {
            messages.add(Map<String, dynamic>.from(raw));
          }
        }

        Map<String, dynamic>? context;
        if (body['context'] is Map) {
          context = Map<String, dynamic>.from(body['context'] as Map);
        }

        final reply = await service.chat(
          messages: messages,
          context: context,
        );
        await _sendJson(
          request.response,
          HttpStatus.ok,
          <String, Object?>{
            'reply': reply,
            'model': service.model,
          },
        );
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments[2] == 'translate') {
        final body = await _readJsonObject(request);
        final rawCourse = body['course'];
        if (rawCourse is! Map) {
          throw const FormatException('course must be an object.');
        }
        final sourceLanguage = body['sourceLanguage']?.toString() ?? '';
        final targetLanguage = body['targetLanguage']?.toString() ?? '';
        if (sourceLanguage.isEmpty || targetLanguage.isEmpty) {
          throw const FormatException(
            'sourceLanguage and targetLanguage are required.',
          );
        }

        final proposal = await service.translateCourse(
          course: Map<String, dynamic>.from(rawCourse),
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );
        await _sendJson(
          request.response,
          HttpStatus.ok,
          <String, Object?>{
            'reply': targetLanguage.toLowerCase().startsWith('zh')
                ? '中文翻译草稿已生成。检查后点 Apply 写入当前课程。'
                : 'English translation draft is ready. Review it, then click Apply.',
            'proposal': proposal,
            'model': service.model,
          },
        );
        return;
      }

      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Agent route not found.',
      );
    } on FormatException catch (error) {
      await _sendError(
        request.response,
        HttpStatus.badRequest,
        error.message,
      );
    } on WorkspaceAdminAgentException catch (error) {
      await _sendError(
        request.response,
        error.statusCode,
        error.message,
      );
    } catch (error, stackTrace) {
      stderr.writeln('Workspace admin agent request failed: $error');
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
      'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    );
    response.headers.set(
      'access-control-allow-headers',
      'authorization, content-type, accept',
    );
    response.headers.set('cache-control', 'no-store');
  }
}
