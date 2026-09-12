import 'dart:convert';
import 'dart:io';

import 'workspace_secret_store.dart';
import 'workspace_store.dart';

/// File-backed administrative view over Workspace users, projects and lessons.
///
/// Password hashes and session token hashes never leave this class. Public
/// account records returned to the admin UI contain identity and timestamps
/// only.
class WorkspaceAdminStore {
  WorkspaceAdminStore({
    required this.root,
    required this.workspaceStore,
    required this.secretStore,
  });

  final Directory root;
  final FileWorkspaceStore workspaceStore;
  final FileWorkspaceSecretStore secretStore;

  Future<List<Map<String, Object?>>> listUsers() async {
    final data = await _readAccounts();
    final now = DateTime.now().toUtc();
    final sessions = _objectList(data['sessions']);
    final users = _objectList(data['users']);

    return users.map((user) {
      final userId = user['userId']?.toString() ?? '';
      final activeSessions = sessions.where((session) {
        if (session['userId'] != userId) return false;
        final expiresAt = DateTime.tryParse(
          session['expiresAt']?.toString() ?? '',
        )?.toUtc();
        return expiresAt != null && expiresAt.isAfter(now);
      }).length;

      return <String, Object?>{
        'userId': userId,
        'username': user['username']?.toString() ?? '',
        'email': user['email']?.toString() ?? '',
        'createdAt': user['createdAt']?.toString(),
        'claimedAt': user['claimedAt']?.toString(),
        'activeSessions': activeSessions,
      };
    }).toList(growable: false)
      ..sort((a, b) =>
          (a['username']?.toString() ?? '').compareTo(
            b['username']?.toString() ?? '',
          ));
  }

  Future<bool> deleteUser(String userId) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return false;

    final data = await _readAccounts();
    final users = _objectList(data['users']);
    final sessions = _objectList(data['sessions']);
    final before = users.length;

    users.removeWhere((user) => user['userId'] == cleanUserId);
    if (users.length == before) return false;
    sessions.removeWhere((session) => session['userId'] == cleanUserId);

    data['users'] = users;
    data['sessions'] = sessions;
    await _writeJsonAtomic(_accountsFile, data);

    final userDirectory = _userDirectory(cleanUserId);
    if (await userDirectory.exists()) {
      await userDirectory.delete(recursive: true);
    }
    return true;
  }

  Future<List<Map<String, Object?>>> listProjects() async {
    final users = await listUsers();
    final projects = <Map<String, Object?>>[];

    for (final user in users) {
      final userId = user['userId']?.toString() ?? '';
      if (userId.isEmpty) continue;

      final catalog = await workspaceStore.loadCatalog(userId);
      final rawProjects = catalog['projects'];
      if (rawProjects is! Iterable) continue;

      for (final raw in rawProjects) {
        if (raw is! Map) continue;
        final project = Map<String, dynamic>.from(raw);
        projects.add(<String, Object?>{
          'owner': <String, Object?>{
            'userId': userId,
            'username': user['username'],
            'email': user['email'],
          },
          'project': project,
          'catalogRevision': catalog['revision']?.toString(),
        });
      }
    }

    return projects;
  }

  Future<bool> deleteProject({
    required String userId,
    required String workspaceId,
  }) async {
    final meta = await workspaceStore.loadWorkspaceMeta(userId, workspaceId);
    if (meta == null) return false;

    final revision = meta['revision'];
    if (revision is! String || revision.isEmpty) {
      throw StateError('Stored Workspace revision is invalid: $workspaceId');
    }

    await workspaceStore.deleteWorkspace(
      userId: userId,
      workspaceId: workspaceId,
      expectedRevision: revision,
    );
    await secretStore.deleteWorkspaceSecrets(
      userId: userId,
      workspaceId: workspaceId,
    );
    return true;
  }

  Future<Map<String, dynamic>?> loadLessonCatalog() async {
    final file = _lessonCatalogFile;
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Lesson catalog must be a JSON object.');
    }
    return _normalizeLessonCatalog(Map<String, dynamic>.from(decoded));
  }

  Future<bool> bootstrapLessonCatalog(Map<String, dynamic> catalog) async {
    final file = _lessonCatalogFile;
    if (await file.exists()) return false;
    await saveLessonCatalog(catalog);
    return true;
  }

  Future<Map<String, dynamic>> saveLessonCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final normalized = _normalizeLessonCatalog(catalog);
    normalized['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _writeJsonAtomic(_lessonCatalogFile, normalized);
    return normalized;
  }

  Map<String, dynamic> _normalizeLessonCatalog(Map<String, dynamic> catalog) {
    final projects = catalog['projects'];
    if (projects is! List) {
      throw const FormatException('Lesson catalog projects must be a JSON array.');
    }

    for (final project in projects) {
      if (project is! Map) {
        throw const FormatException('Lesson catalog project must be an object.');
      }
      if ((project['id']?.toString().trim() ?? '').isEmpty) {
        throw const FormatException('Lesson project id is required.');
      }
      if (project['lessons'] is! List) {
        throw const FormatException('Lesson project lessons must be an array.');
      }
    }

    return <String, dynamic>{
      ...catalog,
      'schemaVersion': catalog['schemaVersion'] ?? 1,
      'projects': projects,
    };
  }

  Future<Map<String, dynamic>> _readAccounts() async {
    if (!await _accountsFile.exists()) {
      return <String, dynamic>{
        'users': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
      };
    }

    final decoded = jsonDecode(await _accountsFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Workspace account store must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  List<Map<String, dynamic>> _objectList(Object? source) {
    if (source == null) return <Map<String, dynamic>>[];
    if (source is! Iterable) {
      throw const FormatException('Expected a JSON array.');
    }
    return source.map((item) {
      if (item is! Map) {
        throw const FormatException('Expected a JSON object entry.');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: true);
  }

  Future<void> _writeJsonAtomic(
    File file,
    Map<String, dynamic> value,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  File get _accountsFile => File('${root.path}/auth/accounts.json');

  File get _lessonCatalogFile =>
      File('${root.path}/admin/lesson_catalog.json');

  Directory _userDirectory(String userId) =>
      Directory('${root.path}/users/${_key(userId)}');

  String _key(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
