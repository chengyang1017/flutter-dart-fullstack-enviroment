class WorkspaceIdentity {
  const WorkspaceIdentity({
    required this.userId,
    this.username,
  });

  /// Stable account id resolved from the authenticated server session.
  ///
  /// This value identifies the current platform account. Workspace ownership
  /// must still be enforced by the server; clients must never be trusted to
  /// choose an arbitrary owner id for remote operations.
  final String userId;

  /// Human-readable account namespace resolved by the server, for example
  /// `chengyang1017`. It is intentionally separate from [userId] so changing a
  /// username never changes Workspace ownership.
  final String? username;

  String get accountNamespace {
    final value = username?.trim();
    return value == null || value.isEmpty ? userId : value;
  }

  @override
  String toString() =>
      'WorkspaceIdentity(userId: $userId, username: $username)';
}
