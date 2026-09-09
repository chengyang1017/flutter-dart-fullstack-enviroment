enum WorkspaceViewMode {
  project,
  concept,
  sourceControl,
}

extension WorkspaceViewModeInfo on WorkspaceViewMode {
  String get label => switch (this) {
        WorkspaceViewMode.project => '项目',
        WorkspaceViewMode.concept => '概念',
        WorkspaceViewMode.sourceControl => 'Git',
      };

  String get description => switch (this) {
        WorkspaceViewMode.project => '完整 Flutter 项目',
        WorkspaceViewMode.concept => '只直接操作 lib/',
        WorkspaceViewMode.sourceControl => '版本控制 · Stage / Diff / Commit',
      };

  bool get isConcept => this == WorkspaceViewMode.concept;
  bool get isSourceControl => this == WorkspaceViewMode.sourceControl;

  bool allowsPath(String path) {
    if (this != WorkspaceViewMode.concept) return true;

    final normalized = path.replaceAll('\\', '/');
    return normalized == 'lib' || normalized.startsWith('lib/');
  }
}
