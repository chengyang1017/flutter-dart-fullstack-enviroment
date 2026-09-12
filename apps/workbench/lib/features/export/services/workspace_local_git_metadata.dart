import 'dart:convert';

import 'workspace_import_picker.dart';

class WorkspaceLocalGitMetadata {
  const WorkspaceLocalGitMetadata({
    required this.repositoryUrl,
    required this.remoteName,
    required this.branch,
  });

  final String repositoryUrl;
  final String remoteName;
  final String? branch;
}

WorkspaceLocalGitMetadata? detectWorkspaceLocalGitMetadata(
  List<WorkspacePickedFile> files,
) {
  if (files.isEmpty) return null;

  final byPath = <String, WorkspacePickedFile>{};
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/').trim();
    if (path.isEmpty) continue;
    byPath[path] = file;
  }

  final configPaths =
      byPath.keys.where(_isGitConfigPath).toList(growable: false)
        ..sort((a, b) {
          final depth = '/'.allMatches(a).length.compareTo(
                '/'.allMatches(b).length,
              );
          return depth != 0 ? depth : a.compareTo(b);
        });

  for (final configPath in configPaths) {
    final prefix = configPath.substring(
      0,
      configPath.length - 'config'.length,
    );
    final headPath = '${prefix}HEAD';
    final configFile = byPath[configPath];
    if (configFile == null) continue;

    final configText = _tryDecodeUtf8(configFile.bytes);
    if (configText == null) continue;

    final remotes = _readRemoteUrls(configText);
    if (remotes.isEmpty) continue;

    final remoteName = remotes.containsKey('origin')
        ? 'origin'
        : (remotes.keys.toList(growable: false)..sort()).first;
    final repositoryUrl = remotes[remoteName]?.trim();
    if (repositoryUrl == null || repositoryUrl.isEmpty) continue;

    final headFile = byPath[headPath];
    final headText = headFile == null ? null : _tryDecodeUtf8(headFile.bytes);

    return WorkspaceLocalGitMetadata(
      repositoryUrl: repositoryUrl,
      remoteName: remoteName,
      branch: _readHeadBranch(headText),
    );
  }

  return null;
}

bool _isGitConfigPath(String path) {
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  if (segments.length < 2 || segments.length > 3) return false;
  return segments[segments.length - 2] == '.git' && segments.last == 'config';
}

Map<String, String> _readRemoteUrls(String config) {
  final result = <String, String>{};
  String? currentRemote;

  for (final rawLine in const LineSplitter().convert(config)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }

    final section = RegExp(
      r'^\[\s*remote\s+"([^"]+)"\s*\]$',
      caseSensitive: false,
    ).firstMatch(line);
    if (section != null) {
      currentRemote = section.group(1)?.trim();
      continue;
    }

    if (line.startsWith('[')) {
      currentRemote = null;
      continue;
    }

    if (currentRemote == null) continue;

    final equals = line.indexOf('=');
    if (equals <= 0) continue;

    final key = line.substring(0, equals).trim().toLowerCase();
    if (key != 'url') continue;

    final value = line.substring(equals + 1).trim();
    if (value.isNotEmpty) {
      result[currentRemote] = value;
    }
  }

  return result;
}

String? _readHeadBranch(String? head) {
  if (head == null) return null;
  final source = head.trim();
  const prefix = 'ref: refs/heads/';
  if (!source.startsWith(prefix)) return null;

  final branch = source.substring(prefix.length).trim();
  if (branch.isEmpty ||
      branch.startsWith('/') ||
      branch.endsWith('/') ||
      branch.contains('..') ||
      branch.contains('//') ||
      branch.contains('@{') ||
      !RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(branch)) {
    return null;
  }
  return branch;
}

String? _tryDecodeUtf8(List<int> bytes) {
  if (bytes.contains(0)) return null;
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return null;
  }
}
