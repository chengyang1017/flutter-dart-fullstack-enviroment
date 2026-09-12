class WorkspaceGitPushResult {
  const WorkspaceGitPushResult({
    required this.repositoryUrl,
    required this.branch,
    required this.provider,
    required this.previousRemoteHead,
    required this.newRemoteHead,
    required this.committed,
  });

  final String repositoryUrl;
  final String branch;
  final String provider;
  final String previousRemoteHead;
  final String newRemoteHead;
  final bool committed;

  factory WorkspaceGitPushResult.fromJson(Map<dynamic, dynamic> json) {
    final repositoryUrl = json['repositoryUrl'];
    final branch = json['branch'];
    final provider = json['provider'];
    final previousRemoteHead = json['previousRemoteHead'];
    final newRemoteHead = json['newRemoteHead'];
    final committed = json['committed'];
    if (repositoryUrl is! String ||
        branch is! String ||
        provider is! String ||
        previousRemoteHead is! String ||
        newRemoteHead is! String ||
        committed is! bool ||
        !_isHead(previousRemoteHead) ||
        !_isHead(newRemoteHead)) {
      throw const FormatException('Invalid Git push response.');
    }
    return WorkspaceGitPushResult(
      repositoryUrl: repositoryUrl,
      branch: branch,
      provider: provider,
      previousRemoteHead: previousRemoteHead.toLowerCase(),
      newRemoteHead: newRemoteHead.toLowerCase(),
      committed: committed,
    );
  }

  static bool _isHead(String value) =>
      RegExp(r'^[A-Fa-f0-9]{7,128}$').hasMatch(value);
}

class WorkspaceGitRemoteHeadConflict implements Exception {
  const WorkspaceGitRemoteHeadConflict({
    required this.workspaceId,
    required this.expectedRemoteHead,
    required this.actualRemoteHead,
  });

  final String workspaceId;
  final String expectedRemoteHead;
  final String actualRemoteHead;

  @override
  String toString() =>
      'WorkspaceGitRemoteHeadConflict(workspaceId: $workspaceId, '
      'expected: $expectedRemoteHead, actual: $actualRemoteHead)';
}
