import '../models/workspace_project.dart';

abstract interface class WorkspaceProjectCatalogStore {
  List<WorkspaceProject> loadProjects();

  String? loadActiveProjectId();

  Future<void> saveProjects(List<WorkspaceProject> projects);

  Future<void> saveActiveProjectId(String projectId);
}
