import 'dart:convert';
import 'dart:io';

import 'workspace_secret_store.dart';
import 'workspace_store.dart';

class WorkspaceGitRemoteCheckResult {
  const WorkspaceGitRemoteCheckResult({
    required this.repositoryUrl,
    required this.branch,
    required this.provider,
    required this.branchFound,
    this.remoteHead,
    this.repositoryId,
    this.repositoryFullName,
    this.canonicalUrl,
  });

  final String repositoryUrl;
  final String branch;
  final String provider;
  final bool branchFound;
  final String? remoteHead;
  final int? repositoryId;
  final String? repositoryFullName;
  final String? canonicalUrl;

  Map<String, Object?> toJson() => <String, Object?>{
        'repositoryUrl': repositoryUrl,
        'branch': branch,
        'provider': provider,
        'reachable': true,
        'branchFound': branchFound,
        'remoteHead': remoteHead,
        if (repositoryId != null) 'repositoryId': repositoryId,
        if (repositoryFullName != null)
          'repositoryFullName': repositoryFullName,
        if (canonicalUrl != null) 'canonicalUrl': canonicalUrl,
      };
}

class WorkspaceGitRemoteException implements Exception {
  const WorkspaceGitRemoteException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WorkspaceGitCommandResult {
  const WorkspaceGitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class WorkspaceGitCommandExecutor {
  Future<WorkspaceGitCommandResult> lsRemote({
    required String repositoryUrl,
    required String branch,
    String? username,
    String? secret,
  });
}

class ProcessWorkspaceGitCommandExecutor
    implements WorkspaceGitCommandExecutor {
  const ProcessWorkspaceGitCommandExecutor({this.gitExecutable = 'git'});

  final String gitExecutable;

  @override
  Future<WorkspaceGitCommandResult> lsRemote({
    required String repositoryUrl,
    required String branch,
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
          'workspace-git-askpass-',
        );
        final askPass = await _createAskPass(askPassDirectory);
        environment
          ..['GIT_ASKPASS'] = askPass.path
          ..['WORKSPACE_GIT_USERNAME'] = username ?? 'oauth2'
          ..['WORKSPACE_GIT_SECRET'] = secret;
      }

      final process = await Process.run(
        gitExecutable,
        <String>[
          'ls-remote',
          '--heads',
          repositoryUrl,
          'refs/heads/$branch',
        ],
        environment: environment,
        includeParentEnvironment: false,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
      return WorkspaceGitCommandResult(
        exitCode: process.exitCode,
        stdout: '${process.stdout}',
        stderr: _redact('${process.stderr}', secret),
      );
    } finally {
      if (askPassDirectory != null && await askPassDirectory.exists()) {
        await askPassDirectory.delete(recursive: true);
      }
    }
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

class WorkspaceGitRemoteChecker {
  const WorkspaceGitRemoteChecker({
    required this.workspaceStore,
    required this.secretStore,
    required this.executor,
  });

  final FileWorkspaceStore workspaceStore;
  final FileWorkspaceSecretStore secretStore;
  final WorkspaceGitCommandExecutor executor;

  Future<WorkspaceGitRemoteCheckResult> check({
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
    final storedRepositoryId = _readOptionalRepositoryId(
      remote['repositoryId'],
    );

    String? secret;
    if (secretName != null && secretName.trim().isNotEmpty) {
      secret = await secretStore.resolveForTrustedExecution(
        userId: userId,
        workspaceId: workspaceId,
        name: secretName.trim(),
        context: 'git',
      );
    }

    final result = await executor.lsRemote(
      repositoryUrl: repositoryUrl,
      branch: branch,
      username: secret == null
          ? null
          : (username?.trim().isNotEmpty == true
              ? username!.trim()
              : _defaultUsername(provider)),
      secret: secret,
    );
    if (result.exitCode != 0) {
      final detail = result.stderr.trim();
      throw WorkspaceGitRemoteException(
        detail.isEmpty ? 'Git remote check failed.' : detail,
      );
    }

    final firstLine = result.stdout
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final remoteHead =
        firstLine.isEmpty ? null : firstLine.split(RegExp(r'\s+')).first;

    _GitHubRepositoryIdentity? identity;
    if (provider == 'github' &&
        executor is ProcessWorkspaceGitCommandExecutor) {
      identity = await _tryResolveGitHubIdentity(
        repositoryUrl,
        secret: secret,
      );
      if (storedRepositoryId != null &&
          identity != null &&
          identity.id != storedRepositoryId) {
        throw WorkspaceGitRemoteException(
          'GitHub repository identity changed. Stored repository id '
          '$storedRepositoryId does not match ${identity.id}. Rebind the '
          'Workspace before pushing.',
        );
      }
    }

    return WorkspaceGitRemoteCheckResult(
      repositoryUrl: repositoryUrl,
      branch: branch,
      provider: provider,
      branchFound: remoteHead != null,
      remoteHead: remoteHead,
      repositoryId: identity?.id ?? storedRepositoryId,
      repositoryFullName: identity?.fullName,
      canonicalUrl: identity?.htmlUrl,
    );
  }

  int? _readOptionalRepositoryId(Object? value) {
    if (value == null) return null;
    if (value is! int || value <= 0) {
      throw const FormatException('Invalid GitHub repository id.');
    }
    return value;
  }

  Future<_GitHubRepositoryIdentity?> _tryResolveGitHubIdentity(
    String repositoryUrl, {
    String? secret,
  }) async {
    final coordinates = _githubCoordinates(repositoryUrl);
    if (coordinates == null) return null;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/${coordinates.owner}/${coordinates.name}',
      );
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'flutter-dart-fullstack-environment')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      if (secret != null && secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final id = decoded['id'];
      final fullName = decoded['full_name'];
      final htmlUrl = decoded['html_url'];
      if (id is! int ||
          id <= 0 ||
          fullName is! String ||
          fullName.isEmpty ||
          htmlUrl is! String ||
          htmlUrl.isEmpty) {
        return null;
      }

      return _GitHubRepositoryIdentity(
        id: id,
        fullName: fullName,
        htmlUrl: htmlUrl,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  _GitHubCoordinates? _githubCoordinates(String repositoryUrl) {
    final scp = RegExp(
      r'^[^@\s]+@github\.com:([^/\s]+)/([^\s]+)$',
      caseSensitive: false,
    ).firstMatch(repositoryUrl);
    if (scp != null) {
      return _GitHubCoordinates(
        owner: scp.group(1)!,
        name: _trimGitSuffix(scp.group(2)!),
      );
    }

    final uri = Uri.tryParse(repositoryUrl);
    if (uri == null || uri.host.toLowerCase() != 'github.com') return null;
    final parts = uri.pathSegments
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;
    return _GitHubCoordinates(
      owner: parts[0],
      name: _trimGitSuffix(parts[1]),
    );
  }

  String _trimGitSuffix(String value) {
    var source = value.trim();
    while (source.endsWith('/')) {
      source = source.substring(0, source.length - 1);
    }
    return source.toLowerCase().endsWith('.git')
        ? source.substring(0, source.length - 4)
        : source;
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

class _GitHubCoordinates {
  const _GitHubCoordinates({
    required this.owner,
    required this.name,
  });

  final String owner;
  final String name;
}

class _GitHubRepositoryIdentity {
  const _GitHubRepositoryIdentity({
    required this.id,
    required this.fullName,
    required this.htmlUrl,
  });

  final int id;
  final String fullName;
  final String htmlUrl;
}
