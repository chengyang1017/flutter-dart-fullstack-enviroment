import 'package:http/http.dart' as http;

import 'http_workspace_git_remote_service.dart';
import 'http_workspace_remote_persistence.dart';
import 'http_workspace_secret_service.dart';
import 'workspace_cloud_runtime.dart';
import 'workspace_git_connection_coordinator.dart';

class WorkspaceGitConnectionRuntime {
  WorkspaceGitConnectionRuntime._({
    required http.Client client,
    required this.coordinator,
  }) : _client = client;

  static String get apiUrl => WorkspaceCloudRuntime.apiUrl;
  static String get accessToken => WorkspaceCloudRuntime.accessToken ?? '';

  /// Stable owner id resolved by the storage server's authenticated `/me`
  /// endpoint. It is never supplied by a client-side owner parameter.
  static String get userId =>
      WorkspaceCloudRuntime.identity?.userId ?? 'authenticated-workspace-user';

  final http.Client _client;
  final WorkspaceGitConnectionCoordinator coordinator;

  static WorkspaceGitConnectionRuntime? tryFromEnvironment() {
    final token = accessToken.trim();
    if (apiUrl.trim().isEmpty || token.isEmpty) return null;

    final identity = WorkspaceCloudRuntime.identity;
    if (identity == null) return null;

    final baseUri = Uri.tryParse(apiUrl.trim());
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      return null;
    }

    final client = http.Client();
    final remote = HttpWorkspaceRemotePersistence(
      identity: identity,
      baseUri: baseUri,
      accessToken: token,
      client: client,
    );
    final secrets = HttpWorkspaceSecretService(
      baseUri: baseUri,
      accessToken: token,
      client: client,
    );
    final git = HttpWorkspaceGitRemoteService(
      baseUri: baseUri,
      accessToken: token,
      client: client,
    );

    return WorkspaceGitConnectionRuntime._(
      client: client,
      coordinator: WorkspaceGitConnectionCoordinator(
        remote: remote,
        secrets: secrets,
        git: git,
      ),
    );
  }

  void close() => _client.close();
}
