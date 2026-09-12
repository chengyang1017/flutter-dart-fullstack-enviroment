import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../models/concept_project_context.dart';

class ConceptFlutterProjectCandidate {
  const ConceptFlutterProjectCandidate({
    required this.projectRoot,
    required this.projectName,
  });

  final String projectRoot;
  final String projectName;

  String get displayPath => projectRoot.isEmpty ? '/' : projectRoot;
}

enum ConceptBackendKind {
  serverpod,
  node,
}

class ConceptBackendProjectCandidate {
  const ConceptBackendProjectCandidate({
    required this.projectRoot,
    required this.sourceRoot,
    required this.projectName,
    required this.kind,
  });

  final String projectRoot;
  final String sourceRoot;
  final String projectName;
  final ConceptBackendKind kind;

  String get displayPath => projectRoot.isEmpty ? '/' : projectRoot;
}

class ConceptProjectProjectionService {
  const ConceptProjectProjectionService();

  List<ConceptFlutterProjectCandidate> detectFlutterProjects(
    WorkspaceSnapshot repositorySnapshot,
  ) {
    final byPath = <String, WorkspaceEntry>{
      for (final entry in repositorySnapshot.entries) entry.path: entry,
    };
    final candidates = <ConceptFlutterProjectCandidate>[];

    for (final entry in repositorySnapshot.entries) {
      if (!entry.isFile || !entry.isText) continue;
      if (entry.path != 'pubspec.yaml' &&
          !entry.path.endsWith('/pubspec.yaml')) {
        continue;
      }

      final root = entry.path == 'pubspec.yaml'
          ? ''
          : entry.path.substring(
              0,
              entry.path.length - '/pubspec.yaml'.length,
            );
      final mainPath = _join(root, 'lib/main.dart');
      final main = byPath[mainPath];
      if (main == null || !main.isFile || !main.isText) continue;
      if (!_looksLikeFlutterPubspec(entry.content)) continue;

      candidates.add(
        ConceptFlutterProjectCandidate(
          projectRoot: root,
          projectName: _projectName(entry.content, root),
        ),
      );
    }

    candidates.sort((a, b) {
      final depth = _depth(a.projectRoot).compareTo(_depth(b.projectRoot));
      return depth != 0 ? depth : a.projectRoot.compareTo(b.projectRoot);
    });
    return List<ConceptFlutterProjectCandidate>.unmodifiable(candidates);
  }

  List<ConceptBackendProjectCandidate> detectBackendProjects(
    WorkspaceSnapshot repositorySnapshot, {
    required ConceptFlutterProjectCandidate app,
  }) {
    final byPath = <String, WorkspaceEntry>{
      for (final entry in repositorySnapshot.entries) entry.path: entry,
    };
    final candidates = <ConceptBackendProjectCandidate>[];

    for (final entry in repositorySnapshot.entries) {
      if (!entry.isFile || !entry.isText) continue;
      if (entry.path != 'pubspec.yaml' &&
          !entry.path.endsWith('/pubspec.yaml')) {
        continue;
      }

      final root = _manifestRoot(entry.path, 'pubspec.yaml');
      if (root == app.projectRoot || !_looksLikeServerpodPubspec(entry.content)) {
        continue;
      }
      final sourceRoot = _existingSourceRoot(byPath, root, 'lib');
      if (sourceRoot == null) continue;

      candidates.add(
        ConceptBackendProjectCandidate(
          projectRoot: root,
          sourceRoot: sourceRoot,
          projectName: _projectName(entry.content, root),
          kind: ConceptBackendKind.serverpod,
        ),
      );
    }

    for (final entry in repositorySnapshot.entries) {
      if (!entry.isFile ||
          !entry.isText ||
          (entry.path != 'package.json' &&
              !entry.path.endsWith('/package.json'))) {
        continue;
      }

      final root = _manifestRoot(entry.path, 'package.json');
      if (root == app.projectRoot || !_looksLikeNodeBackend(entry.content)) {
        continue;
      }

      final sourceRoot = _existingSourceRoot(byPath, root, 'src');
      if (sourceRoot == null && root.isEmpty) continue;

      candidates.add(
        ConceptBackendProjectCandidate(
          projectRoot: root,
          sourceRoot: sourceRoot ?? root,
          projectName: _nodeProjectName(entry.content, root),
          kind: ConceptBackendKind.node,
        ),
      );
    }

    candidates.sort((a, b) {
      final kind = a.kind.index.compareTo(b.kind.index);
      if (kind != 0) return kind;
      final depth = _depth(a.projectRoot).compareTo(_depth(b.projectRoot));
      return depth != 0 ? depth : a.projectRoot.compareTo(b.projectRoot);
    });
    return List<ConceptBackendProjectCandidate>.unmodifiable(candidates);
  }

