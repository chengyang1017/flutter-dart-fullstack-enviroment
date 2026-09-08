import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_secret.dart';
import 'workspace_secret_service.dart';

class WorkspaceSecretRequestException implements Exception {
  const WorkspaceSecretRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'WorkspaceSecretRequestException(statusCode: $statusCode, message: $message)';
}

class HttpWorkspaceSecretService implements WorkspaceSecretService {
  HttpWorkspaceSecretService({
    required this.baseUri,
    required this.accessToken,
    required http.Client client,
  }) : _client = client;

  final Uri baseUri;
  final String accessToken;
  final http.Client _client;

  @override
  Future<List<WorkspaceSecretMetadata>> listSecrets(String workspaceId) async {
    final response = await _client.get(
      _uri(<String>['workspaces', workspaceId, 'secrets']),
      headers: _headers(),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);

    final rawSecrets = body['secrets'];
    if (rawSecrets is! Iterable) {
      throw const FormatException(
        'Workspace secret response must contain a secrets array.',
      );
    }
    return rawSecrets.map((item) {
      if (item is! Map) {
        throw const FormatException('Workspace secret metadata is invalid.');
      }
      return WorkspaceSecretMetadata.fromJson(item);
    }).toList(growable: false);
  }

  @override
  Future<WorkspaceSecretMetadata> putSecret({
    required String workspaceId,
    required String name,
    required String value,
    required Set<WorkspaceSecretContext> contexts,
  }) async {
    if (value.isEmpty) {
      throw const FormatException('Workspace secret value cannot be empty.');
    }
    if (utf8.encode(value).length > 65536) {
      throw const FormatException(
        'Workspace secret value must be 64 KiB or smaller.',
      );
    }
    if (contexts.isEmpty) {
      throw const FormatException(
        'Workspace secret must allow at least one execution context.',
      );
    }

    final response = await _client.put(
      _uri(<String>['workspaces', workspaceId, 'secrets', name]),
      headers: _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'value': value,
        'contexts': contexts.map((context) => context.name).toList()..sort(),
      }),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceSecretMetadata.fromJson(body);
  }

  @override
  Future<void> deleteSecret({
    required String workspaceId,
    required String name,
  }) async {
    final response = await _client.delete(
      _uri(<String>['workspaces', workspaceId, 'secrets', name]),
      headers: _headers(),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
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

  Map<String, String> _headers({bool json = false}) => <String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $accessToken',
        if (json) 'content-type': 'application/json',
      };

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
          'Workspace secret response must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _ensureSuccess(http.Response response, Map<String, dynamic> body) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message = body['error'];
    throw WorkspaceSecretRequestException(
      statusCode: response.statusCode,
      message: message is String && message.isNotEmpty
          ? message
          : 'Workspace secret request failed.',
    );
  }
}
