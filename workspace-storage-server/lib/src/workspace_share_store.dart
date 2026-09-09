import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// Durable, immutable read-only Workspace shares.
///
/// Each token points at the exact Workspace document that existed when the
/// share was created. Later edits to the live Workspace therefore cannot make
/// a multi-file reader observe a mixture of revisions.
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

  Future<WorkspaceShareRecord> createShare({
    required String userId,
    required String workspaceId,
    required Map<String, dynamic> document,
  }) {
    return _serialized(() async {
      final revision = _readRevision(document);
      final token = await _newToken();
      final record = WorkspaceShareRecord(
        token: token,
        userId: userId,
        workspaceId: workspaceId,
        revision: revision,
        createdAt: _clock().toUtc(),
      );

      await _sharesDirectory.create(recursive: true);
      await _writeJson(
        _snapshotFile(token),
        <String, dynamic>{'document': document},
      );

      final records = await _readIndex();
      records.add(record);
      await _writeIndex(records);
      return record;
    });
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

  Future<WorkspaceSharedDocument?> resolve(String token) {
    return _serialized(() async {
      if (!_isValidToken(token)) return null;

      final records = await _readIndex();
      WorkspaceShareRecord? record;
      for (final candidate in records) {
        if (candidate.token == token) {
          record = candidate;
          break;
        }
      }
      if (record == null) return null;

      final file = _snapshotFile(token);
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

      return WorkspaceSharedDocument(
        share: record,
        document: decoded,
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

      final file = _snapshotFile(token);
      if (await file.exists()) {
        await file.delete();
      }
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
        final file = _snapshotFile(record.token);
        if (await file.exists()) {
          await file.delete();
        }
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

  Future<String> _newToken() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
      final token = base64UrlEncode(bytes).replaceAll('=', '');
      if (!await _snapshotFile(token).exists()) return token;
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
        'version': 1,
        'shares': records.map((record) => record.toJson()).toList(),
      },
    );
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
    await file.writeAsString(jsonEncode(value), flush: true);
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

  bool _isValidToken(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(value);

  Directory get _sharesDirectory =>
      Directory('${root.path}${Platform.pathSeparator}shares');

  File get _indexFile =>
      File('${_sharesDirectory.path}${Platform.pathSeparator}index.json');

  File _snapshotFile(String token) => File(
        '${_sharesDirectory.path}${Platform.pathSeparator}$token.json',
      );

  static DateTime _utcNow() => DateTime.now().toUtc();
}
