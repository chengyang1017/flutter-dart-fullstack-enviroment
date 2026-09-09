import 'dart:convert';
import 'dart:io';

import 'workspace_git_pull_service.dart';
import 'workspace_git_remote_checker.dart';
import 'workspace_secret_store.dart';
import 'workspace_store.dart';

class WorkspaceGitHeadMismatch implements Exception {
  const WorkspaceGitHeadMismatch({
    required this.workspaceId,
    required this.expectedRemoteHead,
    required this.actualRemoteHead,
  });

  final String workspaceId;
  final String expectedRemoteHead;
  final String actualRemoteHead;

  @override
  String toString() => 'WorkspaceGitHeadMismatch(workspaceId: $workspaceId, '
      'expected: $expectedRemoteHead, actual: $actualRemoteHead)';
}

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

  Map<String, Object?> toJson() => <String, Object?>{
        'repositoryUrl': repositoryUrl,
        'branch': branch,
        'provider': provider,
        'previousRemoteHead': previousRemoteHead,
        'newRemoteHead': newRemoteHead,
        'committed': committed,
      };
}

class WorkspaceGitPushCommandResult {
  const WorkspaceGitPushCommandResult({
    required this.exitCode,
    required this.stderr,
    required this.committed,
    this.newHead,
  });

  final int exitCode;
  final String stderr;
  final bool committed;
  final String? newHead;
}

abstract interface class WorkspaceGitPushCommandExecutor {
  Future<WorkspaceGitPushCommandResult> commitAndPush({
    required Directory checkoutDirectory,
    required String branch,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? username,
    String? secret,
  });
}

