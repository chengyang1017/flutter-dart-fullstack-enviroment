import 'package:hive/hive.dart';

import '../models/workspace_project.dart';
import 'workspace_project_catalog_store.dart';

class HiveWorkspaceProjectCatalogStore implements WorkspaceProjectCatalogStore {
  HiveWorkspaceProjectCatalogStore(this.box);

  static const _projectsKey = 'projects';
  static const _activeProjectIdKey = 'activeProjectId';

  final Box<dynamic> box;

  @override
  List<WorkspaceProject> loadProjects() {
    final raw = box.get(_projectsKey);
    if (raw is! Iterable) return const <WorkspaceProject>[];

    final result = <WorkspaceProject>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        result.add(WorkspaceProject.fromJson(item));
      } on FormatException {
        // Ignore corrupt catalog rows without discarding healthy projects.
      }
    }
    return result;
  }

  @override
  String? loadActiveProjectId() {
    final value = box.get(_activeProjectIdKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> saveProjects(List<WorkspaceProject> projects) {
    return box.put(
      _projectsKey,
      projects.map((project) => project.toJson()).toList(growable: false),
    );
  }

  @override
  Future<void> saveActiveProjectId(String projectId) {
    return box.put(_activeProjectIdKey, projectId);
  }
}
