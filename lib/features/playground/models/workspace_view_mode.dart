import '../../../core/l10n/app_localizations.dart';

enum WorkspaceViewMode {
  project,
  concept,
  sourceControl,
}

String _localized(String zh, String en) =>
    AppLocaleController.locale.value.languageCode == 'en' ? en : zh;

extension WorkspaceViewModeInfo on WorkspaceViewMode {
  String get label => switch (this) {
        WorkspaceViewMode.project => _localized('项目', 'Project'),
        WorkspaceViewMode.concept => _localized('概念', 'Concept'),
        WorkspaceViewMode.sourceControl => 'Git',
      };

  String get description => switch (this) {
        WorkspaceViewMode.project =>
          _localized('完整 Flutter 项目', 'Complete Flutter project'),
        WorkspaceViewMode.concept => _localized('应用 + 后端', 'App + Backend'),
        WorkspaceViewMode.sourceControl =>
          _localized('版本控制 · Stage / Diff / Commit', 'Version control · Stage / Diff / Commit'),
      };

  bool get isConcept => this == WorkspaceViewMode.concept;
  bool get isSourceControl => this == WorkspaceViewMode.sourceControl;

  bool allowsPath(String path) {
    if (this != WorkspaceViewMode.concept) return true;

    final normalized = path.replaceAll('\\', '/');
    return normalized == 'lib' ||
        normalized.startsWith('lib/') ||
        normalized == 'backend' ||
        normalized.startsWith('backend/') ||
        normalized == 'serverpod/practice_server/lib' ||
        normalized.startsWith('serverpod/practice_server/lib/') ||
        normalized.endsWith('/lib') ||
        normalized.contains('/lib/') ||
        normalized.endsWith('/src') ||
        normalized.contains('/src/');
  }
}
