enum WorkspaceChangeType {
  created,
  modified,
  deleted,
  renamed,
  moved,
}

class WorkspaceChange {
  const WorkspaceChange({
    required this.type,
    required this.path,
    this.previousPath,
  });

  final WorkspaceChangeType type;
  final String path;
  final String? previousPath;
}
