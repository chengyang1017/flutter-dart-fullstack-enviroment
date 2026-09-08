import 'dart:convert';
import 'dart:io';

import 'workspace_git_remote_checker.dart';
import 'workspace_secret_store.dart';
import 'workspace_store.dart';

class WorkspaceGitFlutterProjectCandidate {
  const WorkspaceGitFlutterProjectCandidate({
    required this.projectName,
    required this.projectPath,
  });

  final String projectName;
  final String? projectPath;

  Map<String, Object?> toJson() => <String, Object?>{
        'projectName': projectName,
        'projectPath': projectPath,
      };
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
      'WorkspaceGitProjectSelectionRequired(${candidates.map((item) => item.projectPath ?? '(repository root)').join(', ')})';
}

class WorkspaceGitPullResult {
  const WorkspaceGitPullResult({
    required this.repositoryUrl,
    required this.branch,
    required this.provider,
    required this.projectName,
    required this.projectPath,
    required this.remoteHead,
    required this.files,
    required this.importedFileCount,
    required this.ignoredFileCount,
  });

  final String repositoryUrl;
  final String branch;
  final String provider;
  final String projectName;
  final String? projectPath;
  final String remoteHead;

  /// UTF-8 text is returned as-is. Binary files use the same NUL-prefixed
  /// base64 envelope as the Workspace Runner protocol so the JSON shape stays
  /// backward compatible while preserving arbitrary bytes.
  final Map<String, String> files;
  final int importedFileCount;
  final int ignoredFileCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'repositoryUrl': repositoryUrl,
        'branch': branch,
        'provider': provider,
        'projectName': projectName,
        'projectPath': projectPath,
        'remoteHead': remoteHead,
        'files': files,
        'importedFileCount': importedFileCount,
        'ignoredFileCount': ignoredFileCount,
      };
}

class WorkspaceGitCloneResult {
  const WorkspaceGitCloneResult({
    required this.exitCode,
    required this.stderr,
    this.remoteHead,
  });

  final int exitCode;
  final String stderr;
  final String? remoteHead;
}

abstract interface class WorkspaceGitCloneExecutor {
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  });
}

class ProcessWorkspaceGitCloneExecutor implements WorkspaceGitCloneExecutor {
  const ProcessWorkspaceGitCloneExecutor({this.gitExecutable = 'git'});

  final String gitExecutable;