  ConceptProjectProjection project({
    required WorkspaceSnapshot repositorySnapshot,
    required String repositoryName,
    required ConceptFlutterProjectCandidate candidate,
  }) {
    final projectRoot = candidate.projectRoot;
    final backendCandidates = detectBackendProjects(
      repositorySnapshot,
      app: candidate,
    );
    final backend =
        backendCandidates.isEmpty ? null : backendCandidates.first;
    final context = ConceptProjectContext(
      repositoryName: repositoryName,
      projectName: candidate.projectName,
      projectRoot: projectRoot,
      backendRoot: backend?.projectRoot,
      backendSourceRoot: backend?.sourceRoot,
    );

    final projectedEntries = repositorySnapshot.entries
        .map((entry) => _projectEntry(entry, context))
        .whereType<WorkspaceEntry>()
        .toList(growable: false);
    final projectedBaseEntries = repositorySnapshot.baseEntries
        .map((entry) => _projectEntry(entry, context))
        .whereType<WorkspaceEntry>()
        .toList(growable: false);

    final availablePaths = projectedEntries.map((entry) => entry.path).toSet();
    if (!availablePaths.contains('pubspec.yaml') ||
        !availablePaths.contains('lib/main.dart')) {
      throw StateError(
        'Selected Flutter project is missing pubspec.yaml or lib/main.dart.',
      );
    }

    final projectedIds = projectedEntries.map((entry) => entry.id).toSet();
    final projectedFilePaths = projectedEntries
        .where((entry) => entry.isFile)
        .map((entry) => entry.path)
        .toSet();

    final openFiles = repositorySnapshot.openFiles
        .map(context.toConceptPath)
        .whereType<String>()
        .where(projectedFilePaths.contains)
        .toSet()
        .toList(growable: true);
    if (!openFiles.contains('lib/main.dart')) {
      openFiles.insert(0, 'lib/main.dart');
    }

    final mappedActive = context.toConceptPath(repositorySnapshot.activePath);
    final activePath = mappedActive != null &&
            projectedFilePaths.contains(mappedActive) &&
            _isConceptCodePath(mappedActive)
        ? mappedActive
        : 'lib/main.dart';

    final snapshot = WorkspaceSnapshot(
      entries: projectedEntries,
      baseEntries: projectedBaseEntries,
      openFiles: openFiles,
      activePath: activePath,
      nextId: repositorySnapshot.nextId,
      savedAt: repositorySnapshot.savedAt,
      expandedDirectoryIds: repositorySnapshot.expandedDirectoryIds
          .where(projectedIds.contains)
          .toList(growable: false),
      editorStates: <String, WorkspaceEditorState>{
        for (final entry in repositorySnapshot.editorStates.entries)
          if (projectedIds.contains(entry.key)) entry.key: entry.value,
      },
      formatVersion: repositorySnapshot.formatVersion,
    );

    return ConceptProjectProjection(context: context, snapshot: snapshot);
  }

