import 'workspace_entry.dart';
import 'workspace_snapshot.dart';

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
        rawFiles is! Map) {
      throw const FormatException('Invalid Git pull response.');
    }

    final normalizedProjectPath = _validateProjectPath(projectPath as String?);
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
    if (files.length != importedFileCount ||
        !files.containsKey('pubspec.yaml') ||
        !files.containsKey('lib/main.dart') ||
        WorkspaceEntry.isRunnerBinaryContent(files['pubspec.yaml']!) ||
        WorkspaceEntry.isRunnerBinaryContent(files['lib/main.dart']!)) {
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

    return WorkspaceSnapshot(
      entries: entries,
      baseEntries: List<WorkspaceEntry>.of(entries),
      openFiles: const <String>['lib/main.dart', 'pubspec.yaml'],
      activePath: 'lib/main.dart',
      nextId: idCounter + 1,
      savedAt: (pulledAt ?? DateTime.now()).toUtc(),
      expandedDirectoryIds: rootDirectoryIds,
    );
  }

  static int _depth(String path) => '/'.allMatches(path).length;

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
      throw const FormatException('Git pull response contains an unsafe project path.');
    }
    final segments = source.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Git pull response contains an unsafe project path.');
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
