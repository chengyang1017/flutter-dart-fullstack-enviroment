import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import '../models/workspace_project.dart';
import '../models/workspace_remote_models.dart';
import '../models/workspace_snapshot.dart';
import 'workspace_remote_persistence.dart';

class WorkspaceRemoteRequestException implements Exception {
  const WorkspaceRemoteRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'WorkspaceRemoteRequestException(statusCode: $statusCode, message: $message)';
}

class HttpWorkspaceRemotePersistence implements WorkspaceRemotePersistence {
  HttpWorkspaceRemotePersistence({
    required this.identity,
    required this.baseUri,
    required this.accessToken,
    required http.Client client,
  }) : _client = client;

  @override
  final WorkspaceIdentity identity;
  final Uri baseUri;
  final String accessToken;
  final http.Client _client;

  @override
  Future<WorkspaceRemoteCatalog> loadCatalog() async {
    final response = await _client.get(
      _uri(const <String>['workspaces']),
      headers: _headers(),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceRemoteCatalog.fromJson(body);
  }

  @override
  Future<WorkspaceRemoteDocument?> loadWorkspace(String workspaceId) async {
    final response = await _client.get(
      _uri(<String>['workspaces', workspaceId]),
      headers: _headers(),
    );
    if (response.statusCode == 404) return null;
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceRemoteDocument.fromJson(body);
  }

  @override
  Future<WorkspaceRemoteDocument> createWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
  }) async {
    final response = await _client.post(
      _uri(const <String>['workspaces']),
      headers: _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'project': project.toJson(),
        'snapshot': snapshot.toJson(),
      }),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceRemoteDocument.fromJson(body);
  }

  @override
  Future<WorkspaceRemoteDocument> saveWorkspace({
    required WorkspaceProject project,
    required WorkspaceSnapshot snapshot,
    required String expectedRevision,
  }) async {
    final response = await _client.put(
      _uri(<String>['workspaces', project.id]),
      headers: _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'project': project.toJson(),
        'snapshot': snapshot.toJson(),
        'expectedRevision': expectedRevision,
      }),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceRemoteDocument.fromJson(body);
  }

  @override
  Future<WorkspaceRemoteCatalog> deleteWorkspace({
    required String workspaceId,
    required String expectedRevision,
  }) async {
    final response = await _client.delete(
      _uri(<String>['workspaces', workspaceId]),
      headers: _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'expectedRevision': expectedRevision,
      }),
    );
    final body = _decodeObject(response);
    _ensureSuccess(response, body);
    return WorkspaceRemoteCatalog.fromJson(body);
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
          'Remote Workspace response must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _ensureSuccess(http.Response response, Map<String, dynamic> body) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    if (response.statusCode == 409 && body['code'] == 'revision_conflict') {
      final workspaceId = body['workspaceId'];
      final expected = body['expectedRevision'];
      final actual = body['actualRevision'];
      if (workspaceId is String && expected is String && actual is String) {
        throw WorkspaceRevisionConflict(
          workspaceId: workspaceId,
          expectedRevision: expected,
          actualRevision: actual,
        );
      }
    }

    final message = body['error'];
    throw WorkspaceRemoteRequestException(
      statusCode: response.statusCode,
      message: message is String && message.isNotEmpty
          ? message
          : 'Remote Workspace request failed.',
    );
  }
}
