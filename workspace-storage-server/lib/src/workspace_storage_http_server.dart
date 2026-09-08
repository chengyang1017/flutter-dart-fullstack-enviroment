import 'dart:convert';
import 'dart:io';

import 'workspace_authenticator.dart';
import 'workspace_git_pull_service.dart';
import 'workspace_git_push_service.dart';
import 'workspace_git_remote_checker.dart';
import 'workspace_secret_store.dart';
import 'workspace_store.dart';

class WorkspaceStorageHttpServer {
  WorkspaceStorageHttpServer({
    required FileWorkspaceStore store,
    required FileWorkspaceSecretStore secretStore,
    required this.authenticator,
    WorkspaceGitRemoteChecker? gitRemoteChecker,
    WorkspaceGitPullService? gitPullService,
    WorkspaceGitPushService? gitPushService,
    this.allowedOrigin = '*',
  })  : store = store,
        secretStore = secretStore,
        gitRemoteChecker = gitRemoteChecker ??
            WorkspaceGitRemoteChecker(
              workspaceStore: store,
              secretStore: secretStore,
              executor: const ProcessWorkspaceGitCommandExecutor(),
            ),
        gitPullService = gitPullService ??
            WorkspaceGitPullService(
              workspaceStore: store,
              secretStore: secretStore,
              executor: const ProcessWorkspaceGitCloneExecutor(),
            ),
        gitPushService = gitPushService ??
            WorkspaceGitPushService(
              workspaceStore: store,
              secretStore: secretStore,
              cloneExecutor: const ProcessWorkspaceGitCloneExecutor(),
              pushExecutor: const ProcessWorkspaceGitPushCommandExecutor(),
            );

