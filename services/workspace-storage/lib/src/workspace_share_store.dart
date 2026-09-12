import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'workspace_store.dart';

class WorkspaceShareRecord {
  const WorkspaceShareRecord({
    required this.token,
    required this.userId,
    required this.workspaceId,
    required this.revision,
    required this.createdAt,
  });

  final String token;
  final String userId;
  final String workspaceId;
  final String revision;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token,
        'userId': userId,
        'workspaceId': workspaceId,
        'revision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toPublicJson() => <String, dynamic>{
        'token': token,
        'workspaceId': workspaceId,
        'revision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'sharePath': '/shares/$token',
      };

  factory WorkspaceShareRecord.fromJson(Map<dynamic, dynamic> json) {
    final token = json['token'];
    final userId = json['userId'];
    final workspaceId = json['workspaceId'];
    final revision = json['revision'];
    final createdAt = json['createdAt'];

    if (token is! String ||
        token.isEmpty ||
        userId is! String ||
        userId.isEmpty ||
        workspaceId is! String ||
        workspaceId.isEmpty ||
        revision is! String ||
        revision.isEmpty ||
        createdAt is! String) {
      throw const FormatException('Invalid Workspace share record.');
    }

    final parsedCreatedAt = DateTime.tryParse(createdAt)?.toUtc();
    if (parsedCreatedAt == null) {
      throw const FormatException('Invalid Workspace share creation time.');
    }

    return WorkspaceShareRecord(
      token: token,
      userId: userId,
      workspaceId: workspaceId,
      revision: revision,
      createdAt: parsedCreatedAt,
    );
  }
}

class WorkspaceSharedDocument {
  const WorkspaceSharedDocument({
    required this.share,
    required this.document,
  });

  final WorkspaceShareRecord share;
  final Map<String, dynamic> document;
}

class WorkspaceSharedMetadata {
  const WorkspaceSharedMetadata({
    required this.share,
    required this.project,
  });

  final WorkspaceShareRecord share;
  final Map<String, dynamic> project;
}

class WorkspaceShareTreeEntry {
  const WorkspaceShareTreeEntry({
    required this.path,
    required this.type,
    this.encoding,
    this.size,
    this.sha256,
    this.storageKey,
  });

  final String path;
  final String type;
  final String? encoding;
  final int? size;
  final String? sha256;
  final String? storageKey;

  bool get isFile => type == 'blob';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'path': path,
        'type': type,
        if (encoding != null) 'encoding': encoding,
        if (size != null) 'size': size,
        if (sha256 != null) 'sha256': sha256,
        if (storageKey != null) 'storageKey': storageKey,
      };

  Map<String, Object?> toPublicJson(String token) => <String, Object?>{
        'path': path,
        'type': type,
        if (encoding != null) 'encoding': encoding,
        if (size != null) 'size': size,
        if (sha256 != null) 'sha256': sha256,
        if (isFile)
          'rawPath':
              '/shares/$token/raw/${path.split('/').map(Uri.encodeComponent).join('/')}',
      };

  factory WorkspaceShareTreeEntry.fromJson(Map<dynamic, dynamic> json) {
    final path = json['path'];
    final type = json['type'];
    final encoding = json['encoding'];
    final size = json['size'];
    final sha256 = json['sha256'];
    final storageKey = json['storageKey'];

    if (path is! String || path.isEmpty || (type != 'tree' && type != 'blob')) {
      throw const FormatException('Invalid Workspace share tree entry.');
    }
    if (type == 'blob') {
      if ((encoding != 'utf8' && encoding != 'base64') ||
          size is! int ||
          size < 0 ||
          sha256 is! String ||
          sha256.isEmpty ||
          storageKey is! String ||
          !RegExp(r'^\d{8}\.raw$').hasMatch(storageKey)) {
        throw const FormatException('Invalid Workspace share file entry.');
      }
    }

    return WorkspaceShareTreeEntry(
      path: path,
      type: type as String,
      encoding: encoding as String?,
      size: size as int?,
      sha256: sha256 as String?,
      storageKey: storageKey as String?,
    );
  }
}

class WorkspaceSharedTree {
  const WorkspaceSharedTree({
    required this.share,
    required this.entries,
  });

