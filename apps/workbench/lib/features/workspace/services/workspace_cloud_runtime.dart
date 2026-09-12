import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import 'cloud_backed_workspace_persistence.dart';
import 'hive_workspace_persistence.dart';
import 'http_workspace_account_service.dart';
import 'http_workspace_remote_persistence.dart';

/// Boots the app's cloud-first Workspace persistence from an authenticated
/// session. The account identity is always resolved by the server.
class WorkspaceCloudRuntime {
  WorkspaceCloudRuntime._();

  static const apiUrl = String.fromEnvironment(
    'WORKSPACE_STORAGE_API_URL',
    defaultValue: 'https://workspace-storage-production.up.railway.app',
  );
  static const _environmentAccessToken =
      String.fromEnvironment('WORKSPACE_ACCESS_TOKEN');

  static http.Client? _client;
  static bool _enabled = false;
  static WorkspaceIdentity? _identity;
  static String? _accessToken;

  static bool get enabled => _enabled;
  static WorkspaceIdentity? get identity => _identity;
  static String? get accessToken => _accessToken;

  /// Backward-compatible development bootstrap. Interactive account login uses
  /// [initializeWithAccessToken] instead of a compile-time bearer token.
  static Future<bool> initializeFromEnvironment() async {
    final token = _environmentAccessToken.trim();
    if (token.isEmpty) return false;
    await initializeWithAccessToken(token);
    return true;
  }

  static Future<WorkspaceIdentity> initializeWithAccessToken(
    String accessToken, {
    WorkspaceIdentity? resolvedIdentity,
  }) async {
    final cache = HiveWorkspacePersistence.localFromOpenBoxes();
    if (cache == null) {
      throw StateError('Workspace browser cache is not available.');
    }

    final configuredApiUrl = apiUrl.trim();
    final configuredAccessToken = accessToken.trim();
    if (configuredApiUrl.isEmpty) {
      throw StateError('WORKSPACE_STORAGE_API_URL is not configured.');
    }
    if (configuredAccessToken.isEmpty) {
      throw StateError('Workspace access token is empty.');
    }

    final baseUri = Uri.tryParse(configuredApiUrl);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL 无效：$configuredApiUrl');
    }

    _client?.close();
    _enabled = false;
    _identity = null;
    _accessToken = null;
    HiveWorkspacePersistence.clearRuntimePersistence();

    final client = http.Client();
    try {
      final identity = resolvedIdentity ??
          await HttpWorkspaceAccountService(
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
      _accessToken = configuredAccessToken;
      _enabled = true;
      HiveWorkspacePersistence.useRuntimePersistence(cloud);
      return identity;
    } catch (_) {
      client.close();
      _identity = null;
      _accessToken = null;
      _enabled = false;
      HiveWorkspacePersistence.clearRuntimePersistence();
      rethrow;
    }
  }

  static void reset() {
    _client?.close();
    _client = null;
    _identity = null;
    _accessToken = null;
    _enabled = false;
    HiveWorkspacePersistence.clearRuntimePersistence();
  }
}
