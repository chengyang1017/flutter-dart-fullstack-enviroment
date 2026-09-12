import 'workspace_entry.dart';
import 'workspace_snapshot.dart';

class WorkspaceGitFlutterProjectCandidate {
  const WorkspaceGitFlutterProjectCandidate({
    required this.projectName,
    this.projectPath,
  });

  final String projectName;
  final String? projectPath;

  String get displayPath => projectPath ?? '(repository root)';

  factory WorkspaceGitFlutterProjectCandidate.fromJson(
    Map<dynamic, dynamic> json,
  ) {
    final projectName = json['projectName'];
    final projectPath = json['projectPath'];
    if (projectName is! String ||
        projectName.trim().isEmpty ||
        (projectPath != null && projectPath is! String)) {
      throw const FormatException('Invalid Git Flutter project candidate.');
    }

    return WorkspaceGitFlutterProjectCandidate(
      projectName: projectName.trim(),
      projectPath: WorkspaceGitPullResult.validateProjectPath(
        projectPath as String?,
      ),
    );
  }
}

class WorkspaceGitProjectSelectionRequired implements Exception {
  WorkspaceGitProjectSelectionRequired(
    Iterable<WorkspaceGitFlutterProjectCandidate> candidates,
  ) : candidates = List<WorkspaceGitFlutterProjectCandidate>.unmodifiable(
          candidates,
        ) {
    if (this.candidates.length < 2) {
      throw ArgumentError(
        'Git project selection requires at least two candidates.',
      );
    }
  }

  final List<WorkspaceGitFlutterProjectCandidate> candidates;

  @override
  String toString() =>
      'WorkspaceGitProjectSelectionRequired(${candidates.map((item) => item.displayPath).join(', ')})';
}

class WorkspaceGitPullResult {
  WorkspaceGitPullResult({
    required this.repositoryUrl,
    required this.branch,
    required this.provider,
    required this.projectName,
    this.projectPath,
    required this.remoteHead,
    required Map<String, String> files,
    required this.importedFileCount,
    required this.ignoredFileCount,
    this.repositoryRelativePaths = false,
  }) : files = Map<String, String>.unmodifiable(files);

  final String repositoryUrl;
  final String branch;
  final String provider;
  final String projectName;
  final String? projectPath;
  final String remoteHead;

  /// Text files are raw UTF-8 strings. Binary files use the same guarded
  /// NUL-prefixed base64 envelope as Workspace -> Runner transport.
  final Map<String, String> files;
  final int importedFileCount;
  final int ignoredFileCount;

  /// True when [files] keep repository-relative paths instead of being
  /// re-rooted to the selected Flutter application.
  final bool repositoryRelativePaths;

