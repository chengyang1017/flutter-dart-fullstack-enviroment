import 'workspace_project.dart';
import 'workspace_snapshot.dart';

class WorkspaceRemoteCatalog {
  const WorkspaceRemoteCatalog({
    required this.projects,
    required this.revision,
  });

  final List<WorkspaceProject> projects;

  /// Opaque server revision. Clients compare it but must not interpret it.
  final String revision;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projects':
            projects.map((project) => project.toJson()).toList(growable: false),
        'revision': revision,
      };

  factory WorkspaceRemoteCatalog.fromJson(Map<dynamic, dynamic> json) {
    final rawProjects = json['projects'];
    final revision = json['revision'];
    if (rawProjects is! Iterable || revision is! String || revision.isEmpty) {
      throw const FormatException('Invalid remote Workspace catalog.');
    }

    final projects = <WorkspaceProject>[];
    for (final item in rawProjects) {
      if (item is! Map) {
        throw const FormatException('Invalid remote Workspace catalog row.');
      }
      projects.add(WorkspaceProject.fromJson(item));
    }

    return WorkspaceRemoteCatalog(
      projects: List<WorkspaceProject>.unmodifiable(projects),
      revision: revision,
    );
  }
}

class WorkspaceRemoteDocument {
  const WorkspaceRemoteDocument({
    required this.project,
    required this.snapshot,
    required this.revision,
  });

  final WorkspaceProject project;
  final WorkspaceSnapshot snapshot;

  /// Opaque server revision used for optimistic concurrency on saves.
  final String revision;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'project': project.toJson(),
        'snapshot': snapshot.toJson(),
        'revision': revision,
      };

  factory WorkspaceRemoteDocument.fromJson(Map<dynamic, dynamic> json) {
    final rawProject = json['project'];
    final rawSnapshot = json['snapshot'];
    final revision = json['revision'];
    if (rawProject is! Map ||
        rawSnapshot is! Map ||
        revision is! String ||
        revision.isEmpty) {
      throw const FormatException('Invalid remote Workspace document.');
    }

    return WorkspaceRemoteDocument(
      project: WorkspaceProject.fromJson(rawProject),
      snapshot: WorkspaceSnapshot.fromJson(rawSnapshot),
      revision: revision,
    );
  }
}

class WorkspaceHydrationResult {
  const WorkspaceHydrationResult({
    required this.catalog,
    required this.activeDocument,
  });

  final WorkspaceRemoteCatalog catalog;
  final WorkspaceRemoteDocument? activeDocument;
}

class WorkspaceRevisionConflict implements Exception {
  const WorkspaceRevisionConflict({
    required this.workspaceId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final String workspaceId;
  final String expectedRevision;
  final String actualRevision;

  @override
  String toString() => 'WorkspaceRevisionConflict(workspaceId: $workspaceId, '
      'expected: $expectedRevision, actual: $actualRevision)';
}
