import 'package:http/http.dart' as http;

import '../models/workspace_identity.dart';
import 'http_workspace_remote_persistence.dart';
import 'workspace_remote_persistence.dart';
import 'workspace_remote_session_provider.dart';

class WorkspaceRemoteAuthSession {
  const WorkspaceRemoteAuthSession({
    required this.identity,
    required this.accessToken,
  });

  final WorkspaceIdentity identity;
  final String accessToken;
}

typedef WorkspaceRemoteAuthSessionResolver = Future<WorkspaceRemoteAuthSession?>
    Function();

class HttpWorkspaceRemoteSessionProvider
    implements WorkspaceRemoteSessionProvider {
  HttpWorkspaceRemoteSessionProvider({
    required this.baseUri,
    required this.resolveSession,
    required http.Client client,
  }) : _client = client;

  final Uri baseUri;
  final WorkspaceRemoteAuthSessionResolver resolveSession;
  final http.Client _client;

  @override
  Future<WorkspaceRemotePersistence?> currentRemote() async {
    final session = await resolveSession();
    if (session == null) return null;
    if (session.accessToken.trim().isEmpty) {
      throw StateError('Authenticated Workspace session has an empty token.');
    }

    return HttpWorkspaceRemotePersistence(
      identity: session.identity,
      baseUri: baseUri,
      accessToken: session.accessToken,
      client: _client,
    );
  }
}
