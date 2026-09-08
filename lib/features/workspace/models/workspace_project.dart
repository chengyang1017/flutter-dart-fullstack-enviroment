import 'workspace_capability.dart';
import 'workspace_git_remote.dart';

enum WorkspaceProjectKind {
  practice,
  generatedFlutter,
  importedFlutter,
}

enum WorkspaceLifecycle {
  temporary,
  saved,
}

String normalizeWorkspaceProjectSlug(String value) {
  var slug = value.trim().toLowerCase();
  slug = slug.replaceAll(RegExp(r'[\s/\\?#%]+'), '-');
  slug = slug.replaceAll(RegExp(r'-+'), '-');
  slug = slug.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return slug.isEmpty ? 'project' : slug;
}

class WorkspaceProject {
  const WorkspaceProject({
    required this.id,
    required this.name,
    required this.storageKey,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    String? slug,
    this.lifecycle = WorkspaceLifecycle.saved,
    this.firebaseCapabilities = const <FirebaseCapability>{},
    this.flutterPlatforms = const <String>{},
    this.gitRemote,
  }) : _slug = slug;

  final String id;
  final String name;
  final String storageKey;
  final String? _slug;
  final WorkspaceProjectKind kind;
  final WorkspaceLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;

  final Set<FirebaseCapability> firebaseCapabilities;

  final Set<String> flutterPlatforms;

  final WorkspaceGitRemote? gitRemote;

  /// Human-readable project route segment. The immutable [id] remains the
  /// storage identity, while this slug can change when the project is renamed.
  String get slug => normalizeWorkspaceProjectSlug(_slug ?? name);

  WorkspaceProject copyWith({
    String? name,
    String? slug,
    bool clearSlug = false,
    WorkspaceLifecycle? lifecycle,
    DateTime? updatedAt,
    Set<FirebaseCapability>? firebaseCapabilities,
    Set<String>? flutterPlatforms,
    WorkspaceGitRemote? gitRemote,
    bool clearGitRemote = false,
  }) {
    return WorkspaceProject(
      id: id,
      name: name ?? this.name,
      storageKey: storageKey,
      slug: clearSlug ? null : slug ?? _slug,
      kind: kind,
      lifecycle: lifecycle ?? this.lifecycle,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firebaseCapabilities: firebaseCapabilities ?? this.firebaseCapabilities,
      flutterPlatforms: flutterPlatforms ?? this.flutterPlatforms,
      gitRemote: clearGitRemote ? null : gitRemote ?? this.gitRemote,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'slug': slug,
        'storageKey': storageKey,
        'kind': kind.name,
        'lifecycle': lifecycle.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'firebaseCapabilities': FirebaseCapabilityCodec.encode(
          firebaseCapabilities,
        ),
        'flutterPlatforms': flutterPlatforms.toList()..sort(),
        if (gitRemote != null) 'gitRemote': gitRemote!.toJson(),
      };

  factory WorkspaceProject.fromJson(
    Map<dynamic, dynamic> json,
  ) {
    final id = json['id'];
    final name = json['name'];
    final storageKey = json['storageKey'];

    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        storageKey is! String ||
        storageKey.isEmpty) {
      throw const FormatException(
        'Invalid workspace project metadata.',
      );
    }

    final rawSlug = json['slug'];
    if (rawSlug != null && rawSlug is! String) {
      throw const FormatException('Invalid Workspace project slug.');
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

    WorkspaceGitRemote? readGitRemote(
      Object? value,
    ) {
      if (value == null) return null;

      if (value is! Map) {
        throw const FormatException(
          'Invalid Workspace Git remote metadata.',
        );
      }

      return WorkspaceGitRemote.fromJson(
        value,
      );
    }

    DateTime readDate(dynamic value) {
      return value is String
          ? DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc();
    }

    final rawPlatforms = json['flutterPlatforms'];

    final flutterPlatforms = rawPlatforms is Iterable
        ? rawPlatforms.whereType<String>().toSet()
        : <String>{};

    return WorkspaceProject(
      id: id,
      name: name,
      slug: rawSlug is String && rawSlug.trim().isNotEmpty ? rawSlug : null,
      storageKey: storageKey,
      kind: kind,
      lifecycle: lifecycle,
      createdAt: readDate(json['createdAt']),
      updatedAt: readDate(json['updatedAt']),
      firebaseCapabilities: FirebaseCapabilityCodec.decode(
        json['firebaseCapabilities'],
      ),
      flutterPlatforms: flutterPlatforms,
      gitRemote: readGitRemote(json['gitRemote']),
    );
  }
}
