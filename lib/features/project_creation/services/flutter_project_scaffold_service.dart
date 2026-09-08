import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_snapshot.dart';

class FlutterProjectScaffoldService {
  FlutterProjectScaffoldService({
    required String baseUrl,
    this.accessToken = const String.fromEnvironment('RUNNER_API_TOKEN'),
    http.Client? httpClient,
  })  : baseUrl = baseUrl.replaceFirst(
          RegExp(r'/+$'),
          '',
        ),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String accessToken;

  final http.Client _http;

  Future<WorkspaceSnapshot> create({
    required String projectName,
    required Set<String> platforms,
  }) async {
    if (platforms.isEmpty) {
      throw ArgumentError(
        'Select at least one Flutter platform.',
      );
    }

    final response = await _http.post(
      Uri.parse('$baseUrl/sessions'),
      headers: _headers(json: true),
      body: jsonEncode(
        <String, Object?>{
          'files': <String, String>{},
          'projectName': projectName,
          'platforms': platforms.toList(),
          'includeWorkspace': true,
          'firebaseCapabilities': <String>[],
        },
      ),
    );

    final body = _decodeObject(
      response,
      expected: const <int>{200, 201},
    );

    final rawSession = body['session'];

    if (rawSession is! Map) {
      throw const FormatException(
        'Runner did not return a session.',
      );
    }

    final sessionId = rawSession['id'];

    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException(
        'Runner session id is missing.',
      );
    }

    try {
      final rawWorkspace = body['workspace'];

      if (rawWorkspace is! Map) {
        throw const FormatException(
          'Runner did not return the generated Flutter workspace.',
        );
      }

      return _buildSnapshot(
        rawWorkspace,
      );
    } finally {
      await _deleteTemporarySession(
        sessionId,
      );
    }
  }

  Future<void> _deleteTemporarySession(
    String sessionId,
  ) async {
    try {
      await _http.delete(
        Uri.parse(
          '$baseUrl/sessions/$sessionId',
        ),
        headers: _headers(),
      );
    } catch (_) {
      // Session 本身还有服务器 idle cleanup。
      // 删除失败不应该导致用户刚创建的项目丢失。
    }
  }

  WorkspaceSnapshot _buildSnapshot(
    Map rawWorkspace,
  ) {
    final rawFiles = rawWorkspace['files'];
    final rawDirectories = rawWorkspace['directories'];

    if (rawFiles is! Map) {
      throw const FormatException(
        'Generated workspace files are missing.',
      );
    }

    final files = <String, String>{};

    for (final entry in rawFiles.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
          'Invalid generated workspace file.',
        );
      }

      files[entry.key as String] = entry.value as String;
    }

    final directories = <String>{};

    if (rawDirectories is Iterable) {
      for (final value in rawDirectories) {
        if (value is String && value.isNotEmpty) {
          directories.add(value);
        }
      }
    }

    // 双保险：即使服务器没有返回某一级目录，
    // 也从文件路径补回来。
    for (final path in files.keys) {
      final parts = path.split('/');

      for (var i = 1; i < parts.length; i++) {
        directories.add(
          parts.take(i).join('/'),
        );
      }
    }

    final directoryPaths = directories.toList()
      ..sort((a, b) {
        final depthCompare = _depth(a).compareTo(
          _depth(b),
        );

        if (depthCompare != 0) {
          return depthCompare;
        }

        return a.compareTo(b);
      });

    final filePaths = files.keys.toList()..sort();

    final entries = <WorkspaceEntry>[];

    var idCounter = 0;

    for (final path in directoryPaths) {
      final id = 'flutter-create-${++idCounter}';

      entries.add(
        WorkspaceEntry(
          id: id,
          path: path,
          type: WorkspaceEntryType.directory,
        ),
      );
    }

    for (final path in filePaths) {
      final payload = files[path]!;

      final id = 'flutter-create-${++idCounter}';

      if (WorkspaceEntry.isRunnerBinaryContent(payload)) {
        entries.add(
          WorkspaceEntry.binary(
            id: id,
            path: path,
            bytes: WorkspaceEntry.decodeRunnerContent(
              payload,
            ),
          ),
        );
      } else {
        entries.add(
          WorkspaceEntry(
            id: id,
            path: path,
            type: WorkspaceEntryType.file,
            content: payload,
          ),
        );
      }
    }

    final openFiles = <String>[];

    if (files.containsKey(
      'lib/main.dart',
    )) {
      openFiles.add(
        'lib/main.dart',
      );
    }

    if (files.containsKey(
      'pubspec.yaml',
    )) {
      openFiles.add(
        'pubspec.yaml',
      );
    }

    final activePath = files.containsKey('lib/main.dart')
        ? 'lib/main.dart'
        : files.containsKey(
            'pubspec.yaml',
          )
            ? 'pubspec.yaml'
            : filePaths.first;

    return WorkspaceSnapshot(
      entries: entries,
      baseEntries: List<WorkspaceEntry>.of(
        entries,
      ),
      openFiles: openFiles,
      activePath: activePath,
      nextId: idCounter + 1,
      savedAt: DateTime.now().toUtc(),
      expandedDirectoryIds: const <String>[],
    );
  }

  int _depth(String path) {
    return '/'.allMatches(path).length;
  }

  Map<String, String> _headers({
    bool json = false,
  }) {
    return <String, String>{
      'accept': 'application/json',
      if (json) 'content-type': 'application/json',
      if (accessToken.trim().isNotEmpty)
        'authorization': 'Bearer ${accessToken.trim()}',
    };
  }

  Map<String, dynamic> _decodeObject(
    http.Response response, {
    Set<int> expected = const <int>{200},
  }) {
    if (!expected.contains(
      response.statusCode,
    )) {
      var detail = response.body;

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map && decoded['error'] is String) {
          detail = decoded['error'] as String;
        }
      } catch (_) {}

      throw StateError(
        'Runner ${response.statusCode}: $detail',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {
      throw const FormatException(
        'Runner response must be an object.',
      );
    }

    return Map<String, dynamic>.from(
      decoded,
    );
  }

  void close() {
    _http.close();
  }
}
