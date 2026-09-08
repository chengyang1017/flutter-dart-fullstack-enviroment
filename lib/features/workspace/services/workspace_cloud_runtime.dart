import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import 'cloud_backed_workspace_persistence.dart';
import 'hive_workspace_persistence.dart';
import 'http_workspace_remote_persistence.dart';
import 'workspace_git_connection_runtime.dart';

/// Boots the app's cloud-first Workspace persistence from compile-time config.
class WorkspaceCloudRuntime {
  WorkspaceCloudRuntime._();

  static http.Client? _client;
  static bool _enabled = false;

  static bool get enabled => _enabled;

  static Future<bool> initializeFromEnvironment() async {
    final cache = HiveWorkspacePersistence.localFromOpenBoxes();
    if (cache == null) return false;

    final apiUrl = WorkspaceGitConnectionRuntime.apiUrl.trim();
    final accessToken = WorkspaceGitConnectionRuntime.accessToken.trim();
    if (apiUrl.isEmpty || accessToken.isEmpty) {
      _enabled = false;
      return false;
    }

    final baseUri = Uri.tryParse(apiUrl);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL 无效：$apiUrl');
    }

    _client?.close();
    final client = http.Client();
    final remote = HttpWorkspaceRemotePersistence(
      identity: WorkspaceIdentity(
        userId: WorkspaceGitConnectionRuntime.userId,
      ),
      baseUri: baseUri,
      accessToken: accessToken,
      client: client,
    );
    final cloud = CloudBackedWorkspacePersistence(
      cache: cache,
      remote: remote,
    );

    try {
      await cloud.hydrateFromRemote();
    } catch (_) {
      client.close();
      rethrow;
    }

    _client = client;
    _enabled = true;
    HiveWorkspacePersistence.useRuntimePersistence(cloud);
    return true;
  }
}
