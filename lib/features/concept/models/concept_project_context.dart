import '../../workspace/models/workspace_snapshot.dart';

class ConceptProjectContext {
  const ConceptProjectContext({
    required this.repositoryName,
    required this.projectName,
    required this.projectRoot,
    this.backendRoot,
    this.backendSourceRoot,
  });

  final String repositoryName;
  final String projectName;

  /// Path of the selected Flutter project inside the repository.
  /// Empty means the repository root itself is the Flutter project root.
  final String projectRoot;

  /// Root of the detected backend package inside the source repository.
  final String? backendRoot;

  /// Source directory exposed as the virtual `backend/` concept root.
  ///
  /// Serverpod maps its server `lib/` here. Node backends normally map `src/`.
  final String? backendSourceRoot;

  bool get isMonorepoProject => projectRoot.isNotEmpty;
  bool get hasBackend =>
      backendSourceRoot != null && backendSourceRoot!.isNotEmpty;

  String get sourceLabel {
    if (projectRoot.isEmpty) return repositoryName;
    return '$repositoryName / $projectRoot';
  }

  String toRepositoryPath(String conceptPath) {
    final normalized = _normalizeRelative(conceptPath);
    final backendSource = backendSourceRoot;
    if (backendSource != null && backendSource.isNotEmpty) {
      if (normalized == 'backend') return backendSource;
      if (normalized.startsWith('backend/')) {
        return '$backendSource/${normalized.substring('backend/'.length)}';
      }
    }

    if (projectRoot.isEmpty) return normalized;
    if (normalized.isEmpty) return projectRoot;
    return '$projectRoot/$normalized';
  }

  String? toConceptPath(String repositoryPath) {
    final normalized = _normalizeRelative(repositoryPath);
    final backendSource = backendSourceRoot;
    if (backendSource != null && backendSource.isNotEmpty) {
      if (normalized == backendSource) return 'backend';
      final backendPrefix = '$backendSource/';
      if (normalized.startsWith(backendPrefix)) {
        return 'backend/${normalized.substring(backendPrefix.length)}';
      }
    }

    if (projectRoot.isEmpty) return normalized;
    if (normalized == projectRoot) return '';
    final prefix = '$projectRoot/';
    if (!normalized.startsWith(prefix)) return null;
    return normalized.substring(prefix.length);
  }

  static String _normalizeRelative(String value) {
    var normalized = value.replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.endsWith('/') && normalized.isNotEmpty) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

class ConceptProjectProjection {
  const ConceptProjectProjection({
    required this.context,
    required this.snapshot,
  });

  final ConceptProjectContext context;
  final WorkspaceSnapshot snapshot;
}
