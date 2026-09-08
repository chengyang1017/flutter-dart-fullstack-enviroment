import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/workspace_git_pull.dart';
import '../models/workspace_git_push.dart';
import '../models/workspace_git_remote_check.dart';
import '../models/workspace_remote_models.dart';
import 'workspace_git_remote_service.dart';

class HttpWorkspaceGitRemoteService implements WorkspaceGitRemoteService {
  HttpWorkspaceGitRemoteService({
    required this.baseUri,
    required this.accessToken,
    required http.Client client,
  }) : _client = client;

  final Uri baseUri;
  final String accessToken;
  final http.Client _client;

  @override
  Future<WorkspaceGitRemoteCheckResult> checkRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) async {
    final body = await _postGitAction(
      workspaceId: workspaceId,
      action: 'check',
      requestBody: _credentialReferenceBody(
        secretName: secretName,
        username: username,
      ),
      fallbackError: 'Git remote check failed.',
    );
    return WorkspaceGitRemoteCheckResult.fromJson(body);
  }

  @override
  Future<WorkspaceGitPullResult> pullRemote({
    required String workspaceId,
    String? secretName,
    String? username,
  }) async {
    final body = await _postGitAction(
      workspaceId: workspaceId,
      action: 'pull',
      requestBody: _credentialReferenceBody(
        secretName: secretName,
        username: username,
      ),
      fallbackError: 'Git pull failed.',
    );
    return WorkspaceGitPullResult.fromJson(body);
  }

  @override
  Future<WorkspaceGitPushResult> pushRemote({
    required String workspaceId,
    required String expectedWorkspaceRevision,
    required String expectedRemoteHead,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? secretName,
    String? username,
  }) async {
    final body = await _postGitAction(
      workspaceId: workspaceId,
      action: 'push',
      requestBody: <String, dynamic>{
        'expectedWorkspaceRevision': expectedWorkspaceRevision,
        'expectedRemoteHead': expectedRemoteHead,
        'commitMessage': commitMessage,
        'authorName': authorName,
        'authorEmail': authorEmail,
        ..._credentialReferenceBody(
          secretName: secretName,
          username: username,
        ),
      },
      fallbackError: 'Git push failed.',
    );
    return WorkspaceGitPushResult.fromJson(body);
  }

  Future<Map<String, dynamic>> _postGitAction({
    required String workspaceId,
    required String action,
    required Map<String, dynamic> requestBody,
    required String fallbackError,
  }) async {
    final response = await _client.post(
      _uri(<String>['workspaces', workspaceId, 'git', action]),
      headers: <String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    final body = _decodeObject(response);
    _ensureSuccess(response, body, fallbackError);
    return body;
  }

  Map<String, dynamic> _credentialReferenceBody({
    String? secretName,
    String? username,
  }) {
    return <String, dynamic>{
      if (secretName?.trim().isNotEmpty == true)
        'secretName': secretName!.trim(),
      if (username?.trim().isNotEmpty == true) 'username': username!.trim(),
    };
  }

  void _ensureSuccess(
    http.Response response,
    Map<String, dynamic> body,
    String fallbackError,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    if (response.statusCode == 409) {
      final code = body['code'];
      final workspaceId = body['workspaceId'];
      if (code == 'git_flutter_project_selection_required') {
        final rawCandidates = body['candidates'];
        if (rawCandidates is Iterable) {
          final candidates = rawCandidates.map((item) {
            if (item is! Map) {
              throw const FormatException(
                'Invalid Git Flutter project candidate response.',
              );
            }
            return WorkspaceGitFlutterProjectCandidate.fromJson(item);
          }).toList(growable: false);
          if (candidates.length >= 2) {
            throw WorkspaceGitProjectSelectionRequired(candidates);
          }
        }
        throw const FormatException(
          'Invalid Git Flutter project selection response.',
        );
      }
      if (code == 'git_remote_conflict') {
        final expected = body['expectedRemoteHead'];
        final actual = body['actualRemoteHead'];
        if (workspaceId is String && expected is String && actual is String) {
          throw WorkspaceGitRemoteHeadConflict(
            workspaceId: workspaceId,
            expectedRemoteHead: expected,
            actualRemoteHead: actual,
          );
        }
      }
      if (code == 'revision_conflict') {
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
    }

    final error = body['error'];
    throw WorkspaceGitRemoteRequestException(
      statusCode: response.statusCode,
      message: error is String && error.isNotEmpty ? error : fallbackError,
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
      throw const FormatException('Git remote response must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

class WorkspaceGitRemoteRequestException implements Exception {
  const WorkspaceGitRemoteRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'WorkspaceGitRemoteRequestException(statusCode: $statusCode, message: $message)';
}
