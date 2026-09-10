class WorkspaceGitRemoteCheckResult {
  const WorkspaceGitRemoteCheckResult({
    required this.repositoryUrl,
    required this.branch,
    required this.provider,
    required this.reachable,
    required this.branchFound,
    this.remoteHead,
    this.repositoryId,
    this.repositoryFullName,
    this.canonicalUrl,
  });

  final String repositoryUrl;
  final String branch;
  final String provider;
  final bool reachable;
  final bool branchFound;
  final String? remoteHead;
  final int? repositoryId;
  final String? repositoryFullName;
  final String? canonicalUrl;

  factory WorkspaceGitRemoteCheckResult.fromJson(Map<dynamic, dynamic> json) {
    final repositoryUrl = json['repositoryUrl'];
    final branch = json['branch'];
    final provider = json['provider'];
    final reachable = json['reachable'];
    final branchFound = json['branchFound'];
    final remoteHead = json['remoteHead'];
    final repositoryId = json['repositoryId'];
    final repositoryFullName = json['repositoryFullName'];
    final canonicalUrl = json['canonicalUrl'];
    if (repositoryUrl is! String ||
        branch is! String ||
        provider is! String ||
        reachable is! bool ||
        branchFound is! bool ||
        (remoteHead != null && remoteHead is! String) ||
        (repositoryId != null && repositoryId is! int) ||
        (repositoryFullName != null && repositoryFullName is! String) ||
        (canonicalUrl != null && canonicalUrl is! String)) {
      throw const FormatException('Invalid Git remote check response.');
    }
    return WorkspaceGitRemoteCheckResult(
      repositoryUrl: repositoryUrl,
      branch: branch,
      provider: provider,
      reachable: reachable,
      branchFound: branchFound,
      remoteHead: remoteHead as String?,
      repositoryId: repositoryId as int?,
      repositoryFullName: repositoryFullName as String?,
      canonicalUrl: canonicalUrl as String?,
    );
  }
}
