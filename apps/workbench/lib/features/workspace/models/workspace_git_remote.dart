enum WorkspaceGitProvider {
  github,
  gitlab,
  bitbucket,
  generic,
}

class WorkspaceGitRemote {
  factory WorkspaceGitRemote({
    required String repositoryUrl,
    String remoteName = 'origin',
    String branch = 'main',
    String? projectPath,
    WorkspaceGitProvider? provider,
    String? lastSyncedHead,
    int? repositoryId,
    String? repositoryFullName,
    String? canonicalUrl,
    DateTime? lastResolvedAt,
  }) {
    final normalizedUrl = _normalizeRepositoryUrl(repositoryUrl);
    return WorkspaceGitRemote._(
      repositoryUrl: normalizedUrl,
      remoteName: _validateRemoteName(remoteName),
      branch: _validateBranch(branch),
      projectPath: _validateProjectPath(projectPath),
      provider: provider ?? _detectProvider(normalizedUrl),
      lastSyncedHead: _validateSyncedHead(lastSyncedHead),
      repositoryId: _validateRepositoryId(repositoryId),
      repositoryFullName: _validateRepositoryFullName(repositoryFullName),
      canonicalUrl: _validateCanonicalUrl(canonicalUrl),
      lastResolvedAt: lastResolvedAt?.toUtc(),
    );
  }

  const WorkspaceGitRemote._({
    required this.repositoryUrl,
    required this.remoteName,
    required this.branch,
    required this.projectPath,
    required this.provider,
    required this.lastSyncedHead,
    required this.repositoryId,
    required this.repositoryFullName,
    required this.canonicalUrl,
    required this.lastResolvedAt,
  });

  /// Repository location only. Credentials, access tokens and SSH private keys
  /// must never be stored here; they belong to the Workspace secret store.
  final String repositoryUrl;
  final String remoteName;
  final String branch;

  /// Optional path to one Flutter project inside a monorepo, for example
  /// `apps/mobile`. Null means auto-detect one runnable Flutter project.
  final String? projectPath;

  final WorkspaceGitProvider provider;

  /// Last remote commit that was safely imported into this Workspace.
  /// This is non-secret concurrency metadata used to guard future pushes.
  final String? lastSyncedHead;

  /// Stable GitHub repository identity. This survives repository renames and
  /// owner transfers, unlike owner/name and repository URLs.
  final int? repositoryId;

  /// Latest canonical GitHub owner/name, for example `owner/repository`.
  final String? repositoryFullName;

  /// Latest canonical GitHub browser URL.
  final String? canonicalUrl;

  /// Last successful canonical identity resolution.
  final DateTime? lastResolvedAt;

  WorkspaceGitRemote copyWith({
    String? repositoryUrl,
    String? remoteName,
    String? branch,
    String? projectPath,
    bool clearProjectPath = false,
    WorkspaceGitProvider? provider,
    String? lastSyncedHead,
    bool clearLastSyncedHead = false,
    int? repositoryId,
    bool clearRepositoryId = false,
    String? repositoryFullName,
    bool clearRepositoryFullName = false,
    String? canonicalUrl,
    bool clearCanonicalUrl = false,
    DateTime? lastResolvedAt,
    bool clearLastResolvedAt = false,
  }) {
    return WorkspaceGitRemote(
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      remoteName: remoteName ?? this.remoteName,
      branch: branch ?? this.branch,
      projectPath: clearProjectPath ? null : projectPath ?? this.projectPath,
      provider: provider ?? this.provider,
      lastSyncedHead:
          clearLastSyncedHead ? null : lastSyncedHead ?? this.lastSyncedHead,
      repositoryId:
          clearRepositoryId ? null : repositoryId ?? this.repositoryId,
      repositoryFullName: clearRepositoryFullName
          ? null
          : repositoryFullName ?? this.repositoryFullName,
      canonicalUrl:
          clearCanonicalUrl ? null : canonicalUrl ?? this.canonicalUrl,
      lastResolvedAt:
          clearLastResolvedAt ? null : lastResolvedAt ?? this.lastResolvedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'repositoryUrl': repositoryUrl,
        'remoteName': remoteName,
        'branch': branch,
        if (projectPath != null) 'projectPath': projectPath,
        'provider': provider.name,
        if (lastSyncedHead != null) 'lastSyncedHead': lastSyncedHead,
        if (repositoryId != null) 'repositoryId': repositoryId,
        if (repositoryFullName != null)
          'repositoryFullName': repositoryFullName,
        if (canonicalUrl != null) 'canonicalUrl': canonicalUrl,
        if (lastResolvedAt != null)
          'lastResolvedAt': lastResolvedAt!.toUtc().toIso8601String(),
      };

  factory WorkspaceGitRemote.fromJson(Map<dynamic, dynamic> json) {
    final repositoryUrl = json['repositoryUrl'];
    final remoteName = json['remoteName'];
    final branch = json['branch'];
    final projectPath = json['projectPath'];
    final lastSyncedHead = json['lastSyncedHead'];
    final repositoryId = json['repositoryId'];
    final repositoryFullName = json['repositoryFullName'];
    final canonicalUrl = json['canonicalUrl'];
    final lastResolvedAt = json['lastResolvedAt'];
    if (repositoryUrl is! String ||
        remoteName is! String ||
        branch is! String ||
        (projectPath != null && projectPath is! String) ||
        (lastSyncedHead != null && lastSyncedHead is! String) ||
        (repositoryId != null && repositoryId is! int) ||
        (repositoryFullName != null && repositoryFullName is! String) ||
        (canonicalUrl != null && canonicalUrl is! String) ||
        (lastResolvedAt != null && lastResolvedAt is! String)) {
      throw const FormatException('Invalid Workspace Git remote metadata.');
    }

    final providerName = json['provider'];
    final provider = WorkspaceGitProvider.values.firstWhere(
      (value) => value.name == providerName,
      orElse: () => WorkspaceGitProvider.generic,
    );

    return WorkspaceGitRemote(
      repositoryUrl: repositoryUrl,
      remoteName: remoteName,
      branch: branch,
      projectPath: projectPath as String?,
      provider: provider,
      lastSyncedHead: lastSyncedHead as String?,
      repositoryId: repositoryId as int?,
      repositoryFullName: repositoryFullName as String?,
      canonicalUrl: canonicalUrl as String?,
      lastResolvedAt: lastResolvedAt == null
          ? null
          : DateTime.tryParse(lastResolvedAt)?.toUtc(),
    );
  }

  static int? _validateRepositoryId(int? value) {
    if (value == null) return null;
    if (value <= 0) {
      throw const FormatException('Invalid Git repository id.');
    }
    return value;
  }

  static String? _validateRepositoryFullName(String? value) {
    if (value == null) return null;
    final source = value.trim();
    if (!RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(source)) {
      throw const FormatException('Invalid Git repository full name.');
    }
    return source;
  }

  static String? _validateCanonicalUrl(String? value) {
    if (value == null) return null;
    final source = value.trim();
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.pathSegments.where((part) => part.isNotEmpty).length < 2) {
      throw const FormatException('Invalid GitHub canonical repository URL.');
    }
    return source.endsWith('/')
        ? source.substring(0, source.length - 1)
        : source;
  }

