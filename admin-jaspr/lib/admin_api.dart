import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminSession {
  const AdminSession({
    required this.accessToken,
    required this.userId,
    required this.username,
    required this.email,
  });

  final String accessToken;
  final String userId;
  final String username;
  final String email;
}

class AdminApi {
  AdminApi({
    String? baseUrl,
    http.Client? client,
  })  : baseUri = Uri.parse(
          baseUrl ??
              const String.fromEnvironment(
                'WORKSPACE_STORAGE_API_URL',
                defaultValue:
                    'https://workspace-storage-production.up.railway.app',
              ),
        ),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<AdminSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      baseUri.resolve('/admin/login'),
      headers: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'email': email.trim(),
        'password': password,
      }),
    );

    final body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw AdminApiException(
        body['error']?.toString() ?? 'Login failed.',
        statusCode: response.statusCode,
      );
    }

    final token = body['accessToken'];
    final user = body['user'];
    if (token is! String || token.isEmpty || user is! Map) {
      throw const AdminApiException('Login response is invalid.');
    }

    final normalizedUser = Map<String, dynamic>.from(user);
    return AdminSession(
      accessToken: token,
      userId: normalizedUser['userId']?.toString() ?? '',
      username: normalizedUser['username']?.toString() ?? '',
      email: normalizedUser['email']?.toString() ?? email.trim(),
    );
  }

  Future<Map<String, dynamic>> verifyAdmin(String token) {
    return _getObject('/admin/me', token);
  }

  Future<Map<String, dynamic>> overview(String token) {
    return _getObject('/admin/overview', token);
  }

  Future<List<Map<String, dynamic>>> users(String token) async {
    final body = await _getObject('/admin/users', token);
    return _objectList(body['users']);
  }

  Future<List<Map<String, dynamic>>> projects(String token) async {
    final body = await _getObject('/admin/projects', token);
    return _objectList(body['projects']);
  }

  Future<Map<String, dynamic>> lessons(String token) {
    return _getObject('/admin/lessons', token);
  }

  Future<Map<String, dynamic>> saveLessons(
    String token,
    Map<String, dynamic> catalog,
  ) async {
    final response = await _client.put(
      baseUri.resolve('/admin/lessons'),
      headers: _headers(token, json: true),
      body: jsonEncode(catalog),
    );
    final body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw AdminApiException(
        body['error']?.toString() ?? 'Saving lessons failed.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<void> deleteUser(String token, String userId) async {
    final response = await _client.delete(
      baseUri.resolve('/admin/users/${Uri.encodeComponent(userId)}'),
      headers: _headers(token),
    );
    if (response.statusCode != 204) {
      final body = _decodeObject(response);
      throw AdminApiException(
        body['error']?.toString() ?? 'Deleting user failed.',
        statusCode: response.statusCode,
      );
    }
  }

  Future<void> deleteProject(
    String token, {
    required String userId,
    required String workspaceId,
  }) async {
    final response = await _client.delete(
      baseUri.resolve(
        '/admin/projects/${Uri.encodeComponent(userId)}/'
        '${Uri.encodeComponent(workspaceId)}',
      ),
      headers: _headers(token),
    );
    if (response.statusCode != 204) {
      final body = _decodeObject(response);
      throw AdminApiException(
        body['error']?.toString() ?? 'Deleting project failed.',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _getObject(String path, String token) async {
    final response = await _client.get(
      baseUri.resolve(path),
      headers: _headers(token),
    );
    final body = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminApiException(
        body['error']?.toString() ?? 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Map<String, String> _headers(String token, {bool json = false}) {
    return <String, String>{
      'authorization': 'Bearer $token',
      'accept': 'application/json',
      if (json) 'content-type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AdminApiException(
        'Server returned an invalid JSON response.',
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  List<Map<String, dynamic>> _objectList(Object? source) {
    if (source is! Iterable) return const <Map<String, dynamic>>[];
    return source.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
