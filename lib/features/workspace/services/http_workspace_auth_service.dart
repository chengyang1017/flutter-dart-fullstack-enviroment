import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';

class WorkspaceAuthRequestException implements Exception {
  const WorkspaceAuthRequestException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() =>
      'WorkspaceAuthRequestException(statusCode: $statusCode, code: $code, message: $message)';
}

class WorkspaceAuthSession {
  const WorkspaceAuthSession({
    required this.identity,
    required this.email,
    required this.accessToken,
  });

  final WorkspaceIdentity identity;
  final String email;
  final String accessToken;
}

class HttpWorkspaceAuthService {
  HttpWorkspaceAuthService({
    required this.baseUri,
    required http.Client client,
  }) : _client = client;

  final Uri baseUri;
  final http.Client _client;

  Future<WorkspaceAuthSession> register({
    required String username,
    required String email,
    required String password,
  }) {
    return _authenticate(
      path: const <String>['auth', 'register'],
      body: <String, Object?>{
        'username': username,
        'email': email,
        'password': password,
      },
    );
  }

  Future<WorkspaceAuthSession> login({
    required String email,
    required String password,
  }) {
    return _authenticate(
      path: const <String>['auth', 'login'],
      body: <String, Object?>{
        'email': email,
        'password': password,
      },
    );
  }

  Future<void> logout(String accessToken) async {
    final response = await _client.post(
      _uri(const <String>['auth', 'logout']),
      headers: <String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = _decodeObject(response);
    throw _error(response, body);
  }

  Future<WorkspaceAuthSession> _authenticate({
    required List<String> path,
    required Map<String, Object?> body,
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: const <String, String>{
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final decoded = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response, decoded);
    }

    final accessToken = decoded['accessToken'];
    final rawUser = decoded['user'];
    if (accessToken is! String || accessToken.trim().isEmpty || rawUser is! Map) {
      throw const FormatException(
        'Workspace auth response requires accessToken and user.',
      );
    }
    final user = Map<String, dynamic>.from(rawUser);
    final userId = user['userId'];
    final username = user['username'];
    final email = user['email'];
    if (userId is! String ||
        userId.trim().isEmpty ||
        username is! String ||
        username.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty) {
      throw const FormatException(
        'Workspace auth user requires userId, username, and email.',
      );
    }

    return WorkspaceAuthSession(
      identity: WorkspaceIdentity(
        userId: userId.trim(),
        username: username.trim(),
      ),
      email: email.trim(),
      accessToken: accessToken.trim(),
    );
  }

  WorkspaceAuthRequestException _error(
    http.Response response,
    Map<String, dynamic> body,
  ) {
    final message = body['error'];
    final code = body['code'];
    return WorkspaceAuthRequestException(
      statusCode: response.statusCode,
      code: code is String && code.isNotEmpty ? code : null,
      message: message is String && message.isNotEmpty
          ? message
          : 'Workspace authentication failed.',
    );
  }

  Uri _uri(List<String> segments) {
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    return baseUri.replace(
      pathSegments: <String>[...baseSegments, ...segments],
      queryParameters: null,
      fragment: null,
    );
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Workspace auth response must be a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }
}
