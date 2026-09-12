import 'dart:convert';
import 'dart:io';

import 'workspace_account_store.dart';
import 'workspace_admin_store.dart';
import 'workspace_authenticator.dart';
import 'workspace_store.dart';

/// Adds a small administrative API in front of the normal Workspace routes.
///
/// Admin authorization uses the same bearer sessions as the main app. A user
/// is considered an admin only when its username is listed in
/// `WORKSPACE_ADMIN_USERNAMES` on the server.
class WorkspaceAdminHttpHandler {
  WorkspaceAdminHttpHandler({
    required this.store,
    required this.accounts,
    required this.authenticator,
    required this.fallback,
    required Iterable<String> adminUsernames,
    this.allowedOrigin = '*',
  }) : adminUsernames = adminUsernames
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet();

  final WorkspaceAdminStore store;
  final FileWorkspaceAccountStore accounts;
  final WorkspaceAuthenticator authenticator;
  final Future<void> Function(HttpRequest request) fallback;
  final Set<String> adminUsernames;
  final String allowedOrigin;

  Future<void> handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final isContentRoute = segments.isNotEmpty && segments.first == 'content';
    final isAdminRoute = segments.isNotEmpty && segments.first == 'admin';

    if (!isContentRoute && !isAdminRoute) {
      await fallback(request);
      return;
    }

    if (request.method == 'OPTIONS') {
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    try {
      if (isContentRoute) {
        await _handleContent(request, segments);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 2 &&
          segments[1] == 'login') {
        await _handleAdminLogin(request);
        return;
      }

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
          adminUsernames.isEmpty
              ? 'Workspace admin access is not configured.'
              : 'Administrator access required.',
        );
        return;
      }

      await _handleAdmin(request, segments, principal);
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
    } on WorkspaceRevisionMismatch catch (error) {
      await _sendError(
        request.response,
        HttpStatus.conflict,
        error.toString(),
      );
    } catch (error, stackTrace) {
      stderr.writeln('Workspace admin request failed: $error');
      stderr.writeln(stackTrace);
      await _sendError(
        request.response,
        HttpStatus.internalServerError,
        'Internal server error.',
      );
    }
  }

  Future<void> _handleAdminLogin(HttpRequest request) async {
    if (adminUsernames.isEmpty) {
      await _sendError(
        request.response,
        HttpStatus.forbidden,
        'Workspace admin access is not configured.',
      );
      return;
    }

    final body = await _readJsonObject(request);
    final email = body['email'];
    final password = body['password'];
    if (email is! String || password is! String) {
      throw const FormatException('Email and password are required.');
    }

    final session = await accounts.login(email: email, password: password);
    if (!adminUsernames.contains(session.principal.username.toLowerCase())) {
      await accounts.logoutToken(session.accessToken);
      await _sendError(
        request.response,
        HttpStatus.forbidden,
        'Administrator access required.',
      );
      return;
    }

    await _sendJson(
      request.response,
      HttpStatus.ok,
      session.toJson(),
    );
  }

  Future<void> _handleContent(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments[1] == 'lessons') {
      final catalog = await store.loadLessonCatalog();
      if (catalog == null) {
        await _sendJson(
          request.response,
          HttpStatus.notFound,
          const <String, Object?>{
            'code': 'lesson_catalog_uninitialized',
            'error': 'Lesson catalog has not been initialized yet.',
          },
        );
        return;
      }
      await _sendJson(request.response, HttpStatus.ok, catalog);
      return;
    }

    await _sendError(request.response, HttpStatus.notFound, 'Route not found.');
  }

  Future<void> _handleAdmin(
    HttpRequest request,
    List<String> segments,
    WorkspacePrincipal principal,
  ) async {
    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments[1] == 'me') {
      await _sendJson(
        request.response,
        HttpStatus.ok,
        <String, Object?>{
          'userId': principal.userId,
          'username': principal.username,
          'admin': true,
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments[1] == 'overview') {
      final users = await store.listUsers();
      final projects = await store.listProjects();
      final catalog = await store.loadLessonCatalog();
      final lessonProjects = catalog?['projects'];
      var lessonCount = 0;
      if (lessonProjects is Iterable) {
        for (final project in lessonProjects) {
          if (project is Map && project['lessons'] is Iterable) {
            lessonCount += (project['lessons'] as Iterable).length;
          }
        }
      }

      await _sendJson(
        request.response,
        HttpStatus.ok,
        <String, Object?>{
          'users': users.length,
          'projects': projects.length,
          'lessonProjects': lessonProjects is Iterable
              ? lessonProjects.length
              : 0,
          'lessons': lessonCount,
          'lessonCatalogInitialized': catalog != null,
          'lessonCatalogUpdatedAt': catalog?['updatedAt'],
        },
      );
      return;
    }

    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments[1] == 'users') {
      await _sendJson(
        request.response,
        HttpStatus.ok,
        <String, Object?>{'users': await store.listUsers()},
      );
      return;
    }

    if (request.method == 'DELETE' &&
        segments.length == 3 &&
        segments[1] == 'users') {
      final userId = Uri.decodeComponent(segments[2]);
      if (userId == principal.userId) {
        await _sendError(
          request.response,
          HttpStatus.conflict,
          'You cannot delete the account used for the current admin session.',
        );
        return;
      }
      final deleted = await store.deleteUser(userId);
      if (!deleted) {
        await _sendError(
          request.response,
          HttpStatus.notFound,
          'User not found.',
        );
        return;
      }
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments[1] == 'projects') {
      await _sendJson(
        request.response,
        HttpStatus.ok,
        <String, Object?>{'projects': await store.listProjects()},
      );
      return;
    }

    if (request.method == 'DELETE' &&
        segments.length == 4 &&
        segments[1] == 'projects') {
      final userId = Uri.decodeComponent(segments[2]);
      final workspaceId = Uri.decodeComponent(segments[3]);
      final deleted = await store.deleteProject(
        userId: userId,
        workspaceId: workspaceId,
      );
      if (!deleted) {
        await _sendError(
          request.response,
          HttpStatus.notFound,
          'Workspace project not found.',
        );
        return;
      }
      await _sendEmpty(request.response, HttpStatus.noContent);
      return;
    }

    if (segments.length == 2 && segments[1] == 'lessons') {
      if (request.method == 'GET') {
        final catalog = await store.loadLessonCatalog();
        if (catalog == null) {
          await _sendJson(
            request.response,
            HttpStatus.notFound,
            const <String, Object?>{
              'code': 'lesson_catalog_uninitialized',
              'error': 'Lesson catalog has not been initialized yet.',
            },
          );
          return;
        }
        await _sendJson(request.response, HttpStatus.ok, catalog);
        return;
      }

      if (request.method == 'PUT') {
        final body = await _readJsonObject(request);
        final saved = await store.saveLessonCatalog(body);
        await _sendJson(request.response, HttpStatus.ok, saved);
        return;
      }
    }

    if (request.method == 'POST' &&
        segments.length == 3 &&
        segments[1] == 'lessons' &&
        segments[2] == 'bootstrap') {
      final body = await _readJsonObject(request);
      final created = await store.bootstrapLessonCatalog(body);
      if (!created) {
        await _sendError(
          request.response,
          HttpStatus.conflict,
          'Lesson catalog is already initialized.',
        );
        return;
      }
      final catalog = await store.loadLessonCatalog();
      await _sendJson(
        request.response,
        HttpStatus.created,
        catalog ?? body,
      );
      return;
    }

    await _sendError(request.response, HttpStatus.notFound, 'Route not found.');
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