class ProcessWorkspaceGitPushCommandExecutor
    implements WorkspaceGitPushCommandExecutor {
  const ProcessWorkspaceGitPushCommandExecutor({this.gitExecutable = 'git'});

  final String gitExecutable;

  @override
  Future<WorkspaceGitPushCommandResult> commitAndPush({
    required Directory checkoutDirectory,
    required String branch,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? username,
    String? secret,
  }) async {
    final add = await _run(
      checkoutDirectory,
      const <String>['add', '-A'],
      secret: secret,
    );
    if (add.exitCode != 0) {
      return _failure(add, committed: false);
    }

    final diff = await _run(
      checkoutDirectory,
      const <String>['diff', '--cached', '--quiet'],
      secret: secret,
    );
    if (diff.exitCode == 0) {
      final head = await _readHead(checkoutDirectory, secret: secret);
      return WorkspaceGitPushCommandResult(
        exitCode: 0,
        stderr: '',
        committed: false,
        newHead: head,
      );
    }
    if (diff.exitCode != 1) {
      return _failure(diff, committed: false);
    }

    final commit = await _run(
      checkoutDirectory,
      <String>[
        '-c',
        'user.name=$authorName',
        '-c',
        'user.email=$authorEmail',
        'commit',
        '-m',
        commitMessage,
      ],
      secret: secret,
    );
    if (commit.exitCode != 0) {
      return _failure(commit, committed: false);
    }

    final push = await _run(
      checkoutDirectory,
      <String>['push', 'origin', 'HEAD:refs/heads/$branch'],
      username: username,
      secret: secret,
      authenticated: true,
    );
    if (push.exitCode != 0) {
      return _failure(push, committed: true);
    }

    final head = await _readHead(checkoutDirectory, secret: secret);
    return WorkspaceGitPushCommandResult(
      exitCode: 0,
      stderr: '',
      committed: true,
      newHead: head,
    );
  }

  Future<String?> _readHead(
    Directory checkoutDirectory, {
    String? secret,
  }) async {
    final result = await _run(
      checkoutDirectory,
      const <String>['rev-parse', 'HEAD'],
      secret: secret,
    );
    if (result.exitCode != 0) return null;
    final value = result.stdout.trim();
    return value.isEmpty ? null : value;
  }

  Future<_ProcessResult> _run(
    Directory checkoutDirectory,
    List<String> arguments, {
    String? username,
    String? secret,
    bool authenticated = false,
  }) async {
    Directory? askPassDirectory;
    try {
      final environment = <String, String>{
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
      };
      if (authenticated && secret != null) {
        askPassDirectory = await Directory.systemTemp.createTemp(
          'workspace-git-push-askpass-',
        );
        final askPass = await _createAskPass(askPassDirectory);
        environment
          ..['GIT_ASKPASS'] = askPass.path
          ..['WORKSPACE_GIT_USERNAME'] = username ?? 'oauth2'
          ..['WORKSPACE_GIT_SECRET'] = secret;
      }

      final result = await Process.run(
        gitExecutable,
        <String>['-C', checkoutDirectory.path, ...arguments],
        environment: environment,
        includeParentEnvironment: false,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
      return _ProcessResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: _redact('${result.stderr}', secret),
      );
    } finally {
      if (askPassDirectory != null && await askPassDirectory.exists()) {
        await askPassDirectory.delete(recursive: true);
      }
    }
  }

  WorkspaceGitPushCommandResult _failure(
    _ProcessResult result, {
    required bool committed,
  }) {
    return WorkspaceGitPushCommandResult(
      exitCode: result.exitCode,
      stderr: result.stderr,
      committed: committed,
    );
  }

  Future<File> _createAskPass(Directory directory) async {
    if (Platform.isWindows) {
      final file =
          File('${directory.path}${Platform.pathSeparator}askpass.cmd');
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

class WorkspaceGitPushService {
  const WorkspaceGitPushService({
    required this.workspaceStore,
    required this.secretStore,
    required this.cloneExecutor,
    required this.pushExecutor,
  });

  static const String _binaryEnvelope = '\u0000flutterpractice-base64:';

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
  final WorkspaceGitCloneExecutor cloneExecutor;
  final WorkspaceGitPushCommandExecutor pushExecutor;

  Future<WorkspaceGitPushResult> push({
    required String userId,
    required String workspaceId,
    required String expectedWorkspaceRevision,
    required String expectedRemoteHead,
    required String commitMessage,
    required String authorName,
    required String authorEmail,
    String? secretName,
    String? username,
  }) async {
    final document = await workspaceStore.loadWorkspace(
      userId,
      workspaceId,
      includeBaseEntries: false,
    );
    if (document == null) {
      throw WorkspaceDocumentNotFound(workspaceId);
    }
    final revision = document['revision'];
    if (revision is! String || revision.isEmpty) {
      throw StateError('Stored Workspace revision is invalid: $workspaceId');
    }
    if (revision != expectedWorkspaceRevision) {
      throw WorkspaceRevisionMismatch(
        workspaceId: workspaceId,
        expectedRevision: expectedWorkspaceRevision,
        actualRevision: revision,
      );
    }

    final project = document['project'];
    final snapshot = document['snapshot'];
    if (project is! Map || snapshot is! Map) {
      throw const FormatException('Stored Workspace document is invalid.');
    }
    final remote = project['gitRemote'];
    if (remote is! Map) {
      throw const FormatException('Workspace has no Git remote binding.');
    }

    final repositoryUrl = _validateRepositoryUrl(remote['repositoryUrl']);
    final branch = _validateBranch(remote['branch']);
    final projectPath = _validateProjectPath(remote['projectPath']);
    final provider = _readProvider(remote['provider']);
    final expectedHead = _validateHead(expectedRemoteHead);
    final message = _validateCommitMessage(commitMessage);
    final cleanAuthorName = _validateAuthorName(authorName);
    final cleanAuthorEmail = _validateAuthorEmail(authorEmail);
    final files = _readSnapshotFiles(Map<String, dynamic>.from(snapshot));

    String? secret;
    if (secretName != null && secretName.trim().isNotEmpty) {
      secret = await secretStore.resolveForTrustedExecution(
        userId: userId,
        workspaceId: workspaceId,
        name: secretName.trim(),
        context: 'git',
      );
    }
    final gitUsername = secret == null
        ? null
        : (username?.trim().isNotEmpty == true
            ? username!.trim()
            : _defaultUsername(provider));

    final temp = await Directory.systemTemp.createTemp('workspace-git-push-');
    try {
      final checkout =
          Directory('${temp.path}${Platform.pathSeparator}checkout');
      final clone = await cloneExecutor.clone(
        repositoryUrl: repositoryUrl,
        branch: branch,
        targetDirectory: checkout,
        username: gitUsername,
        secret: secret,
      );
      if (clone.exitCode != 0) {
        final detail = clone.stderr.trim();
        throw WorkspaceGitRemoteException(
          detail.isEmpty ? 'Git push preparation failed.' : detail,
        );
      }
      final actualHead = clone.remoteHead?.trim();
      if (actualHead == null || actualHead.isEmpty) {
        throw const WorkspaceGitRemoteException(
          'Git clone completed without a resolvable HEAD commit.',
        );
      }
      final normalizedActualHead = _validateHead(actualHead);
      if (normalizedActualHead != expectedHead) {
        throw WorkspaceGitHeadMismatch(
          workspaceId: workspaceId,
          expectedRemoteHead: expectedHead,
          actualRemoteHead: normalizedActualHead,
        );
      }

      final flutterRoot = await _findFlutterRoot(
        checkout,
        projectPath: projectPath,
      );
      await _applyWorkspaceFiles(
        checkout: checkout,
        flutterRoot: flutterRoot,
        files: files,
      );

      final pushed = await pushExecutor.commitAndPush(
        checkoutDirectory: checkout,
        branch: branch,
        commitMessage: message,
        authorName: cleanAuthorName,
        authorEmail: cleanAuthorEmail,
        username: gitUsername,
        secret: secret,
      );
      if (pushed.exitCode != 0) {
        final detail = pushed.stderr.trim();
        throw WorkspaceGitRemoteException(
          detail.isEmpty ? 'Git push failed.' : detail,
        );
      }
      final newHead = pushed.newHead?.trim();
      if (newHead == null || newHead.isEmpty) {
        throw const WorkspaceGitRemoteException(
          'Git push completed without a resolvable HEAD commit.',
        );
      }

      return WorkspaceGitPushResult(
        repositoryUrl: repositoryUrl,
        branch: branch,
        provider: provider,
        previousRemoteHead: expectedHead,
        newRemoteHead: _validateHead(newHead),
        committed: pushed.committed,
      );
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Map<String, String> _readSnapshotFiles(Map<String, dynamic> snapshot) {
    final entries = snapshot['entries'];
    if (entries is! Iterable) {
      throw const FormatException('Workspace snapshot entries are missing.');
    }

    final files = <String, String>{};
    for (final item in entries) {
      if (item is! Map) {
        throw const FormatException('Workspace snapshot entry is invalid.');
      }
      if (item['type'] != 'file') continue;
      final path = item['path'];
      final content = item['content'];
      final encoding = item['encoding'];
      if (path is! String ||
          content is! String ||
          (encoding != null && encoding is! String)) {
        throw const FormatException('Workspace snapshot file is invalid.');
      }
      _validatePortablePath(path);
      if (_shouldIgnore(path)) {
        throw FormatException(
          'Generated/platform path cannot be pushed from Workspace: $path',
        );
      }
      if (files.containsKey(path)) {
        throw FormatException(
            'Workspace snapshot contains duplicate path: $path');
      }

      switch (encoding) {
        case null:
        case 'utf8':
          files[path] = content;
          break;
        case 'base64':
          try {
            base64.decode(content);
          } on FormatException {
            throw FormatException(
                'Workspace binary file has invalid base64: $path');
          }
          files[path] = '$_binaryEnvelope$content';
          break;
        default:
          throw FormatException(
              'Unsupported Workspace file encoding: $encoding');
      }
    }

    final pubspec = files['pubspec.yaml'];
    final main = files['lib/main.dart'];
    if (pubspec == null ||
        main == null ||
        _isBinaryPayload(pubspec) ||
        _isBinaryPayload(main)) {
      throw const FormatException(
        'Workspace Git push requires text pubspec.yaml and lib/main.dart.',
      );
    }
    return files;
  }

  Future<String> _findFlutterRoot(
    Directory checkout, {
    String? projectPath,
  }) async {
    if (projectPath != null) {
      final root = Directory(
        '${checkout.path}${Platform.pathSeparator}${_platformPath(projectPath)}',
      );
      if (!await root.exists()) {
        throw FormatException(
          'Bound Git Flutter project path does not exist: $projectPath',
        );
      }
      final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
      final main = File(
        '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
      );
      if (!await pubspec.exists() || !await main.exists()) {
        throw FormatException(
          'Bound Git Flutter project path is not runnable: $projectPath.',
        );
      }
      final pubspecText = await _tryReadText(pubspec);
      final mainText = await _tryReadText(main);
      if (pubspecText == null ||
          mainText == null ||
          !_looksLikeFlutterPubspec(pubspecText)) {
        throw FormatException(
          'Bound Git Flutter project path is not runnable: $projectPath.',
        );
      }
      return projectPath;
    }

    final candidates = <String>[];
    await for (final entity
        in checkout.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        final relative = _relativePath(checkout, entity.path);
        if (!_shouldIgnore(relative)) {
          throw FormatException(
            'Git push does not support symbolic links in portable source: $relative',
          );
        }
        continue;
      }
      if (entity is! File) continue;
      final relative = _relativePath(checkout, entity.path);
      if (_shouldIgnore(relative)) continue;
      if (relative != 'pubspec.yaml' && !relative.endsWith('/pubspec.yaml')) {
        continue;
      }
      final content = await _tryReadText(entity);
      if (content == null || !_looksLikeFlutterPubspec(content)) continue;
      final root = relative == 'pubspec.yaml'
          ? ''
          : relative.substring(0, relative.length - '/pubspec.yaml'.length);
      final main = File(
        '${checkout.path}${Platform.pathSeparator}'
        '${_platformPath(root.isEmpty ? 'lib/main.dart' : '$root/lib/main.dart')}',
      );
      if (await main.exists()) candidates.add(root);
    }

    if (candidates.isEmpty) {
      throw const FormatException(
        'Git repository must contain one runnable Flutter project.',
      );
    }
    if (candidates.length > 1) {
      candidates.sort();
      throw FormatException(
        'Git repository contains multiple runnable Flutter projects: '
        '${candidates.join(', ')}. Bind a Flutter project path first.',
      );
    }
    return candidates.single;
  }

  Future<void> _applyWorkspaceFiles({
    required Directory checkout,
    required String flutterRoot,
    required Map<String, String> files,
  }) async {
    final root = Directory(
      flutterRoot.isEmpty
          ? checkout.path
          : '${checkout.path}${Platform.pathSeparator}${_platformPath(flutterRoot)}',
    );
    final existingPortableFiles = <String, File>{};

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relative = _relativePath(root, entity.path);
      if (relative.isEmpty || _shouldIgnore(relative)) continue;
      if (entity is Link) {
        throw FormatException(
          'Git push does not support symbolic links in portable source: $relative',
        );
      }
      if (entity is! File) continue;
      existingPortableFiles[relative] = entity;
    }

    for (final entry in existingPortableFiles.entries) {
      if (!files.containsKey(entry.key)) {
        await entry.value.delete();
      }
    }

    for (final entry in files.entries) {
      final file = File(
        '${root.path}${Platform.pathSeparator}${_platformPath(entry.key)}',
      );
      await file.parent.create(recursive: true);
      if (_isBinaryPayload(entry.value)) {
        await file.writeAsBytes(
          _decodeBinaryPayload(entry.value),
          flush: true,
        );
      } else {
        await file.writeAsString(entry.value, flush: true);
      }
    }
  }

  bool _isBinaryPayload(String value) => value.startsWith(_binaryEnvelope);

  List<int> _decodeBinaryPayload(String value) {
    if (!_isBinaryPayload(value)) {
      throw const FormatException('Workspace binary envelope is missing.');
    }
    final encoded = value.substring(_binaryEnvelope.length);
    try {
      return base64.decode(encoded);
    } on FormatException {
      throw const FormatException('Workspace binary envelope is invalid.');
    }
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

  bool _shouldIgnore(String path) {
    final segments = path.split('/');
    if (segments.any(_ignoredDirectoryNames.contains)) return true;
    if (_ignoredFileNames.contains(segments.last)) return true;
    return segments.any((segment) => segment == '__MACOSX');
  }

  void _validatePortablePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      throw FormatException('Unsafe Workspace Git path: $path');
    }
    final segments = path.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Unsafe Workspace Git path: $path');
    }
  }

  String _relativePath(Directory root, String entityPath) {
    final rootPath = root.absolute.path;
    final absolute = File(entityPath).absolute.path;
    if (!absolute.startsWith(rootPath)) {
      throw const FormatException('Git checkout contains an unsafe file path.');
    }
    var relative = absolute.substring(rootPath.length);
    while (relative.startsWith(Platform.pathSeparator)) {
      relative = relative.substring(1);
    }
    return relative.replaceAll(Platform.pathSeparator, '/');
  }

  String _platformPath(String path) =>
      path.replaceAll('/', Platform.pathSeparator);

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

  String _validateHead(String value) {
    final source = value.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{7,128}$').hasMatch(source)) {
      throw const FormatException('Invalid Git commit id.');
    }
    return source;
  }

  String _validateCommitMessage(String value) {
    final source = value.trim();
    if (source.isEmpty || source.length > 200 || source.contains('\u0000')) {
      throw const FormatException(
        'Git commit message must contain 1-200 safe characters.',
      );
    }
    return source;
  }

  String _validateAuthorName(String value) {
    final source = value.trim();
    if (source.isEmpty || source.length > 100 || source.contains('\n')) {
      throw const FormatException('Invalid Git author name.');
    }
    return source;
  }

  String _validateAuthorEmail(String value) {
    final source = value.trim();
    if (source.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(source)) {
      throw const FormatException('Invalid Git author email.');
    }
    return source;
  }

  String _defaultUsername(String provider) => switch (provider) {
        'github' => 'x-access-token',
        'gitlab' => 'oauth2',
        'bitbucket' => 'x-token-auth',
        _ => 'oauth2',
      };
}

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
