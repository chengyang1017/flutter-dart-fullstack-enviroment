import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WorkspaceRevisionMismatch implements Exception {
  const WorkspaceRevisionMismatch({
    required this.workspaceId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final String workspaceId;
  final String expectedRevision;
  final String actualRevision;

  @override
  String toString() =>
      'WorkspaceRevisionMismatch(workspaceId: $workspaceId, '
      'expected: $expectedRevision, actual: $actualRevision)';
}

class WorkspaceDocumentNotFound implements Exception {
  const WorkspaceDocumentNotFound(this.workspaceId);

  final String workspaceId;

  @override
  String toString() => 'WorkspaceDocumentNotFound($workspaceId)';
}

class FileWorkspaceStore {
  FileWorkspaceStore(
    this.root, {
    this.temporaryWorkspaceTtl = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow {
    if (temporaryWorkspaceTtl <= Duration.zero) {
      throw ArgumentError.value(
        temporaryWorkspaceTtl,
        'temporaryWorkspaceTtl',
        'Temporary Workspace TTL must be greater than zero.',
      );
    }
  }

  final Directory root;
  final Duration temporaryWorkspaceTtl;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _userLocks = <String, Future<void>>{};

  Future<Map<String, dynamic>> loadCatalog(String userId) {
    return _serialized(userId, () async {
      final catalog = await _readCatalog(userId);
      return _purgeExpiredTemporaryWorkspaces(userId, catalog);
    });
  }

  Future<Map<String, dynamic>?> loadWorkspace(
    String userId,
    String workspaceId,
  ) {
    return _serialized(userId, () => _readDocument(userId, workspaceId));
  }

  Future<Map<String, dynamic>> createWorkspace({
    required String userId,
    required Map<String, dynamic> project,
    required Map<String, dynamic> snapshot,
  }) {
    return _serialized(userId, () async {
      final workspaceId = _readWorkspaceId(project);
      final existing = await _readDocument(userId, workspaceId);
      if (existing != null) {
        throw StateError('Workspace already exists: $workspaceId');
      }

      final document = <String, dynamic>{
        'project': project,
        'snapshot': snapshot,
        'revision': 'r1',
      };
      await _writeDocument(userId, workspaceId, document);

      final catalog = await _readCatalog(userId);
      final projects = _readProjects(catalog)
        ..removeWhere((item) => item['id'] == workspaceId)
        ..add(project);
      await _writeCatalog(
        userId,
        <String, dynamic>{
          'projects': projects,
          'revision': _nextRevision(catalog['revision'], 'c'),
        },
      );

      return document;
    });
  }

  Future<Map<String, dynamic>> saveWorkspace({
    required String userId,
    required String workspaceId,
    required Map<String, dynamic> project,
    required Map<String, dynamic> snapshot,
    required String expectedRevision,
  }) {
    return _serialized(userId, () async {
      if (_readWorkspaceId(project) != workspaceId) {
        throw const FormatException(
          'Workspace project id does not match the requested Workspace.',
        );
      }

      final current = await _readDocument(userId, workspaceId);
      if (current == null) {
        throw WorkspaceDocumentNotFound(workspaceId);
      }
      final actualRevision = current['revision'];
      if (actualRevision is! String || actualRevision.isEmpty) {
        throw StateError('Stored Workspace revision is invalid: $workspaceId');
      }
      if (actualRevision != expectedRevision) {
        throw WorkspaceRevisionMismatch(
          workspaceId: workspaceId,
          expectedRevision: expectedRevision,
          actualRevision: actualRevision,
        );
      }

      final document = <String, dynamic>{
        'project': project,
        'snapshot': snapshot,
        'revision': _nextRevision(actualRevision, 'r'),
      };
      await _writeDocument(userId, workspaceId, document);

      final catalog = await _readCatalog(userId);
      final projects = _readProjects(catalog);
      final index = projects.indexWhere((item) => item['id'] == workspaceId);
      if (index == -1) {
        projects.add(project);
      } else {
        projects[index] = project;
      }
      await _writeCatalog(
        userId,
        <String, dynamic>{
          'projects': projects,
          'revision': _nextRevision(catalog['revision'], 'c'),
        },
      );

      return document;
    });
  }

  Future<Map<String, dynamic>> patchWorkspace({
    required String userId,
    required String workspaceId,
    required Map<String, dynamic> project,
    required Map<String, dynamic> delta,
    required String expectedRevision,
  }) {
    return _serialized(userId, () async {
      if (_readWorkspaceId(project) != workspaceId) {
        throw const FormatException(
          'Workspace project id does not match the requested Workspace.',
        );
      }

      var meta = await _readSplitMeta(userId, workspaceId);
      if (meta == null) {
        final legacy = await _readLegacyDocument(userId, workspaceId);
        if (legacy == null) {
          throw WorkspaceDocumentNotFound(workspaceId);
        }
        final legacyRevision = _readDocumentRevision(legacy, workspaceId);
        if (legacyRevision != expectedRevision) {
          throw WorkspaceRevisionMismatch(
            workspaceId: workspaceId,
            expectedRevision: expectedRevision,
            actualRevision: legacyRevision,
          );
        }

        // Existing Railway data used one large JSON document. Migrate it once
        // on the first delta save, then every later PATCH can touch only the
        // changed entry files plus the small metadata manifest.
        await _writeSplitDocument(userId, workspaceId, legacy);
        meta = await _readSplitMeta(userId, workspaceId);
        if (meta == null) {
          throw StateError('Workspace split migration failed: $workspaceId');
        }
      }

      final actualRevision = _readDocumentRevision(meta, workspaceId);
      if (actualRevision != expectedRevision) {
        throw WorkspaceRevisionMismatch(
          workspaceId: workspaceId,
          expectedRevision: expectedRevision,
          actualRevision: actualRevision,
        );
      }

      final currentManifest = meta['snapshot'];
      if (currentManifest is! Map) {
        throw const FormatException('Stored Workspace manifest is invalid.');
      }
      final nextManifest = _applySnapshotManifestDelta(
        Map<String, dynamic>.from(currentManifest),
        delta,
      );
      final entryDelta = _parseEntryDelta(
        delta['entries'],
        label: 'entries',
      );
      final baseEntryDelta = _parseEntryDelta(
        delta['baseEntries'],
        label: 'baseEntries',
      );

      await _applySplitEntryDelta(
        _workspaceEntriesDirectory(userId, workspaceId),
        entryDelta,
      );
      await _applySplitEntryDelta(
        _workspaceBaseEntriesDirectory(userId, workspaceId),
        baseEntryDelta,
      );

      final revision = _nextRevision(actualRevision, 'r');
      await _writeSplitMeta(
        userId,
        workspaceId,
        <String, dynamic>{
          'project': project,
          'snapshot': nextManifest,
          'revision': revision,
        },
      );

      final catalog = await _readCatalog(userId);
      final projects = _readProjects(catalog);
      final index = projects.indexWhere((item) => item['id'] == workspaceId);
      if (index == -1) {
        projects.add(project);
      } else {
        projects[index] = project;
      }
      await _writeCatalog(
        userId,
        <String, dynamic>{
          'projects': projects,
          'revision': _nextRevision(catalog['revision'], 'c'),
        },
      );

      // The client already owns the resulting snapshot. Echoing it back would
      // erase the bandwidth benefit of delta transport.
      return <String, dynamic>{'revision': revision};
    });
  }

  Future<Map<String, dynamic>> deleteWorkspace({
    required String userId,
    required String workspaceId,
    required String expectedRevision,
  }) {
    return _serialized(userId, () async {
      final current = await _readDocument(userId, workspaceId);
      if (current == null) {
        throw WorkspaceDocumentNotFound(workspaceId);
      }
      final actualRevision = current['revision'];
      if (actualRevision is! String || actualRevision.isEmpty) {
        throw StateError('Stored Workspace revision is invalid: $workspaceId');
      }
      if (actualRevision != expectedRevision) {
        throw WorkspaceRevisionMismatch(
          workspaceId: workspaceId,
          expectedRevision: expectedRevision,
          actualRevision: actualRevision,
        );
      }

      await _deleteDocument(userId, workspaceId);

      final catalog = await _readCatalog(userId);
      final projects = _readProjects(catalog)
        ..removeWhere((item) => item['id'] == workspaceId);
      final next = <String, dynamic>{
        'projects': projects,
        'revision': _nextRevision(catalog['revision'], 'c'),
      };
      await _writeCatalog(userId, next);
      return next;
    });
  }

  Map<String, dynamic> _applySnapshotManifestDelta(
    Map<String, dynamic> current,
    Map<String, dynamic> delta,
  ) {
    if (delta['formatVersion'] != 1) {
      throw const FormatException('Unsupported Workspace delta version.');
    }

    final manifest = delta['manifest'];
    if (manifest is! Map) {
      throw const FormatException('Workspace delta manifest is invalid.');
    }
    final next = Map<String, dynamic>.from(current);
    for (final entry in manifest.entries) {
      if (entry.key is! String) {
        throw const FormatException('Workspace delta manifest key is invalid.');
      }
      final key = entry.key as String;
      if (key == 'entries' || key == 'baseEntries') {
        throw const FormatException(
          'Workspace delta manifest cannot replace entry collections.',
        );
      }
      next[key] = entry.value;
    }
    return next;
  }

  _WorkspaceEntryDelta _parseEntryDelta(
    Object? value, {
    required String label,
  }) {
    if (value is! Map) {
      throw FormatException('Workspace delta $label is invalid.');
    }

    final deleteIds = value['deleteIds'];
    if (deleteIds is! Iterable) {
      throw FormatException('Workspace delta $label deleteIds is invalid.');
    }
    final deletes = <String>{};
    for (final id in deleteIds) {
      if (id is! String || id.isEmpty) {
        throw FormatException('Workspace delta $label delete id is invalid.');
      }
      deletes.add(id);
    }

    final upserts = value['upsert'];
    if (upserts is! Iterable) {
      throw FormatException('Workspace delta $label upsert is invalid.');
    }
    final rows = <String, Map<String, dynamic>>{};
    for (final raw in upserts) {
      if (raw is! Map) {
        throw FormatException('Workspace delta $label row is invalid.');
      }
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'];
      if (id is! String || id.isEmpty) {
        throw FormatException('Workspace delta $label id is invalid.');
      }
      rows[id] = row;
    }

    return _WorkspaceEntryDelta(
      deleteIds: deletes,
      upserts: rows,
    );
  }

  Future<void> _applySplitEntryDelta(
    Directory directory,
    _WorkspaceEntryDelta delta,
  ) async {
    await directory.create(recursive: true);

    for (final id in delta.deleteIds) {
      final file = _entryFile(directory, id);
      if (await file.exists()) {
        await file.delete();
      }
    }

    for (final entry in delta.upserts.entries) {
      await _writeJson(_entryFile(directory, entry.key), entry.value);
    }
  }

  Future<Map<String, dynamic>> _purgeExpiredTemporaryWorkspaces(
    String userId,
    Map<String, dynamic> catalog,
  ) async {
    final projects = _readProjects(catalog);
    final expiredIds = <String>[];
    final now = _clock().toUtc();

    for (final project in projects) {
      if (project['lifecycle'] != 'temporary') continue;

      final workspaceId = project['id'];
      final updatedAtSource = project['updatedAt'];
      if (workspaceId is! String || workspaceId.isEmpty) continue;
      if (updatedAtSource is! String) continue;

      final updatedAt = DateTime.tryParse(updatedAtSource)?.toUtc();
      if (updatedAt == null) continue;
      final expiresAt = updatedAt.add(temporaryWorkspaceTtl);
      if (!expiresAt.isAfter(now)) {
        expiredIds.add(workspaceId);
      }
    }

    if (expiredIds.isEmpty) return catalog;

    for (final workspaceId in expiredIds) {
      await _deleteDocument(userId, workspaceId);
    }
    projects.removeWhere((project) => expiredIds.contains(project['id']));

    final next = <String, dynamic>{
      'projects': projects,
      'revision': _nextRevision(catalog['revision'], 'c'),
    };
    await _writeCatalog(userId, next);
    return next;
  }

  Future<T> _serialized<T>(
    String userId,
    Future<T> Function() action,
  ) async {
    final previous = _userLocks[userId] ?? Future<void>.value();
    final completer = Completer<void>();
    final current = completer.future;
    _userLocks[userId] = current;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_userLocks[userId], current)) {
        _userLocks.remove(userId);
      }
    }
  }

  Future<Map<String, dynamic>> _readCatalog(String userId) async {
    final file = _catalogFile(userId);
    if (!await file.exists()) {
      return <String, dynamic>{
        'projects': <Map<String, dynamic>>[],
        'revision': 'c0',
      };
    }
    return _readJsonObject(file, 'Workspace catalog');
  }

  Future<Map<String, dynamic>?> _readDocument(
    String userId,
    String workspaceId,
  ) async {
    final split = await _readSplitDocument(userId, workspaceId);
    if (split != null) return split;
    return _readLegacyDocument(userId, workspaceId);
  }

  Future<Map<String, dynamic>?> _readLegacyDocument(
    String userId,
    String workspaceId,
  ) async {
    final file = _documentFile(userId, workspaceId);
    if (!await file.exists()) return null;
    return _readJsonObject(file, 'Workspace document');
  }

  Future<Map<String, dynamic>?> _readSplitDocument(
    String userId,
    String workspaceId,
  ) async {
    final meta = await _readSplitMeta(userId, workspaceId);
    if (meta == null) return null;

    final rawProject = meta['project'];
    final rawManifest = meta['snapshot'];
    final revision = meta['revision'];
    if (rawProject is! Map ||
        rawManifest is! Map ||
        revision is! String ||
        revision.isEmpty) {
      throw const FormatException('Workspace split metadata is invalid.');
    }

    final snapshot = Map<String, dynamic>.from(rawManifest);
    snapshot['entries'] = await _readSplitEntryCollection(
      _workspaceEntriesDirectory(userId, workspaceId),
      label: 'entries',
    );
    snapshot['baseEntries'] = await _readSplitEntryCollection(
      _workspaceBaseEntriesDirectory(userId, workspaceId),
      label: 'baseEntries',
    );

    return <String, dynamic>{
      'project': Map<String, dynamic>.from(rawProject),
      'snapshot': snapshot,
      'revision': revision,
    };
  }

  Future<Map<String, dynamic>?> _readSplitMeta(
    String userId,
    String workspaceId,
  ) async {
    final file = _workspaceMetaFile(userId, workspaceId);
    if (!await file.exists()) return null;
    return _readJsonObject(file, 'Workspace metadata');
  }

  String _readDocumentRevision(
    Map<String, dynamic> document,
    String workspaceId,
  ) {
    final revision = document['revision'];
    if (revision is! String || revision.isEmpty) {
      throw StateError('Stored Workspace revision is invalid: $workspaceId');
    }
    return revision;
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

  List<Map<String, dynamic>> _readProjects(Map<String, dynamic> catalog) {
    final raw = catalog['projects'];
    if (raw is! Iterable) {
      throw const FormatException('Workspace catalog projects are invalid.');
    }
    return raw.map((item) {
      if (item is! Map) {
        throw const FormatException('Workspace catalog project is invalid.');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: true);
  }

  String _readWorkspaceId(Map<String, dynamic> project) {
    final id = project['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Workspace project id is required.');
    }
    return id;
  }

  String _nextRevision(Object? current, String prefix) {
    if (current is! String || !current.startsWith(prefix)) {
      throw FormatException('Invalid $prefix revision: $current');
    }
    final number = int.tryParse(current.substring(prefix.length));
    if (number == null || number < 0) {
      throw FormatException('Invalid $prefix revision: $current');
    }
    return '$prefix${number + 1}';
  }

  Future<void> _writeCatalog(
    String userId,
    Map<String, dynamic> catalog,
  ) {
    return _writeJson(_catalogFile(userId), catalog);
  }

  Future<void> _writeDocument(
    String userId,
    String workspaceId,
    Map<String, dynamic> document,
  ) {
    return _writeSplitDocument(userId, workspaceId, document);
  }

  Future<void> _writeSplitDocument(
    String userId,
    String workspaceId,
    Map<String, dynamic> document,
  ) async {
    final rawProject = document['project'];
    final rawSnapshot = document['snapshot'];
    final revision = document['revision'];
    if (rawProject is! Map ||
        rawSnapshot is! Map ||
        revision is! String ||
        revision.isEmpty) {
      throw const FormatException('Workspace document is invalid.');
    }

    final snapshot = Map<String, dynamic>.from(rawSnapshot);
    final entries = _readSnapshotEntryRows(
      snapshot.remove('entries'),
      label: 'entries',
    );
    final baseEntries = _readSnapshotEntryRows(
      snapshot.remove('baseEntries'),
      label: 'baseEntries',
    );

    final target = _workspaceDirectory(userId, workspaceId);
    final temp = Directory(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final backup = Directory('${target.path}.bak');

    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
    if (await backup.exists()) {
      await backup.delete(recursive: true);
    }
    await temp.create(recursive: true);

    try {
      await _writeSplitEntryCollection(
        Directory('${temp.path}/entries'),
        entries,
      );
      await _writeSplitEntryCollection(
        Directory('${temp.path}/base-entries'),
        baseEntries,
      );
      await _writeJson(
        File('${temp.path}/meta.json'),
        <String, dynamic>{
          'project': Map<String, dynamic>.from(rawProject),
          'snapshot': snapshot,
          'revision': revision,
        },
      );

      var movedPrevious = false;
      if (await target.exists()) {
        await target.rename(backup.path);
        movedPrevious = true;
      }

      try {
        await temp.rename(target.path);
      } catch (_) {
        if (movedPrevious &&
            !await target.exists() &&
            await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }

      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }
      final legacy = _documentFile(userId, workspaceId);
      if (await legacy.exists()) {
        await legacy.delete();
      }
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<void> _writeSplitMeta(
    String userId,
    String workspaceId,
    Map<String, dynamic> meta,
  ) {
    return _writeJson(_workspaceMetaFile(userId, workspaceId), meta);
  }

  List<Map<String, dynamic>> _readSnapshotEntryRows(
    Object? value, {
    required String label,
  }) {
    // Older Workspace documents treated snapshot payloads as opaque and may
    // not have the v3 entries/baseEntries fields yet. Split storage keeps
    // those legacy snapshots valid by treating a missing collection as empty.
    if (value == null) return <Map<String, dynamic>>[];

    if (value is! Iterable) {
      throw FormatException('Workspace snapshot $label is invalid.');
    }

    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final raw in value) {
      if (raw is! Map) {
        throw FormatException('Workspace snapshot $label row is invalid.');
      }
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'];
      if (id is! String || id.isEmpty) {
        throw FormatException('Workspace snapshot $label id is invalid.');
      }
      if (!ids.add(id)) {
        throw FormatException('Workspace snapshot $label contains duplicate id: $id');
      }
      rows.add(row);
    }
    return rows;
  }

  Future<void> _writeSplitEntryCollection(
    Directory directory,
    List<Map<String, dynamic>> rows,
  ) async {
    await directory.create(recursive: true);
    const batchSize = 24;
    for (var start = 0; start < rows.length; start += batchSize) {
      final end = start + batchSize < rows.length
          ? start + batchSize
          : rows.length;
      await Future.wait(<Future<void>>[
        for (final row in rows.sublist(start, end))
          _writeJson(
            _entryFile(directory, row['id'] as String),
            row,
          ),
      ]);
    }
  }

  Future<List<Map<String, dynamic>>> _readSplitEntryCollection(
    Directory directory, {
    required String label,
  }) async {
    if (!await directory.exists()) return <Map<String, dynamic>>[];

    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    const batchSize = 24;
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < files.length; start += batchSize) {
      final end = start + batchSize < files.length
          ? start + batchSize
          : files.length;
      rows.addAll(
        await Future.wait<Map<String, dynamic>>(<Future<Map<String, dynamic>>>[
          for (final file in files.sublist(start, end))
            _readJsonObject(file, 'Workspace $label entry'),
        ]),
      );
    }

    rows.sort((a, b) {
      final aId = a['id'];
      final bId = b['id'];
      if (aId is! String || aId.isEmpty || bId is! String || bId.isEmpty) {
        throw FormatException('Workspace $label entry id is invalid.');
      }
      return aId.compareTo(bId);
    });
    return rows;
  }

  Future<void> _deleteDocument(String userId, String workspaceId) async {
    final directory = _workspaceDirectory(userId, workspaceId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }

    final legacy = _documentFile(userId, workspaceId);
    if (await legacy.exists()) {
      await legacy.delete();
    }
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

  File _catalogFile(String userId) =>
      File('${_userDirectory(userId).path}/catalog.json');

  File _documentFile(String userId, String workspaceId) => File(
        '${_userDirectory(userId).path}/documents/${_key(workspaceId)}.json',
      );

  Directory _workspaceDirectory(String userId, String workspaceId) => Directory(
        '${_userDirectory(userId).path}/workspaces/${_key(workspaceId)}',
      );

  File _workspaceMetaFile(String userId, String workspaceId) =>
      File('${_workspaceDirectory(userId, workspaceId).path}/meta.json');

  Directory _workspaceEntriesDirectory(String userId, String workspaceId) =>
      Directory('${_workspaceDirectory(userId, workspaceId).path}/entries');

  Directory _workspaceBaseEntriesDirectory(
    String userId,
    String workspaceId,
  ) =>
      Directory('${_workspaceDirectory(userId, workspaceId).path}/base-entries');

  File _entryFile(Directory directory, String entryId) =>
      File('${directory.path}/${_key(entryId)}.json');

  Directory _userDirectory(String userId) =>
      Directory('${root.path}/users/${_key(userId)}');

  String _key(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

class _WorkspaceEntryDelta {
  const _WorkspaceEntryDelta({
    required this.deleteIds,
    required this.upserts,
  });

  final Set<String> deleteIds;
  final Map<String, Map<String, dynamic>> upserts;
}

DateTime _utcNow() => DateTime.now().toUtc();
