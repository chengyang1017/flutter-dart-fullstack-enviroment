enum WorkspaceSecretContext {
  runner,
  git,
  deploy,
}

class WorkspaceSecretMetadata {
  WorkspaceSecretMetadata({
    required String name,
    required Set<WorkspaceSecretContext> contexts,
    required this.createdAt,
    required this.updatedAt,
  })  : name = _validateName(name),
        contexts = Set<WorkspaceSecretContext>.unmodifiable(contexts) {
    if (contexts.isEmpty) {
      throw const FormatException(
        'Workspace secret metadata requires at least one context.',
      );
    }
  }

  final String name;
  final Set<WorkspaceSecretContext> contexts;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorkspaceSecretMetadata.fromJson(Map<dynamic, dynamic> json) {
    final name = json['name'];
    final rawContexts = json['contexts'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (name is! String ||
        rawContexts is! Iterable ||
        createdAt is! String ||
        updatedAt is! String) {
      throw const FormatException('Invalid Workspace secret metadata.');
    }

    final contexts = rawContexts.map((item) {
      if (item is! String) {
        throw const FormatException('Invalid Workspace secret context.');
      }
      return WorkspaceSecretContext.values.firstWhere(
        (context) => context.name == item,
        orElse: () => throw FormatException(
          'Unsupported Workspace secret context: $item',
        ),
      );
    }).toSet();

    final parsedCreatedAt = DateTime.tryParse(createdAt)?.toUtc();
    final parsedUpdatedAt = DateTime.tryParse(updatedAt)?.toUtc();
    if (parsedCreatedAt == null || parsedUpdatedAt == null) {
      throw const FormatException('Invalid Workspace secret timestamp.');
    }

    return WorkspaceSecretMetadata(
      name: name,
      contexts: contexts,
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  static String _validateName(String value) {
    final source = value.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(source)) {
      throw const FormatException(
        'Secret name must be an environment-style identifier up to 64 characters.',
      );
    }
    return source;
  }
}