  @override
  Future<WorkspaceGitCloneResult> clone({
    required String repositoryUrl,
    required String branch,
    required Directory targetDirectory,
    String? username,
    String? secret,
  }) async {
    Directory? askPassDirectory;
    try {
      final environment = <String, String>{
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
      };
      if (secret != null) {
        askPassDirectory = await Directory.systemTemp.createTemp(
          'workspace-git-pull-askpass-',
        );
        final askPass = await _createAskPass(askPassDirectory);
        environment
          ..['GIT_ASKPASS'] = askPass.path
          ..['WORKSPACE_GIT_USERNAME'] = username ?? 'oauth2'
          ..['WORKSPACE_GIT_SECRET'] = secret;
      }

      final clone = await Process.run(
        gitExecutable,
        <String>[
          'clone',
          '--depth=1',
          '--single-branch',
          '--no-tags',
          '--branch',
          branch,
          '--',
          repositoryUrl,
          targetDirectory.path,
        ],
        environment: environment,
        includeParentEnvironment: false,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
      if (clone.exitCode != 0) {
        return WorkspaceGitCloneResult(
          exitCode: clone.exitCode,
          stderr: _redact('${clone.stderr}', secret),
        );
      }

      final head = await Process.run(
        gitExecutable,
        <String>['-C', targetDirectory.path, 'rev-parse', 'HEAD'],
        environment: <String, String>{...Platform.environment},
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
      if (head.exitCode != 0) {
        return WorkspaceGitCloneResult(
          exitCode: head.exitCode,
          stderr: _redact('${head.stderr}', secret),
        );
      }

      final remoteHead = '${head.stdout}'.trim();
      return WorkspaceGitCloneResult(
        exitCode: 0,
        stderr: '',
        remoteHead: remoteHead.isEmpty ? null : remoteHead,
      );
    } finally {
      if (askPassDirectory != null && await askPassDirectory.exists()) {
        await askPassDirectory.delete(recursive: true);
      }
    }
  }

  Future<File> _createAskPass(Directory directory) async {
    if (Platform.isWindows) {
      final file = File('${directory.path}${Platform.pathSeparator}askpass.cmd');
      await file.writeAsString(
        '@echo off\r\n'
        'echo %~1 | findstr /I "Username" >nul\r\n'
        'if %errorlevel%==0 (\r\n'
        '  echo %WORKSPACE_GIT_USERNAME%\r\n'
        ') else (\r\n'
        '  echo %WORKSPACE_GIT_SECRET%\r\n'
        ')\r\n',
        flush: true,
      );
      return file;
    }

    final file = File('${directory.path}${Platform.pathSeparator}askpass.sh');
    await file.writeAsString(
      '#!/bin/sh\n'
      'case "\$1" in\n'
      '  *Username*) printf "%s\\n" "\$WORKSPACE_GIT_USERNAME" ;;\n'
      '  *) printf "%s\\n" "\$WORKSPACE_GIT_SECRET" ;;\n'
      'esac\n',
      flush: true,
    );
    final chmod = await Process.run('chmod', <String>['700', file.path]);
    if (chmod.exitCode != 0) {
      throw StateError('Unable to secure temporary Git askpass helper.');
    }
    return file;
  }

  static String _redact(String source, String? secret) {
    if (secret == null || secret.isEmpty) return source;
    return source.replaceAll(secret, '[REDACTED]');
  }
}

class WorkspaceGitPullService {
  const WorkspaceGitPullService({
    required this.workspaceStore,
    required this.secretStore,
    required this.executor,
  });

  static const int maxImportedFiles = 3000;
  static const int maxSinglePortableFileBytes = 5 * 1024 * 1024;
  static const int maxImportedPortableBytes = 50 * 1024 * 1024;
  static const String binaryFilePrefix = '\u0000workspace-base64:';

  static const Set<String> _ignoredDirectoryNames = <String>{
    '.git',
    '.dart_tool',
    '.gradle',
    '.idea',
    'build',
    'coverage',
    'android',
    'ios',
    'linux',
    'macos',
    'windows',
    'web',
  };

  static const Set<String> _ignoredFileNames = <String>{
    '.metadata',
    '.packages',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.DS_Store',
  };

  final FileWorkspaceStore workspaceStore;
  final FileWorkspaceSecretStore secretStore;
  final WorkspaceGitCloneExecutor executor;

  Future<WorkspaceGitPullResult> pull({
    required String userId,
    required String workspaceId,
    String? secretName,
    String? username,
  }) async {
    final document = await workspaceStore.loadWorkspace(userId, workspaceId);
    if (document == null) {
      throw WorkspaceDocumentNotFound(workspaceId);
    }
    final project = document['project'];
    if (project is! Map) {
      throw const FormatException('Stored Workspace project is invalid.');
    }
    final remote = project['gitRemote'];
    if (remote is! Map) {
      throw const FormatException('Workspace has no Git remote binding.');
    }

    final repositoryUrl = _validateRepositoryUrl(remote['repositoryUrl']);
    final branch = _validateBranch(remote['branch']);
    final provider = _readProvider(remote['provider']);
    final projectPath = _validateProjectPath(remote['projectPath']);

    String? secret;
    if (secretName != null && secretName.trim().isNotEmpty) {
      secret = await secretStore.resolveForTrustedExecution(
        userId: userId,
        workspaceId: workspaceId,
        name: secretName.trim(),
        context: 'git',
      );
    }

    final temp = await Directory.systemTemp.createTemp('workspace-git-pull-');
    try {
      final checkout = Directory(
        '${temp.path}${Platform.pathSeparator}checkout',
      );
      final clone = await executor.clone(
        repositoryUrl: repositoryUrl,
        branch: branch,
        targetDirectory: checkout,
        username: secret == null
            ? null
            : (username?.trim().isNotEmpty == true
                ? username!.trim()
                : _defaultUsername(provider)),
        secret: secret,
      );
      if (clone.exitCode != 0) {
        final detail = clone.stderr.trim();
        throw WorkspaceGitRemoteException(
          detail.isEmpty ? 'Git pull failed.' : detail,
        );
      }
      final remoteHead = clone.remoteHead?.trim();
      if (remoteHead == null || remoteHead.isEmpty) {
        throw const WorkspaceGitRemoteException(
          'Git clone completed without a resolvable HEAD commit.',
        );
      }

      final imported = await _readFlutterProject(
        checkout,
        projectPath: projectPath,
      );
      return WorkspaceGitPullResult(
        repositoryUrl: repositoryUrl,
        branch: branch,
        provider: provider,
        projectName: imported.projectName,
        projectPath: imported.projectPath,
        remoteHead: remoteHead,
        files: imported.files,
        importedFileCount: imported.files.length,
        ignoredFileCount: imported.ignoredFileCount,
      );
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<_PortableFlutterProject> _readFlutterProject(
    Directory checkout, {
    String? projectPath,
  }) async {
    if (!await checkout.exists()) {
      throw const WorkspaceGitRemoteException(
        'Git clone did not produce a checkout directory.',
      );
    }

    final repositoryFiles = <String, File>{};
    await for (final entity in checkout.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = _relativePath(checkout, entity);
      if (relative.isEmpty || _shouldIgnore(relative)) continue;
      repositoryFiles[relative] = entity;
    }

    final candidates = <String>[];
    final pubspecs = <String, String>{};
    for (final entry in repositoryFiles.entries) {
      final path = entry.key;
      if (path != 'pubspec.yaml' && !path.endsWith('/pubspec.yaml')) continue;
      if (await entry.value.length() > maxSinglePortableFileBytes) continue;
      final pubspec = await _tryReadText(entry.value);
      if (pubspec == null || !_looksLikeFlutterPubspec(pubspec)) continue;
      final root = path == 'pubspec.yaml'
          ? ''
          : path.substring(0, path.length - '/pubspec.yaml'.length);
      final mainPath = root.isEmpty ? 'lib/main.dart' : '$root/lib/main.dart';
      if (!repositoryFiles.containsKey(mainPath)) continue;
      final mainText = await _tryReadText(repositoryFiles[mainPath]!);
      if (mainText == null) continue;
      candidates.add(root);
      pubspecs[root] = pubspec;
    }

    late final String root;
    if (projectPath != null) {
      if (!candidates.contains(projectPath)) {
        throw FormatException(
          'Bound Git Flutter project path is not runnable: $projectPath. '
          'Expected pubspec.yaml and text lib/main.dart at that path.',
        );
      }
      root = projectPath;
    } else {
      if (candidates.isEmpty) {
        throw const FormatException(
          'Git repository must contain one runnable Flutter project with '
          'pubspec.yaml and lib/main.dart.',
        );
      }
      if (candidates.length > 1) {
        candidates.sort();
        throw WorkspaceGitProjectSelectionRequired(
          candidates.map(
            (candidateRoot) => WorkspaceGitFlutterProjectCandidate(
              projectName: _projectName(
                pubspecs[candidateRoot]!,
                candidateRoot,
              ),
              projectPath: candidateRoot.isEmpty ? null : candidateRoot,
            ),
          ),
        );
      }
      root = candidates.single;
    }

    final files = <String, String>{};
    var ignoredFileCount = 0;
    var importedBytes = 0;

    for (final entry in repositoryFiles.entries) {
      final relative = _relativeToRoot(entry.key, root);
      if (relative == null || relative.isEmpty) continue;
      if (_shouldIgnore(relative)) {
        ignoredFileCount += 1;
        continue;
      }
      if (files.length >= maxImportedFiles) {
        throw const FormatException(
          'Git project contains more than 3000 portable files.',
        );
      }

      final length = await entry.value.length();
      if (length > maxSinglePortableFileBytes) {
        throw FormatException(
          'File is larger than the 5 MB portable-file limit: $relative',
        );
      }
      importedBytes += length;
      if (importedBytes > maxImportedPortableBytes) {
        throw const FormatException(
          'Git project contains more than 50 MB of portable files.',
        );
      }
      files[relative] = await _readPortablePayload(entry.value);
    }

    if (!files.containsKey('pubspec.yaml') ||
        !files.containsKey('lib/main.dart') ||
        files['pubspec.yaml']!.startsWith(binaryFilePrefix) ||
        files['lib/main.dart']!.startsWith(binaryFilePrefix)) {
      throw const FormatException(
        'Pulled Flutter project must preserve text pubspec.yaml and lib/main.dart.',
      );
    }

    return _PortableFlutterProject(
      projectName: _projectName(pubspecs[root]!, root),
      projectPath: root.isEmpty ? null : root,
      files: Map<String, String>.unmodifiable(files),
      ignoredFileCount: ignoredFileCount,
    );
  }

  Future<String> _readPortablePayload(File file) async {
    final bytes = await file.readAsBytes();
    if (!bytes.any((value) => value == 0)) {
      try {
        return utf8.decode(bytes, allowMalformed: false);
      } on FormatException {
        // Fall through to binary encoding.
      }
    }
    return '$binaryFilePrefix${base64Encode(bytes)}';
  }

  Future<String?> _tryReadText(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.any((value) => value == 0)) return null;
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  bool _looksLikeFlutterPubspec(String content) {
    return RegExp(r'^\s*flutter\s*:\s*$', multiLine: true).hasMatch(content) ||
        RegExp(r'^\s*sdk\s*:\s*flutter\s*$', multiLine: true).hasMatch(content);
  }

  String _projectName(String pubspec, String root) {
    final match = RegExp(
      r'^\s*name\s*:\s*([A-Za-z0-9_\-]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    final fromPubspec = match?.group(1)?.trim();
    if (fromPubspec != null && fromPubspec.isNotEmpty) return fromPubspec;
    if (root.isNotEmpty) return root.split('/').last;
    return 'Pulled Flutter Project';
  }

  bool _shouldIgnore(String path) {
    final segments = path.split('/');
    if (segments.any(_ignoredDirectoryNames.contains)) return true;
    if (_ignoredFileNames.contains(segments.last)) return true;
    return segments.any((segment) => segment == '__MACOSX');
  }

  String _relativePath(Directory root, File file) {
    final rootPath = root.absolute.path;
    final filePath = file.absolute.path;
    if (!filePath.startsWith(rootPath)) {
      throw const FormatException('Git checkout contains an unsafe file path.');
    }
    var relative = filePath.substring(rootPath.length);
    while (relative.startsWith(Platform.pathSeparator)) {
      relative = relative.substring(1);
    }
    return relative.replaceAll(Platform.pathSeparator, '/');
  }

  String? _relativeToRoot(String path, String root) {
    if (root.isEmpty) return path;
    final prefix = '$root/';
    if (!path.startsWith(prefix)) return null;
    return path.substring(prefix.length);
  }

  String _validateRepositoryUrl(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Git repository URL is required.');
    }
    final source = value.trim();
    final scp = RegExp(
      r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s]+$',
    ).hasMatch(source);
    if (scp) return source;

    final uri = Uri.tryParse(source);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('Git repository URL must include a host.');
    }
    if (!const <String>{'https', 'http', 'ssh'}.contains(uri.scheme)) {
      throw const FormatException('Unsupported Git repository URL scheme.');
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Git credentials must not be embedded in repository URL.',
      );
    }
    return source;
  }

  String _validateBranch(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Git branch is required.');
    }
    final source = value.trim();
    if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(source) ||
        source.contains('..') ||
        source.contains('//') ||
        source.contains('@{') ||
        source.startsWith('/') ||
        source.endsWith('/')) {
      throw const FormatException('Invalid Git branch name.');
    }
    return source;
  }

  String? _validateProjectPath(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invalid Git Flutter project path.');
    }
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
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Invalid Git Flutter project path.');
    }
    return source;
  }

  String _readProvider(Object? value) {
    if (value is! String || value.isEmpty) return 'generic';
    return switch (value) {
      'github' || 'gitlab' || 'bitbucket' || 'generic' => value,
      _ => 'generic',
    };
  }

  String _defaultUsername(String provider) => switch (provider) {
        'github' => 'x-access-token',
        'gitlab' => 'oauth2',
        'bitbucket' => 'x-token-auth',
        _ => 'oauth2',
      };
}

class _PortableFlutterProject {
  const _PortableFlutterProject({
    required this.projectName,
    required this.projectPath,
    required this.files,
    required this.ignoredFileCount,
  });

  final String projectName;
  final String? projectPath;
  final Map<String, String> files;
  final int ignoredFileCount;
}
