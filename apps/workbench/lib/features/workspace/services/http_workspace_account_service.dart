import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';

class WorkspaceAccountRequestException implements Exception {
  const WorkspaceAccountRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'WorkspaceAccountRequestException(statusCode: $statusCode, message: $message)';
}

/// Resolves the authenticated Workspace account from the storage server.
///
/// The bearer token is the only client credential involved. The client never
/// supplies its own owner id; `/me` is authoritative for both stable [userId]
/// and the human-readable [username].
class HttpWorkspaceAccountService {
  HttpWorkspaceAccountService({
    required this.baseUri,
    required this.accessToken,
    required http.Client client,
  }) : _client = client;

  final Uri baseUri;
  final String accessToken;
  final http.Client _client;

  Future<WorkspaceIdentity> currentIdentity() async {
    final response = await _client.get(
      _uri(const <String>['me']),
      headers: <String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $accessToken',
      },
    );

    final body = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      throw WorkspaceAccountRequestException(
        statusCode: response.statusCode,
        message: error is String && error.isNotEmpty
            ? error
            : 'Workspace account request failed.',
      );
    }

    final userId = body['userId'];
    final username = body['username'];
    if (userId is! String ||
        userId.trim().isEmpty ||
        username is! String ||
        username.trim().isEmpty) {
      throw const FormatException(
        'Workspace /me response requires non-empty userId and username.',
      );
    }

    return WorkspaceIdentity(
      userId: userId.trim(),
      username: username.trim(),
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
        'Workspace account response must be a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }
}