  static String _normalizeRepositoryUrl(String value) {
    final source = value.trim();
    if (source.isEmpty) {
      throw const FormatException('Git repository URL cannot be empty.');
    }

    final scpStyle = RegExp(
      r'^[A-Za-z0-9._-]+@([A-Za-z0-9.-]+):([^\s]+)$',
    ).firstMatch(source);
    if (scpStyle != null) {
      if (source.contains('@{') || source.contains('://')) {
        throw const FormatException('Invalid SSH Git repository URL.');
      }
      return source;
    }

    final uri = Uri.tryParse(source);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('Git repository URL must include a host.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http' && uri.scheme != 'ssh') {
      throw const FormatException(
        'Git repository URL must use HTTPS, HTTP or SSH.',
      );
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Git repository URL cannot contain query parameters or fragments.',
      );
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (uri.userInfo.isNotEmpty) {
        throw const FormatException(
          'Git credentials must not be embedded in the repository URL.',
        );
      }
    } else if (uri.userInfo.contains(':')) {
      throw const FormatException(
        'SSH passwords must not be embedded in the repository URL.',
      );
    }

    final meaningfulPath = uri.pathSegments.where((part) => part.isNotEmpty);
    if (meaningfulPath.length < 2) {
      throw const FormatException(
        'Git repository URL must identify a repository path.',
      );
    }
    return source.endsWith('/')
        ? source.substring(0, source.length - 1)
        : source;
  }

  static String _validateRemoteName(String value) {
    final source = value.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{1,40}$').hasMatch(source) ||
        source == '.' ||
        source == '..') {
      throw const FormatException('Invalid Git remote name.');
    }
    return source;
  }

  static String _validateBranch(String value) {
    final source = value.trim();
    final validCharacters = RegExp(r'^[A-Za-z0-9._/-]+$');
    if (source.isEmpty ||
        !validCharacters.hasMatch(source) ||
        source.startsWith('/') ||
        source.endsWith('/') ||
        source.startsWith('.') ||
        source.endsWith('.') ||
        source.endsWith('.lock') ||
        source.contains('..') ||
        source.contains('//') ||
        source.contains('@{')) {
      throw const FormatException('Invalid Git branch name.');
    }
    return source;
  }

  static String? _validateProjectPath(String? value) {
    if (value == null) return null;
    var source = value.trim();
    if (source.isEmpty) return null;
    while (source.endsWith('/')) {
      source = source.substring(0, source.length - 1);
    }
    if (source.isEmpty ||
        source.startsWith('/') ||
        source.contains('\\') ||
        source.contains('//')) {
      throw const FormatException('Invalid Git Flutter project path.');
    }
    final parts = source.split('/');
    if (parts.any((part) =>
        part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.contains('\u0000'))) {
      throw const FormatException('Invalid Git Flutter project path.');
    }
    return source;
  }

  static String? _validateSyncedHead(String? value) {
    if (value == null) return null;
    final source = value.trim();
    if (!RegExp(r'^[A-Fa-f0-9]{7,128}$').hasMatch(source)) {
      throw const FormatException('Invalid Git synced commit id.');
    }
    return source.toLowerCase();
  }

  static WorkspaceGitProvider _detectProvider(String repositoryUrl) {
    final scpStyle = RegExp(
      r'^[A-Za-z0-9._-]+@([A-Za-z0-9.-]+):',
    ).firstMatch(repositoryUrl);
    final host = (scpStyle?.group(1) ?? Uri.tryParse(repositoryUrl)?.host ?? '')
        .toLowerCase();
    return switch (host) {
      'github.com' => WorkspaceGitProvider.github,
      'gitlab.com' => WorkspaceGitProvider.gitlab,
      'bitbucket.org' => WorkspaceGitProvider.bitbucket,
      _ => WorkspaceGitProvider.generic,
    };
  }
}