  final WorkspaceShareRecord share;
  final List<WorkspaceShareTreeEntry> entries;
}

class WorkspaceSharedFile {
  WorkspaceSharedFile._({
    required this.share,
    required this.binary,
    required File file,
  }) : _file = file;

  final WorkspaceShareRecord share;
  final bool binary;
  final File _file;

  Future<int> length() => _file.length();

  Stream<List<int>> openRead() => _file.openRead();
}

/// Durable, immutable read-only Workspace shares.
///
/// Version 2 shares are split on disk: metadata, a content-free tree, and one
/// raw file per Workspace entry. Public reads therefore never need to decode a
/// complete Workspace snapshot merely to serve one file.
class FileWorkspaceShareStore {
  FileWorkspaceShareStore(
    this.root, {
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? _utcNow;

  final Directory root;
  final Random _random;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  /// Backward-compatible entry point for callers that already own a document.
  /// New server code should prefer [createShareFromWorkspace], which never
  /// materializes the full Workspace in memory.
  Future<WorkspaceShareRecord> createShare({
    required String userId,
    required String workspaceId,
    required Map<String, dynamic> document,
  }) {
    return _serialized(() {
      return _createSplitShare(
        userId: userId,
        workspaceId: workspaceId,
        visitSnapshot: (onEntry) async {
          final metadata = _metadataFromDocument(document);
          final snapshot = document['snapshot'] as Map;
          final entries = snapshot['entries'];
          if (entries is! Iterable) {
            throw const FormatException('Workspace share entries are invalid.');
          }
          for (final raw in entries) {
            if (raw is! Map) {
              throw const FormatException('Workspace share entry is invalid.');
            }
            await onEntry(Map<String, dynamic>.from(raw));
          }
          return metadata;
        },
      );
    });
  }

  /// Creates a share directly from split Workspace storage. The Workspace store
  /// holds its per-user serialization lock while entries are visited, so the
  /// metadata revision and every copied entry belong to the same snapshot.
  Future<WorkspaceShareRecord> createShareFromWorkspace({
    required String userId,
    required String workspaceId,
    required FileWorkspaceStore workspaceStore,
  }) {
    return _serialized(() {
      return _createSplitShare(
        userId: userId,
        workspaceId: workspaceId,
        visitSnapshot: (onEntry) {
          return workspaceStore.visitWorkspaceSnapshot(
            userId: userId,
            workspaceId: workspaceId,
            onEntry: onEntry,
          );
        },
      );
    });
  }

  Future<WorkspaceShareRecord> _createSplitShare({
    required String userId,
    required String workspaceId,
    required Future<Map<String, dynamic>?> Function(
      Future<void> Function(Map<String, dynamic> entry) onEntry,
    ) visitSnapshot,
  }) async {
    await _sharesDirectory.create(recursive: true);
    final token = await _newToken();
    final target = _shareDirectory(token);
    final temp = Directory(
      '${_sharesDirectory.path}${Platform.pathSeparator}.$token.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final filesDirectory = Directory(
      '${temp.path}${Platform.pathSeparator}files',
    );
    await filesDirectory.create(recursive: true);

    final tree = <WorkspaceShareTreeEntry>[];
    final seenPaths = <String>{};
    var fileSequence = 0;

    try {
      final metadata = await visitSnapshot((entry) async {
        final path = entry['path'];
        final type = entry['type'];
        if (path is! String || path.isEmpty) {
          throw const FormatException('Workspace share entry path is invalid.');
        }
        if (!seenPaths.add(path)) {
          throw FormatException(
              'Workspace share contains duplicate path: $path');
        }

        if (type == 'directory') {
          tree.add(WorkspaceShareTreeEntry(path: path, type: 'tree'));
          return;
        }
        if (type != 'file') {
          throw const FormatException('Workspace share entry type is invalid.');
        }

        final content = entry['content'];
        if (content is! String) {
          throw FormatException(
              'Workspace share file content is invalid: $path');
        }
        final encoding = entry['encoding'] == 'base64' ? 'base64' : 'utf8';
        final storageKey = '${fileSequence.toString().padLeft(8, '0')}.raw';
        fileSequence += 1;
        final file = File(
          '${filesDirectory.path}${Platform.pathSeparator}$storageKey',
        );

        if (encoding == 'base64') {
          final sink = file.openWrite();
          try {
            await sink.addStream(
              base64.decoder.bind(Stream<String>.value(content)),
            );
          } finally {
            await sink.close();
          }
        } else {
          await file.writeAsString(content, encoding: utf8, flush: false);
        }

        final size = await file.length();
        tree.add(
          WorkspaceShareTreeEntry(
            path: path,
            type: 'blob',
            encoding: encoding,
            size: size,
            sha256: await _sha256File(file),
            storageKey: storageKey,
          ),
        );
      });

      if (metadata == null) {
        throw WorkspaceDocumentNotFound(workspaceId);
      }
      final revision = _readRevision(metadata);
      final record = WorkspaceShareRecord(
        token: token,
        userId: userId,
        workspaceId: workspaceId,
        revision: revision,
        createdAt: _clock().toUtc(),
      );

      tree.sort((a, b) => a.path.compareTo(b.path));
      await _writeJson(
        File('${temp.path}${Platform.pathSeparator}meta.json'),
        <String, dynamic>{
          'version': 2,
          'project': Map<String, dynamic>.from(metadata['project'] as Map),
          'snapshot': Map<String, dynamic>.from(metadata['snapshot'] as Map),
          'revision': revision,
        },
      );
      await _writeJson(
        File('${temp.path}${Platform.pathSeparator}tree.json'),
        <String, dynamic>{
          'version': 2,
          'entries':
              tree.map((entry) => entry.toJson()).toList(growable: false),
        },
      );

      await temp.rename(target.path);
      try {
        final records = await _readIndex();
        records.add(record);
        await _writeIndex(records);
      } catch (_) {
        if (await target.exists()) {
          await target.delete(recursive: true);
        }
        rethrow;
      }
      return record;
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<List<WorkspaceShareRecord>> listShares({
    required String userId,
    required String workspaceId,
  }) {
    return _serialized(() async {
      final records = await _readIndex();
      return records
          .where(
            (record) =>
                record.userId == userId && record.workspaceId == workspaceId,
          )
          .toList(growable: false);
    });
  }

  Future<WorkspaceSharedMetadata?> resolveMetadata(String token) {
    return _serialized(() async {
      final record = await _findRecord(token);
      if (record == null) return null;

      final meta = await _readSplitMeta(token);
      if (meta != null) {
        _validateSplitRevision(meta, record);
        final project = meta['project'];
        if (project is! Map) {
          throw const FormatException('Workspace share project is invalid.');
        }
        return WorkspaceSharedMetadata(
          share: record,
          project: Map<String, dynamic>.from(project),
        );
      }

      // Legacy v1 shares are intentionally not loaded by public routes. A v1
      // token stores one giant Workspace JSON and decoding it here can recreate
      // the Railway OOM. Revoke/recreate the share once to migrate to v2.
      return null;
    });
  }

  Future<WorkspaceSharedTree?> loadTree(String token) {
    return _serialized(() async {
      final record = await _findRecord(token);
      if (record == null) return null;

      final treeFile = _treeFile(token);
      if (await treeFile.exists()) {
        final payload = await _readJsonObject(treeFile, 'Workspace share tree');
        final rawEntries = payload['entries'];
        if (rawEntries is! Iterable) {
          throw const FormatException('Workspace share tree is invalid.');
        }
        final entries = rawEntries.map((raw) {
          if (raw is! Map) {
            throw const FormatException('Workspace share tree row is invalid.');
          }
          return WorkspaceShareTreeEntry.fromJson(raw);
        }).toList(growable: false);
        return WorkspaceSharedTree(share: record, entries: entries);
      }

      // Do not decode legacy giant snapshots from a public request.
      return null;
    });
  }

  Future<WorkspaceSharedFile?> openFile(String token, String path) {
    return _serialized(() async {
      final record = await _findRecord(token);
      if (record == null) return null;

      final treeFile = _treeFile(token);
      if (await treeFile.exists()) {
        final payload = await _readJsonObject(treeFile, 'Workspace share tree');
        final rawEntries = payload['entries'];
        if (rawEntries is! Iterable) {
          throw const FormatException('Workspace share tree is invalid.');
        }
        WorkspaceShareTreeEntry? match;
        for (final raw in rawEntries) {
          if (raw is! Map) continue;
          final candidate = WorkspaceShareTreeEntry.fromJson(raw);
          if (candidate.path == path && candidate.isFile) {
            match = candidate;
            break;
          }
        }
        if (match == null) return null;
        final file = File(
          '${_shareFilesDirectory(token).path}${Platform.pathSeparator}${match.storageKey}',
        );
        if (!await file.exists()) return null;
        return WorkspaceSharedFile._(
          share: record,
          binary: match.encoding == 'base64',
          file: file,
        );
      }

      // Do not decode legacy giant snapshots from a public request.
      return null;
    });
  }

  /// Compatibility API for older internal callers. New public HTTP routes use
  /// metadata/tree/raw methods above and avoid reconstructing a full document.
  Future<WorkspaceSharedDocument?> resolve(String token) {
    return _serialized(() async {
      final record = await _findRecord(token);
      if (record == null) return null;

      final legacy = await _readLegacySharedDocument(record);
      if (legacy != null) return legacy;

      final meta = await _readSplitMeta(token);
      if (meta == null) return null;
      _validateSplitRevision(meta, record);
      final treePayload = await _readJsonObject(
        _treeFile(token),
        'Workspace share tree',
      );
      final rawEntries = treePayload['entries'];
      if (rawEntries is! Iterable) {
        throw const FormatException('Workspace share tree is invalid.');
      }

      final entries = <Map<String, dynamic>>[];
      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final entry = WorkspaceShareTreeEntry.fromJson(raw);
        if (!entry.isFile) {
          entries
              .add(<String, dynamic>{'path': entry.path, 'type': 'directory'});
          continue;
        }
        final file = File(
          '${_shareFilesDirectory(token).path}${Platform.pathSeparator}${entry.storageKey}',
        );
        final content = entry.encoding == 'base64'
            ? base64Encode(await file.readAsBytes())
            : await file.readAsString();
        entries.add(<String, dynamic>{
          'path': entry.path,
          'type': 'file',
          'encoding': entry.encoding,
          'content': content,
        });
      }

      final snapshot = Map<String, dynamic>.from(meta['snapshot'] as Map)
        ..['entries'] = entries
        ..['baseEntries'] = <Map<String, dynamic>>[];
      return WorkspaceSharedDocument(
        share: record,
        document: <String, dynamic>{
          'project': Map<String, dynamic>.from(meta['project'] as Map),
          'snapshot': snapshot,
          'revision': record.revision,
        },
      );
    });
  }

  Future<bool> revoke({
    required String userId,
    required String workspaceId,
    required String token,
  }) {
    return _serialized(() async {
      final records = await _readIndex();
      final before = records.length;
      records.removeWhere(
        (record) =>
            record.token == token &&
            record.userId == userId &&
            record.workspaceId == workspaceId,
      );
      if (records.length == before) return false;

      await _deleteSharePayload(token);
      await _writeIndex(records);
      return true;
    });
  }

  Future<void> revokeWorkspace({
    required String userId,
    required String workspaceId,
  }) {
    return _serialized(() async {
      final records = await _readIndex();
      final revoked = records
          .where(
            (record) =>
                record.userId == userId && record.workspaceId == workspaceId,
          )
          .toList(growable: false);
      if (revoked.isEmpty) return;

      records.removeWhere(
        (record) =>
            record.userId == userId && record.workspaceId == workspaceId,
      );
      for (final record in revoked) {
        await _deleteSharePayload(record.token);
      }
      await _writeIndex(records);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<WorkspaceShareRecord?> _findRecord(String token) async {
    if (!_isValidToken(token)) return null;
    final records = await _readIndex();
    for (final record in records) {
      if (record.token == token) return record;
    }
    return null;
  }

  Future<String> _newToken() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
      final token = base64UrlEncode(bytes).replaceAll('=', '');
      if (!await _legacySnapshotFile(token).exists() &&
          !await _shareDirectory(token).exists()) {
        return token;
      }
    }
    throw StateError('Unable to allocate a unique Workspace share token.');
  }

  Future<List<WorkspaceShareRecord>> _readIndex() async {
    final file = _indexFile;
    if (!await file.exists()) return <WorkspaceShareRecord>[];

    final payload = await _readJsonObject(file, 'Workspace share index');
    final rawShares = payload['shares'];
    if (rawShares is! Iterable) {
      throw const FormatException('Workspace share index is invalid.');
    }

    return rawShares.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Workspace share index row is invalid.');
      }
      return WorkspaceShareRecord.fromJson(raw);
    }).toList(growable: true);
  }

  Future<void> _writeIndex(List<WorkspaceShareRecord> records) {
    return _writeJson(
      _indexFile,
      <String, dynamic>{
        'version': 2,
        'shares': records.map((record) => record.toJson()).toList(),
      },
    );
  }

  Future<Map<String, dynamic>?> _readSplitMeta(String token) async {
    final file = _metaFile(token);
    if (!await file.exists()) return null;
    return _readJsonObject(file, 'Workspace share metadata');
  }

  Future<WorkspaceSharedDocument?> _readLegacySharedDocument(
    WorkspaceShareRecord record,
  ) async {
    final file = _legacySnapshotFile(record.token);
    if (!await file.exists()) return null;
    final payload = await _readJsonObject(file, 'Workspace share snapshot');
    final document = payload['document'];
    if (document is! Map) {
      throw const FormatException('Workspace share document is invalid.');
    }
    final decoded = Map<String, dynamic>.from(document);
    if (_readRevision(decoded) != record.revision) {
      throw const FormatException('Workspace share revision is inconsistent.');
    }
    return WorkspaceSharedDocument(share: record, document: decoded);
  }

  Map<String, dynamic> _metadataFromDocument(Map<String, dynamic> document) {
    final revision = _readRevision(document);
    final project = document['project'] as Map;
    final rawSnapshot = document['snapshot'] as Map;
    final snapshot = Map<String, dynamic>.from(rawSnapshot)
      ..remove('entries')
      ..remove('baseEntries');
    return <String, dynamic>{
      'project': Map<String, dynamic>.from(project),
      'snapshot': snapshot,
      'revision': revision,
    };
  }

  void _validateSplitRevision(
    Map<String, dynamic> metadata,
    WorkspaceShareRecord record,
  ) {
    final revision = metadata['revision'];
    if (revision != record.revision) {
      throw const FormatException('Workspace share revision is inconsistent.');
    }
  }

  Future<void> _deleteSharePayload(String token) async {
    final directory = _shareDirectory(token);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    final legacy = _legacySnapshotFile(token);
    if (await legacy.exists()) {
      await legacy.delete();
    }
  }

  Future<Map<String, dynamic>> _readJsonObject(
    File file,
    String label,
  ) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw FormatException('$label must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _writeJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  String _readRevision(Map<String, dynamic> document) {
    final revision = document['revision'];
    if (revision is! String || revision.isEmpty) {
      throw const FormatException('Workspace share revision is invalid.');
    }
    if (document['project'] is! Map || document['snapshot'] is! Map) {
      throw const FormatException('Workspace share document is invalid.');
    }
    return revision;
  }

  Future<String> _sha256File(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    return _digestHex(digest.bytes);
  }

  String _digestHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  bool _isValidToken(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(value);

  Directory get _sharesDirectory =>
      Directory('${root.path}${Platform.pathSeparator}shares');

  File get _indexFile =>
      File('${_sharesDirectory.path}${Platform.pathSeparator}index.json');

  Directory _shareDirectory(String token) => Directory(
        '${_sharesDirectory.path}${Platform.pathSeparator}$token',
      );

  File _metaFile(String token) => File(
        '${_shareDirectory(token).path}${Platform.pathSeparator}meta.json',
      );

  File _treeFile(String token) => File(
        '${_shareDirectory(token).path}${Platform.pathSeparator}tree.json',
      );

  Directory _shareFilesDirectory(String token) => Directory(
        '${_shareDirectory(token).path}${Platform.pathSeparator}files',
      );

  File _legacySnapshotFile(String token) => File(
        '${_sharesDirectory.path}${Platform.pathSeparator}$token.json',
      );

  static DateTime _utcNow() => DateTime.now().toUtc();
}
