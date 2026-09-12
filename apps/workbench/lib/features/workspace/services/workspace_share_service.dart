import 'dart:convert';

import 'package:http/http.dart' as http;

import 'workspace_cloud_runtime.dart';

class WorkspaceShareLink {
  const WorkspaceShareLink({
    required this.token,
    required this.revision,
    required this.url,
    required this.createdAt,
  });

  final String token;
  final String revision;
  final Uri url;
  final DateTime? createdAt;
}

/// Creates immutable, read-only Workspace share links.
///
/// The public URL points directly at the share metadata endpoint. A reader can
/// discover the recursive tree from `treePath` and then fetch each file through
/// its `rawPath`, which mirrors the repository -> revision -> tree -> blob/raw
/// access pattern used by source-hosting APIs.
class WorkspaceShareService {
  WorkspaceShareService({
    http.Client? client,
    Uri? baseUri,
    String? accessToken,
  })  : _client = client,
        _baseUriOverride = baseUri,
        _accessTokenOverride = accessToken;

  final http.Client? _client;
  final Uri? _baseUriOverride;
  final String? _accessTokenOverride;

  Future<WorkspaceShareLink> createShare(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'must not be empty');
    }

    final baseUri = _resolveBaseUri();
    final accessToken = _resolveAccessToken();
    final endpoint = baseUri.resolve(
      'workspaces/${Uri.encodeComponent(id)}/shares',
    );

    final ownedClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        endpoint,
        headers: <String, String>{
          'accept': 'application/json',
          'authorization': 'Bearer $accessToken',
        },
      );

      final payload = _decodeObject(response.body);
      if (response.statusCode != 201) {
        final error = payload['error'];
        final message = error is String && error.trim().isNotEmpty
            ? error.trim()
            : 'HTTP ${response.statusCode}';
        throw StateError('Workspace share create failed: $message');
      }

      final token = _requiredString(payload, 'token');
      final revision = _requiredString(payload, 'revision');
      final sharePath = _requiredString(payload, 'sharePath');
      final createdAtSource = payload['createdAt'];
      final createdAt = createdAtSource is String
          ? DateTime.tryParse(createdAtSource)?.toUtc()
          : null;

      return WorkspaceShareLink(
        token: token,
        revision: revision,
        url: baseUri.resolve(sharePath),
        createdAt: createdAt,
      );
    } finally {
      if (ownedClient) {
        client.close();
      }
    }
  }

  Uri _resolveBaseUri() {
    final override = _baseUriOverride;
    if (override != null) {
      return _normalizeBaseUri(override);
    }

    final source = WorkspaceCloudRuntime.apiUrl.trim();
    if (source.isEmpty) {
      throw StateError('WORKSPACE_STORAGE_API_URL is not configured.');
    }
    final parsed = Uri.tryParse(source);
    if (parsed == null ||
        !parsed.hasScheme ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL is invalid: $source');
    }
    return _normalizeBaseUri(parsed);
  }

  String _resolveAccessToken() {
    final token =
        (_accessTokenOverride ?? WorkspaceCloudRuntime.accessToken ?? '').trim();
    if (token.isEmpty) {
      throw StateError('Workspace access token is empty.');
    }
    return token;
  }

  Uri _normalizeBaseUri(Uri value) {
    final path = value.path.isEmpty
        ? '/'
        : value.path.endsWith('/')
            ? value.path
            : '${value.path}/';
    return value.replace(path: path, query: null, fragment: null);
  }

  Map<String, dynamic> _decodeObject(String source) {
    if (source.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Workspace share response must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _requiredString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Workspace share response is missing $key.');
    }
    return value.trim();
  }
}
