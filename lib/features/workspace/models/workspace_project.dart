import 'workspace_capability.dart';
import 'workspace_git_remote.dart';

enum WorkspaceProjectKind {
  practice,
  importedFlutter,
}

enum WorkspaceLifecycle {
  temporary,
  saved,
}

class WorkspaceProject {
  const WorkspaceProject({
    required this.id,
    required this.name,
    required this.storageKey,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.lifecycle = WorkspaceLifecycle.saved,
    this.firebaseCapabilities = const <FirebaseCapability>{},
    this.gitRemote,
  });

  final String id;
  final String name;
  final String storageKey;
  final WorkspaceProjectKind kind;
  final WorkspaceLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Set<FirebaseCapability> firebaseCapabilities;
  final WorkspaceGitRemote? gitRemote;

  WorkspaceProject copyWith({
    String? name,
    WorkspaceLifecycle? lifecycle,
    DateTime? updatedAt,
    Set<FirebaseCapability>? firebaseCapabilities,
    WorkspaceGitRemote? gitRemote,
    bool clearGitRemote = false,
  }) {
    return WorkspaceProject(
      id: id,
      name: name ?? this.name,
      storageKey: storageKey,
      kind: kind,
      lifecycle: lifecycle ?? this.lifecycle,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firebaseCapabilities: firebaseCapabilities ?? this.firebaseCapabilities,
      gitRemote: clearGitRemote ? null : gitRemote ?? this.gitRemote,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'storageKey': storageKey,
        'kind': kind.name,
        'lifecycle': lifecycle.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'firebaseCapabilities': FirebaseCapabilityCodec.encode(
          firebaseCapabilities,
        ),
        if (gitRemote != null) 'gitRemote': gitRemote!.toJson(),
      };

  factory WorkspaceProject.fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final storageKey = json['storageKey'];
    if (id is! String || id.isEmpty ||
        name is! String || name.isEmpty ||
        storageKey is! String || storageKey.isEmpty) {
      throw const FormatException('Invalid workspace project metadata.');
    }

    final kindName = json['kind'];
    final kind = WorkspaceProjectKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => WorkspaceProjectKind.practice,
    );

    final lifecycleName = json['lifecycle'];
    final lifecycle = WorkspaceLifecycle.values.firstWhere(
      (value) => value.name == lifecycleName,
      orElse: () => WorkspaceLifecycle.saved,
    );

    WorkspaceGitRemote? readGitRemote(Object? value) {
      if (value == null) return null;
      if (value is! Map) {
        throw const FormatException('Invalid Workspace Git remote metadata.');
      }
      return WorkspaceGitRemote.fromJson(value);
    }

    DateTime readDate(dynamic value) => value is String
        ? DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();

    return WorkspaceProject(
      id: id,
      name: name,
      storageKey: storageKey,
      kind: kind,
      lifecycle: lifecycle,
      createdAt: readDate(json['createdAt']),
      updatedAt: readDate(json['updatedAt']),
      firebaseCapabilities: FirebaseCapabilityCodec.decode(
        json['firebaseCapabilities'],
      ),
      gitRemote: readGitRemote(json['gitRemote']),
    );
  }
}
