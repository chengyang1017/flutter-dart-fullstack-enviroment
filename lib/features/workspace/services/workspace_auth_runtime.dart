import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import 'hive_workspace_persistence.dart';
import 'http_workspace_account_service.dart';
import 'http_workspace_auth_service.dart';
import 'workspace_auth_session_store.dart';
import 'workspace_cloud_runtime.dart';

/// Application-level account/session runtime.
///
/// A stored bearer session is restored on startup. New sessions come from the
/// server's register/login endpoints; userId and username are never chosen by
/// the client.
class WorkspaceAuthRuntime {
  WorkspaceAuthRuntime._();

  static const _developmentAccessToken =
      String.fromEnvironment('WORKSPACE_ACCESS_TOKEN');

  static Object? _startupError;

  static bool get cloudConfigured =>
      WorkspaceCloudRuntime.apiUrl.trim().isNotEmpty;
  static bool get isAuthenticated => WorkspaceCloudRuntime.identity != null;
  static WorkspaceIdentity? get identity => WorkspaceCloudRuntime.identity;
  static String? get accessToken => WorkspaceCloudRuntime.accessToken;
  static Object? get startupError => _startupError;

  /// True only when the active session came from the compile-time development
  /// token and has not yet been converted into a normal persisted account
  /// session.
  static bool get canClaimExistingAccount =>
      isAuthenticated &&
      WorkspaceAuthSessionStore.accessToken == null &&
      _developmentAccessToken.trim().isNotEmpty;

  static Future<bool> bootstrap() async {
    _startupError = null;
    if (!cloudConfigured) {
      WorkspaceCloudRuntime.reset();
      return false;
    }

    final storedToken = WorkspaceAuthSessionStore.accessToken;
    final developmentToken = _developmentAccessToken.trim();
    final token = storedToken ??
        (developmentToken.isEmpty ? null : developmentToken);
    if (token == null) {
      WorkspaceCloudRuntime.reset();
      return false;
    }

    try {
      await _activate(
        token,
        persistToken: storedToken != null,
      );
      return true;
    } on WorkspaceAccountRequestException catch (error) {
      if (error.statusCode == 401) {
        if (storedToken != null) {
          await WorkspaceAuthSessionStore.clearAccessToken();
        }
        WorkspaceCloudRuntime.reset();
        return false;
      }
      _startupError = error;
      WorkspaceCloudRuntime.reset();
      return false;
    } catch (error) {
      _startupError = error;
      WorkspaceCloudRuntime.reset();
      return false;
    }
  }

  static Future<WorkspaceIdentity> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final service = _authService();
    try {
      final session = await service.service.register(
        username: username,
        email: email,
        password: password,
      );
      return _activate(
        session.accessToken,
        resolvedIdentity: session.identity,
        persistToken: true,
      );
    } finally {
      service.client.close();
    }
  }

  static Future<WorkspaceIdentity> claimExistingAccount({
    required String email,
    required String password,
  }) async {
    final token = WorkspaceCloudRuntime.accessToken;
    if (!canClaimExistingAccount || token == null || token.trim().isEmpty) {
      throw StateError('当前会话不是可绑定的开发账号。');
    }

    final service = _authService();
    try {
      final session = await service.service.claimExisting(
        accessToken: token,
        email: email,
        password: password,
      );
      return _activate(
        session.accessToken,
        resolvedIdentity: session.identity,
        persistToken: true,
      );
    } finally {
      service.client.close();
    }
  }

  static Future<WorkspaceIdentity> login({
    required String email,
    required String password,
  }) async {
    final service = _authService();
    try {
      final session = await service.service.login(
        email: email,
        password: password,
      );
      return _activate(
        session.accessToken,
        resolvedIdentity: session.identity,
        persistToken: true,
      );
    } finally {
      service.client.close();
    }
  }

  static Future<void> logout() async {
    final token = WorkspaceCloudRuntime.accessToken ??
        WorkspaceAuthSessionStore.accessToken;
    if (token != null && token.trim().isNotEmpty && cloudConfigured) {
      final service = _authService();
      try {
        await service.service.logout(token);
      } catch (_) {
        // Local sign-out must still succeed if the server is temporarily
        // unreachable or this was a non-revocable development token.
      } finally {
        service.client.close();
      }
    }

    WorkspaceCloudRuntime.reset();
    await WorkspaceAuthSessionStore.clearAll();
    await HiveWorkspacePersistence.clearLocalCache();
    _startupError = null;
  }

  static Future<WorkspaceIdentity> _activate(
    String token, {
    WorkspaceIdentity? resolvedIdentity,
    required bool persistToken,
  }) async {
    final identity = resolvedIdentity ?? await _resolveIdentity(token);
    final previousCacheUser = WorkspaceAuthSessionStore.cacheUserId;
    if (previousCacheUser != null && previousCacheUser != identity.userId) {
      await HiveWorkspacePersistence.clearLocalCache();
    }

    final activated = await WorkspaceCloudRuntime.initializeWithAccessToken(
      token,
      resolvedIdentity: identity,
    );
    if (persistToken) {
      await WorkspaceAuthSessionStore.saveAccessToken(token);
    }
    await WorkspaceAuthSessionStore.bindCacheToUser(activated.userId);
    _startupError = null;
    return activated;
  }

  static Future<WorkspaceIdentity> _resolveIdentity(String token) async {
    final baseUri = _baseUri();
    final client = http.Client();
    try {
      return HttpWorkspaceAccountService(
        baseUri: baseUri,
        accessToken: token,
        client: client,
      ).currentIdentity();
    } finally {
      client.close();
    }
  }

  static _AuthServiceHandle _authService() {
    final client = http.Client();
    return _AuthServiceHandle(
      client,
      HttpWorkspaceAuthService(
        baseUri: _baseUri(),
        client: client,
      ),
    );
  }

  static Uri _baseUri() {
    final source = WorkspaceCloudRuntime.apiUrl.trim();
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL 无效：$source');
    }
    return uri;
  }
}

class _AuthServiceHandle {
  const _AuthServiceHandle(this.client, this.service);

  final http.Client client;
  final HttpWorkspaceAuthService service;
}
