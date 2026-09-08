import 'dart:convert';
import 'dart:io';

class WorkspacePrincipal {
  const WorkspacePrincipal({
    required this.userId,
    required this.username,
  });

  final String userId;
  final String username;

  Map<String, String> toJson() => <String, String>{
        'userId': userId,
        'username': username,
      };
}

abstract class WorkspaceAuthenticator {
  const WorkspaceAuthenticator();

  Future<String?> authenticate(HttpRequest request);

  Future<WorkspacePrincipal?> authenticatePrincipal(HttpRequest request) async {
    final userId = await authenticate(request);
    if (userId == null) return null;
    return WorkspacePrincipal(userId: userId, username: userId);
  }
}

class CompositeWorkspaceAuthenticator extends WorkspaceAuthenticator {
  const CompositeWorkspaceAuthenticator(this.delegates);

  final List<WorkspaceAuthenticator> delegates;

  @override
  Future<String?> authenticate(HttpRequest request) async {
    return (await authenticatePrincipal(request))?.userId;
  }

  @override
  Future<WorkspacePrincipal?> authenticatePrincipal(HttpRequest request) async {
    for (final delegate in delegates) {
      final principal = await delegate.authenticatePrincipal(request);
      if (principal != null) return principal;
    }
    return null;
  }
}

class StaticBearerWorkspaceAuthenticator extends WorkspaceAuthenticator {
  const StaticBearerWorkspaceAuthenticator(this.tokenToUserId)
      : tokenToPrincipal = const <String, WorkspacePrincipal>{};

  const StaticBearerWorkspaceAuthenticator.principals(this.tokenToPrincipal)
      : tokenToUserId = const <String, String>{};

  final Map<String, String> tokenToUserId;
  final Map<String, WorkspacePrincipal> tokenToPrincipal;

  factory StaticBearerWorkspaceAuthenticator.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'WORKSPACE_AUTH_TOKENS must be a JSON object mapping token to user identity.',
      );
    }

    final result = <String, WorkspacePrincipal>{};
    for (final entry in decoded.entries) {
      final token = entry.key;
      if (token is! String || token.isEmpty) {
        throw const FormatException(
          'WORKSPACE_AUTH_TOKENS keys must be non-empty strings.',
        );
      }

      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        result[token] = WorkspacePrincipal(
          userId: value,
          username: value,
        );
        continue;
      }

      if (value is Map) {
        final userId = value['userId'];
        final usernameSource = value['username'];
        if (userId is! String ||
            userId.trim().isEmpty ||
            usernameSource is! String ||
            usernameSource.trim().isEmpty) {
          throw const FormatException(
            'Structured WORKSPACE_AUTH_TOKENS values require non-empty userId and username.',
          );
        }

        final username = usernameSource.trim().toLowerCase();
        if (!_usernamePattern.hasMatch(username)) {
          throw const FormatException(
            'Workspace username must use lowercase letters, numbers, or hyphens and be at most 39 characters.',
          );
        }

        result[token] = WorkspacePrincipal(
          userId: userId.trim(),
          username: username,
        );
        continue;
      }

      throw const FormatException(
        'WORKSPACE_AUTH_TOKENS values must be a user id string or an identity object.',
      );
    }

    return StaticBearerWorkspaceAuthenticator.principals(
      Map<String, WorkspacePrincipal>.unmodifiable(result),
    );
  }

  WorkspacePrincipal? principalForToken(String token) {
    final configured = tokenToPrincipal[token];
    if (configured != null) return configured;

    final userId = tokenToUserId[token];
    if (userId == null) return null;
    return WorkspacePrincipal(userId: userId, username: userId);
  }

  @override
  Future<String?> authenticate(HttpRequest request) async {
    return (await authenticatePrincipal(request))?.userId;
  }

  @override
  Future<WorkspacePrincipal?> authenticatePrincipal(HttpRequest request) async {
    final token = workspaceBearerToken(request);
    if (token == null) return null;
    return principalForToken(token);
  }
}

String? workspaceBearerToken(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null || !header.startsWith('Bearer ')) return null;
  final token = header.substring('Bearer '.length).trim();
  return token.isEmpty ? null : token;
}

final RegExp _usernamePattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,38})$');