  final FileWorkspaceStore store;
  final FileWorkspaceSecretStore secretStore;
  final WorkspaceGitRemoteChecker gitRemoteChecker;
  final WorkspaceGitPullService gitPullService;
  final WorkspaceGitPushService gitPushService;
  final WorkspaceAuthenticator authenticator;
  final String allowedOrigin;

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
        await _sendJson(
          request.response,
          HttpStatus.ok,
          const <String, Object?>{'status': 'ok'},
        );
        return;
      }

      if (segments.isEmpty || segments.first != 'workspaces') {
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

      if (segments.length == 1 && request.method == 'GET') {
        final catalog = await store.loadCatalog(userId);
        await secretStore.retainWorkspaces(
          userId: userId,
          workspaceIds: _workspaceIdsFromCatalog(catalog),
        );
        await _sendJson(request.response, HttpStatus.ok, catalog);
        return;
      }

      if (segments.length == 1 && request.method == 'POST') {
        final body = await _readJsonObject(request);
        final project = _readObject(body, 'project');
        final snapshot = _readObject(body, 'snapshot');
        final document = await store.createWorkspace(
          userId: userId,
          project: project,
          snapshot: snapshot,
        );
        await _sendJson(request.response, HttpStatus.created, document);
        return;
      }

      if (segments.length == 4 &&
          segments[2] == 'git' &&
          segments[3] == 'check' &&
          request.method == 'POST') {
        final workspaceId = _readWorkspaceIdFromRoute(segments[1]);
        final body = await _readJsonObject(request);
        final result = await gitRemoteChecker.check(
          userId: userId,
          workspaceId: workspaceId,
          secretName: _readOptionalString(body, 'secretName'),
          username: _readOptionalString(body, 'username'),
        );
        await _sendJson(request.response, HttpStatus.ok, result.toJson());
        return;
      }

      if (segments.length == 4 &&
          segments[2] == 'git' &&
          segments[3] == 'pull' &&
          request.method == 'POST') {
        final workspaceId = _readWorkspaceIdFromRoute(segments[1]);
        final body = await _readJsonObject(request);
        final result = await gitPullService.pull(
          userId: userId,
          workspaceId: workspaceId,
          secretName: _readOptionalString(body, 'secretName'),
          username: _readOptionalString(body, 'username'),
        );
        await _sendJson(request.response, HttpStatus.ok, result.toJson());
        return;
      }

      if (segments.length == 4 &&
          segments[2] == 'git' &&
          segments[3] == 'push' &&
          request.method == 'POST') {
        final workspaceId = _readWorkspaceIdFromRoute(segments[1]);
        final body = await _readJsonObject(request);
        final result = await gitPushService.push(
          userId: userId,
          workspaceId: workspaceId,
          expectedWorkspaceRevision: _readRequiredString(
            body,
            'expectedWorkspaceRevision',
          ),
          expectedRemoteHead: _readRequiredString(body, 'expectedRemoteHead'),
          commitMessage: _readRequiredString(body, 'commitMessage'),
          authorName: _readRequiredString(body, 'authorName'),
          authorEmail: _readRequiredString(body, 'authorEmail'),
          secretName: _readOptionalString(body, 'secretName'),
          username: _readOptionalString(body, 'username'),
        );
        await _sendJson(request.response, HttpStatus.ok, result.toJson());
        return;
      }

      if (segments.length >= 3 && segments[2] == 'secrets') {
        final workspaceId = _readWorkspaceIdFromRoute(segments[1]);
        final workspace = await store.loadWorkspace(userId, workspaceId);
        if (workspace == null) {
          await _sendError(
            request.response,
            HttpStatus.notFound,
            'Workspace not found.',
          );
          return;
        }

        if (segments.length == 3 && request.method == 'GET') {
          final secrets = await secretStore.listSecrets(
            userId: userId,
            workspaceId: workspaceId,
          );
          await _sendJson(
            request.response,
            HttpStatus.ok,
            <String, Object?>{'secrets': secrets},
          );
          return;
        }

        if (segments.length == 4 && request.method == 'PUT') {
          final body = await _readJsonObject(request);
          final value = body['value'];
          if (value is! String) {
            throw const FormatException('Secret value must be a string.');
          }
          final secret = await secretStore.putSecret(
            userId: userId,
            workspaceId: workspaceId,
            name: segments[3],
            value: value,
            contexts: _readSecretContexts(body['contexts']),
          );
          await _sendJson(request.response, HttpStatus.ok, secret);
          return;
        }

        if (segments.length == 4 && request.method == 'DELETE') {
          final deleted = await secretStore.deleteSecret(
            userId: userId,
            workspaceId: workspaceId,
            name: segments[3],
          );
          if (!deleted) {
            await _sendError(
              request.response,
              HttpStatus.notFound,
              'Workspace secret not found.',
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
        return;
      }

      if (segments.length != 2) {
        await _sendError(
          request.response,
          HttpStatus.notFound,
          'Route not found.',
        );
        return;
      }

      final workspaceId = _readWorkspaceIdFromRoute(segments[1]);

      if (request.method == 'GET') {
        final document = await store.loadWorkspace(userId, workspaceId);
        if (document == null) {
          await _sendError(
            request.response,
            HttpStatus.notFound,
            'Workspace not found.',
          );
          return;
        }
        await _sendJson(request.response, HttpStatus.ok, document);
        return;
      }

      if (request.method == 'PUT') {
        final body = await _readJsonObject(request);
        final document = await store.saveWorkspace(
          userId: userId,
          workspaceId: workspaceId,
          project: _readObject(body, 'project'),
          snapshot: _readObject(body, 'snapshot'),
          expectedRevision: _readRevision(body),
        );
        await _sendJson(request.response, HttpStatus.ok, document);
        return;
      }

      if (request.method == 'DELETE') {
        final body = await _readJsonObject(request);
        final catalog = await store.deleteWorkspace(
          userId: userId,
          workspaceId: workspaceId,
          expectedRevision: _readRevision(body),
        );
        await secretStore.deleteWorkspaceSecrets(
          userId: userId,
          workspaceId: workspaceId,
        );
        await _sendJson(request.response, HttpStatus.ok, catalog);
        return;
      }

      await _sendError(
        request.response,
        HttpStatus.notFound,
        'Route not found.',
      );
    } on WorkspaceRevisionMismatch catch (error) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        <String, Object?>{
          'code': 'revision_conflict',
          'workspaceId': error.workspaceId,
          'expectedRevision': error.expectedRevision,
          'actualRevision': error.actualRevision,
        },
      );
    } on WorkspaceGitHeadMismatch catch (error) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        <String, Object?>{
          'code': 'git_remote_conflict',
          'workspaceId': error.workspaceId,
          'expectedRemoteHead': error.expectedRemoteHead,
          'actualRemoteHead': error.actualRemoteHead,
        },
      );
    } on WorkspaceGitProjectSelectionRequired catch (error) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        <String, Object?>{
          'code': 'git_flutter_project_selection_required',
          'candidates': [
            for (final candidate in error.candidates) candidate.toJson(),
          ],
        },
      );
    } on WorkspaceDocumentNotFound catch (error) {
      await _sendError(
        request.response,
        HttpStatus.notFound,
        error.toString(),
      );
    } on WorkspaceGitRemoteException catch (error) {
      await _sendError(
        request.response,
        HttpStatus.badGateway,
        error.message,
      );
    } on FormatException catch (error) {
      await _sendError(
        request.response,
        HttpStatus.badRequest,
        error.toString(),
      );
    } on StateError catch (error) {
      await _sendError(
        request.response,
        HttpStatus.conflict,
        error.toString(),
      );
    } catch (error, stackTrace) {
      stderr.writeln('Workspace storage request failed: $error');
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

  Map<String, dynamic> _readObject(
    Map<String, dynamic> body,
    String key,
  ) {
    final value = body[key];
    if (value is! Map) {
      throw FormatException('$key must be a JSON object.');
    }
    return Map<String, dynamic>.from(value);
  }

  String _readWorkspaceIdFromRoute(String value) {
    if (value.isEmpty) {
      throw const FormatException('Workspace id is required.');
    }
    return value;
  }

  String _readRequiredString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key is required.');
    }
    return value;
  }

  String? _readOptionalString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$key must be a string.');
    }
    return value;
  }

  String _readRevision(Map<String, dynamic> body) {
    final value = body['expectedRevision'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('expectedRevision is required.');
    }
    return value;
  }

  Set<String> _readSecretContexts(Object? value) {
    if (value is! Iterable) {
      throw const FormatException('Secret contexts must be an array.');
    }
    return value.map((item) {
      if (item is! String) {
        throw const FormatException('Secret context must be a string.');
      }
      return item;
    }).toSet();
  }

  Set<String> _workspaceIdsFromCatalog(Map<String, dynamic> catalog) {
    final projects = catalog['projects'];
    if (projects is! Iterable) return <String>{};
    return projects.map((project) {
      if (project is Map && project['id'] is String) {
        return project['id'] as String;
      }
      return '';
    }).where((id) => id.isNotEmpty).toSet();
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
