import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import 'cloud_backed_workspace_persistence.dart';
import 'hive_workspace_persistence.dart';
import 'http_workspace_account_service.dart';
import 'http_workspace_remote_persistence.dart';

/// Boots the app's cloud-first Workspace persistence from compile-time config.
class WorkspaceCloudRuntime {
  WorkspaceCloudRuntime._();

  static const apiUrl = String.fromEnvironment('WORKSPACE_STORAGE_API_URL');
  static const accessToken = String.fromEnvironment('WORKSPACE_ACCESS_TOKEN');

  static http.Client? _client;
  static bool _enabled = false;
  static WorkspaceIdentity? _identity;

  static bool get enabled => _enabled;
  static WorkspaceIdentity? get identity => _identity;

  static Future<bool> initializeFromEnvironment() async {
    _enabled = false;
    _identity = null;

    final cache = HiveWorkspacePersistence.localFromOpenBoxes();
    if (cache == null) return false;

    final configuredApiUrl = apiUrl.trim();
    final configuredAccessToken = accessToken.trim();
    if (configuredApiUrl.isEmpty || configuredAccessToken.isEmpty) {
      return false;
    }

    final baseUri = Uri.tryParse(configuredApiUrl);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL 无效：$configuredApiUrl');
    }

    _client?.close();
    final client = http.Client();

    try {
      final identity = await HttpWorkspaceAccountService(
        baseUri: baseUri,
        accessToken: configuredAccessToken,
        client: client,
      ).currentIdentity();

      final remote = HttpWorkspaceRemotePersistence(
        identity: identity,
        baseUri: baseUri,
        accessToken: configuredAccessToken,
        client: client,
      );
      final cloud = CloudBackedWorkspacePersistence(
        cache: cache,
        remote: remote,
      );

      await cloud.hydrateFromRemote();

      _client = client;
      _identity = identity;
      _enabled = true;
      HiveWorkspacePersistence.useRuntimePersistence(cloud);
      return true;
    } catch (_) {
      client.close();
      _identity = null;
      _enabled = false;
      rethrow;
    }
  }
}
