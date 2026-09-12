import '../models/workspace_secret.dart';

abstract interface class WorkspaceSecretService {
  Future<List<WorkspaceSecretMetadata>> listSecrets(String workspaceId);

  Future<WorkspaceSecretMetadata> putSecret({
    required String workspaceId,
    required String name,
    required String value,
    required Set<WorkspaceSecretContext> contexts,
  });

  Future<void> deleteSecret({
    required String workspaceId,
    required String name,
  });
}