  ConceptProjectProjection projectSingle({
    required WorkspaceSnapshot repositorySnapshot,
    required String repositoryName,
  }) {
    final candidates = detectFlutterProjects(repositorySnapshot);
    if (candidates.isEmpty) {
      throw const FormatException(
        'Repository does not contain a runnable Flutter project.',
      );
    }
    if (candidates.length > 1) {
      throw FormatException(
        'Repository contains multiple Flutter projects: '
        '${candidates.map((candidate) => candidate.displayPath).join(', ')}',
      );
    }
    return project(
      repositorySnapshot: repositorySnapshot,
      repositoryName: repositoryName,
      candidate: candidates.single,
    );
  }

  WorkspaceEntry? _projectEntry(
    WorkspaceEntry entry,
    ConceptProjectContext context,
  ) {
    final path = context.toConceptPath(entry.path);
    if (path == null || path.isEmpty) return null;
    return WorkspaceEntry(
      id: entry.id,
      path: path,
      type: entry.type,
      content: entry.content,
      encoding: entry.encoding,
    );
  }

  bool _looksLikeFlutterPubspec(String content) {
    try {
      final root = loadYaml(content);
      if (root is! YamlMap) return false;
      final dependencies = root['dependencies'];
      if (dependencies is YamlMap) {
        final flutterDependency = dependencies['flutter'];
        if (flutterDependency is YamlMap &&
            '${flutterDependency['sdk']}' == 'flutter') {
          return true;
        }
      }
      return root['flutter'] is YamlMap;
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeServerpodPubspec(String content) {
    try {
      final root = loadYaml(content);
      if (root is! YamlMap) return false;
      final dependencies = root['dependencies'];
      return (dependencies is YamlMap &&
              dependencies.containsKey('serverpod')) ||
          root['serverpod'] is YamlMap;
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeNodeBackend(String content) {
    try {
      final root = jsonDecode(content);
      if (root is! Map) return false;
      final packages = <String>{
        ..._dependencyNames(root['dependencies']),
        ..._dependencyNames(root['devDependencies']),
      };
      return const <String>{
        'express',
        '@nestjs/core',
        'fastify',
        'koa',
        'hono',
        '@hapi/hapi',
      }.any(packages.contains);
    } catch (_) {
      return false;
    }
  }

  Set<String> _dependencyNames(Object? value) {
    if (value is! Map) return const <String>{};
    return value.keys.whereType<String>().toSet();
  }

  String _nodeProjectName(String packageJson, String rootPath) {
    try {
      final root = jsonDecode(packageJson);
      if (root is Map) {
        final raw = root['name'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      }
    } catch (_) {
      // Fall back to the folder name below.
    }
    if (rootPath.isNotEmpty) return rootPath.split('/').last;
    return 'Node Backend';
  }

  String _manifestRoot(String path, String fileName) {
    if (path == fileName) return '';
    return path.substring(0, path.length - '/$fileName'.length);
  }

  String? _existingSourceRoot(
    Map<String, WorkspaceEntry> byPath,
    String root,
    String sourceDirectory,
  ) {
    final sourceRoot = _join(root, sourceDirectory);
    final direct = byPath[sourceRoot];
    if (direct?.isDirectory == true) return sourceRoot;
    if (byPath.keys.any((path) => path.startsWith('$sourceRoot/'))) {
      return sourceRoot;
    }
    return null;
  }

  bool _isConceptCodePath(String path) {
    return path == 'lib' ||
        path.startsWith('lib/') ||
        path == 'backend' ||
        path.startsWith('backend/');
  }

  String _projectName(String pubspec, String rootPath) {
    try {
      final root = loadYaml(pubspec);
      if (root is YamlMap) {
        final raw = root['name'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      }
    } catch (_) {
      // Fall back to the folder name below.
    }
    if (rootPath.isNotEmpty) return rootPath.split('/').last;
    return 'Flutter App';
  }

  String _join(String root, String path) =>
      root.isEmpty ? path : '$root/$path';

  int _depth(String path) => path.isEmpty ? 0 : path.split('/').length;
}
