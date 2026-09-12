import '../../workspace/models/workspace_capability.dart';
import '../../workspace/models/workspace_change.dart';

class WorkspaceRunnerSource {
  WorkspaceRunnerSource({
    required Map<String, String> files,
    required List<WorkspaceChange> changes,
    Set<FirebaseCapability> firebaseCapabilities = const <FirebaseCapability>{},
    this.remoteRevision,
  })  : files = Map<String, String>.unmodifiable(files),
        changes = List<WorkspaceChange>.unmodifiable(changes),
        firebaseCapabilities = Set<FirebaseCapability>.unmodifiable(
          firebaseCapabilities,
        );

  final Map<String, String> files;
  final List<WorkspaceChange> changes;
  final Set<FirebaseCapability> firebaseCapabilities;

  /// Opaque persisted Workspace revision used to identify the exact source
  /// version that was prepared for the disposable Runner.
  final String? remoteRevision;
}