  factory WorkspaceGitPullResult.fromJson(Map<dynamic, dynamic> json) {
    final repositoryUrl = json['repositoryUrl'];
    final branch = json['branch'];
    final provider = json['provider'];
    final projectName = json['projectName'];
    final projectPath = json['projectPath'];
    final remoteHead = json['remoteHead'];
    final importedFileCount = json['importedFileCount'];
    final ignoredFileCount = json['ignoredFileCount'];
    final rawFiles = json['files'];
    final repositoryRelativePaths = json['repositoryRelativePaths'] ?? false;

    if (repositoryUrl is! String ||
        branch is! String ||
        provider is! String ||
        projectName is! String ||
        projectName.isEmpty ||
        (projectPath != null && projectPath is! String) ||
        remoteHead is! String ||
        remoteHead.isEmpty ||
        importedFileCount is! int ||
        importedFileCount < 0 ||
        ignoredFileCount is! int ||
        ignoredFileCount < 0 ||
        repositoryRelativePaths is! bool ||
        rawFiles is! Map) {
      throw const FormatException('Invalid Git pull response.');
    }

    final normalizedProjectPath = validateProjectPath(projectPath as String?);
    final files = <String, String>{};
    for (final entry in rawFiles.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
          'Git pull files must contain encoded Workspace file payloads.',
        );
      }
      final path = entry.key as String;
      final payload = entry.value as String;
      _validatePortablePath(path);
      if (WorkspaceEntry.isRunnerBinaryContent(payload)) {
        try {
          WorkspaceEntry.decodeRunnerContent(payload);
        } on FormatException {
          throw FormatException('Git pull contains invalid binary file: $path');
        }
      }
      files[path] = payload;
    }
    final primaryPrefix = repositoryRelativePaths &&
            normalizedProjectPath != null &&
            normalizedProjectPath.isNotEmpty
        ? '$normalizedProjectPath/'
        : '';
    final pubspecPath = '${primaryPrefix}pubspec.yaml';
    final mainPath = '${primaryPrefix}lib/main.dart';
    if (files.length != importedFileCount ||
        !files.containsKey(pubspecPath) ||
        !files.containsKey(mainPath) ||
        WorkspaceEntry.isRunnerBinaryContent(files[pubspecPath]!) ||
        WorkspaceEntry.isRunnerBinaryContent(files[mainPath]!)) {
      throw const FormatException(
        'Git pull response contains an invalid Flutter source set.',
      );
    }

    return WorkspaceGitPullResult(
      repositoryUrl: repositoryUrl,
      branch: branch,
      provider: provider,
      projectName: projectName,
      projectPath: normalizedProjectPath,
      remoteHead: remoteHead,
      files: files,
      importedFileCount: importedFileCount,
      ignoredFileCount: ignoredFileCount,
      repositoryRelativePaths: repositoryRelativePaths,
    );
  }

  WorkspaceSnapshot toSnapshot({DateTime? pulledAt}) {
    final directories = <String>{};
    for (final path in files.keys) {
      final parts = path.split('/');
      for (var index = 1; index < parts.length; index++) {
        directories.add(parts.take(index).join('/'));
      }
    }

    final directoryPaths = directories.toList()
      ..sort((a, b) {
        final depth = _depth(a).compareTo(_depth(b));
        return depth != 0 ? depth : a.compareTo(b);
      });
    final filePaths = files.keys.toList()..sort();
    final entries = <WorkspaceEntry>[];
    final rootDirectoryIds = <String>[];
    var idCounter = 0;

    for (final path in directoryPaths) {
      final id = 'git-pull-${++idCounter}';
      entries.add(
        WorkspaceEntry(
          id: id,
          path: path,
          type: WorkspaceEntryType.directory,
        ),
      );
      if (!path.contains('/')) rootDirectoryIds.add(id);
    }
    for (final path in filePaths) {
      final payload = files[path]!;
      if (WorkspaceEntry.isRunnerBinaryContent(payload)) {
        entries.add(
          WorkspaceEntry.binary(
            id: 'git-pull-${++idCounter}',
            path: path,
            bytes: WorkspaceEntry.decodeRunnerContent(payload),
          ),
        );
      } else {
        entries.add(
          WorkspaceEntry(
            id: 'git-pull-${++idCounter}',
            path: path,
            type: WorkspaceEntryType.file,
            content: payload,
          ),
        );
      }
    }

    final primaryPrefix = repositoryRelativePaths &&
            projectPath != null &&
            projectPath!.isNotEmpty
        ? '$projectPath/'
        : '';

    return WorkspaceSnapshot(
      entries: entries,
      baseEntries: List<WorkspaceEntry>.of(entries),
      openFiles: <String>[
        '${primaryPrefix}lib/main.dart',
        '${primaryPrefix}pubspec.yaml',
      ],
      activePath: '${primaryPrefix}lib/main.dart',
      nextId: idCounter + 1,
      savedAt: (pulledAt ?? DateTime.now()).toUtc(),
      expandedDirectoryIds: rootDirectoryIds,
    );
  }

  static int _depth(String path) => '/'.allMatches(path).length;

  static String? validateProjectPath(String? value) {
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
      throw const FormatException(
        'Git pull response contains an unsafe project path.',
      );
    }
    final segments = source.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException(
        'Git pull response contains an unsafe project path.',
      );
    }
    return source;
  }

  static void _validatePortablePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      throw const FormatException('Git pull response contains an unsafe path.');
    }
    final segments = path.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Git pull response contains an unsafe path.');
    }
  }
}
