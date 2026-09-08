import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'workspace_authenticator.dart';

class WorkspaceAccountConflict implements Exception {
  const WorkspaceAccountConflict(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'WorkspaceAccountConflict($code, $message)';
}

class WorkspaceCredentialsRejected implements Exception {
  const WorkspaceCredentialsRejected();

  @override
  String toString() => 'WorkspaceCredentialsRejected';
}

class WorkspaceAuthenticatedSession {
  const WorkspaceAuthenticatedSession({
    required this.principal,
    required this.email,
    required this.accessToken,
  });

  final WorkspacePrincipal principal;
  final String email;
  final String accessToken;

  Map<String, Object?> toJson() => <String, Object?>{
        'accessToken': accessToken,
        'user': <String, Object?>{
          'userId': principal.userId,
          'username': principal.username,
          'email': email,
        },
      };
}

/// Persistent email/password accounts and opaque bearer sessions.
///
/// Passwords are stored only as PBKDF2-HMAC-SHA256 hashes with unique salts.
/// Session tokens are returned to the client once; only SHA-256 token hashes
/// are persisted on disk.
class FileWorkspaceAccountStore extends WorkspaceAuthenticator {
  FileWorkspaceAccountStore(
    this.root, {
    this.sessionTtl = const Duration(days: 30),
    this.passwordIterations = 210000,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? _utcNow {
    if (sessionTtl <= Duration.zero) {
      throw ArgumentError.value(
        sessionTtl,
        'sessionTtl',
        'Session TTL must be greater than zero.',
      );
    }
    if (passwordIterations < 100000) {
      throw ArgumentError.value(
        passwordIterations,
        'passwordIterations',
        'PBKDF2 iterations must be at least 100000.',
      );
    }
  }

  final Directory root;
  final Duration sessionTtl;
  final int passwordIterations;
  final Random _random;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  Pbkdf2 get _passwordAlgorithm => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: passwordIterations,
        bits: 256,
      );

  Future<WorkspaceAuthenticatedSession> register({
    required String username,
    required String email,
    required String password,
  }) {
    return _serialized(() async {
      final cleanUsername = _normalizeUsername(username);
      final cleanEmail = _normalizeEmail(email);
      _validatePassword(password);

      final data = await _readData();
      final users = _users(data);
      if (users.any((user) => user['username'] == cleanUsername)) {
        throw const WorkspaceAccountConflict(
          'username_taken',
          'Username is already in use.',
        );
      }
      if (users.any((user) => user['email'] == cleanEmail)) {
        throw const WorkspaceAccountConflict(
          'email_taken',
          'Email is already registered.',
        );
      }

      final salt = _randomBytes(16);
      final passwordHash = await _derivePassword(password, salt);
      final userId = 'usr_${_randomToken(16)}';
      final now = _clock().toUtc();
      final user = <String, dynamic>{
        'userId': userId,
        'username': cleanUsername,
        'email': cleanEmail,
        'passwordSalt': base64UrlEncode(salt),
        'passwordHash': base64UrlEncode(passwordHash),
        'passwordIterations': passwordIterations,
        'createdAt': now.toIso8601String(),
      };
      users.add(user);

      final issued = await _issueSession(
        data: data,
        user: user,
        now: now,
      );
      await _writeData(data);
      return issued;
    });
  }

  /// Converts a pre-existing static development identity into a normal
  /// email/password account without changing its stable user id or username.
  /// Existing Workspace ownership therefore remains untouched.
  Future<WorkspaceAuthenticatedSession> claimExistingIdentity({
    required WorkspacePrincipal principal,
    required String email,
    required String password,
  }) {
    return _serialized(() async {
      final cleanUserId = principal.userId.trim();
      if (cleanUserId.isEmpty) {
        throw const FormatException('Existing Workspace user id is required.');
      }
      final cleanUsername = _normalizeUsername(principal.username);
      final cleanEmail = _normalizeEmail(email);
      _validatePassword(password);

      final data = await _readData();
      final users = _users(data);
      if (users.any((user) => user['userId'] == cleanUserId)) {
        throw const WorkspaceAccountConflict(
          'account_already_claimed',
          'This Workspace account already has login credentials.',
        );
      }
      if (users.any((user) => user['username'] == cleanUsername)) {
        throw const WorkspaceAccountConflict(
          'username_taken',
          'Username is already in use.',
        );
      }
      if (users.any((user) => user['email'] == cleanEmail)) {
        throw const WorkspaceAccountConflict(
          'email_taken',
          'Email is already registered.',
        );
      }

      final salt = _randomBytes(16);
      final passwordHash = await _derivePassword(password, salt);
      final now = _clock().toUtc();
      final user = <String, dynamic>{
        'userId': cleanUserId,
        'username': cleanUsername,
        'email': cleanEmail,
        'passwordSalt': base64UrlEncode(salt),
        'passwordHash': base64UrlEncode(passwordHash),
        'passwordIterations': passwordIterations,
        'createdAt': now.toIso8601String(),
        'claimedAt': now.toIso8601String(),
      };
      users.add(user);

      final issued = await _issueSession(
        data: data,
        user: user,
        now: now,
      );
      await _writeData(data);
      return issued;
    });
  }

  Future<WorkspaceAuthenticatedSession> login({
    required String email,
    required String password,
  }) {
    return _serialized(() async {
      final cleanEmail = _normalizeEmail(email);
      if (password.isEmpty) throw const WorkspaceCredentialsRejected();

      final data = await _readData();
      final users = _users(data);
      Map<String, dynamic>? user;
      for (final candidate in users) {
        if (candidate['email'] == cleanEmail) {
          user = candidate;
          break;
        }
      }
      if (user == null) throw const WorkspaceCredentialsRejected();

      final saltSource = user['passwordSalt'];
      final hashSource = user['passwordHash'];
      final iterationsSource = user['passwordIterations'];
      if (saltSource is! String ||
          hashSource is! String ||
          iterationsSource is! int) {
        throw StateError('Stored Workspace account password metadata is invalid.');
      }

      final salt = base64Url.decode(base64Url.normalize(saltSource));
      final expected = base64Url.decode(base64Url.normalize(hashSource));
      final actual = await _derivePassword(
        password,
        salt,
        iterations: iterationsSource,
      );
      if (!_constantTimeEquals(expected, actual)) {
        throw const WorkspaceCredentialsRejected();
      }

      final issued = await _issueSession(
        data: data,
        user: user,
        now: _clock().toUtc(),
      );
      await _writeData(data);
      return issued;
    });
  }

  Future<bool> logoutToken(String token) {
    return _serialized(() async {
      if (token.trim().isEmpty) return false;
      final data = await _readData();
      final sessions = _sessions(data);
      _pruneExpiredSessions(sessions, _clock().toUtc());
      final tokenHash = await _hashToken(token.trim());
      final before = sessions.length;
      sessions.removeWhere((session) => session['tokenHash'] == tokenHash);
      if (sessions.length == before) return false;
      await _writeData(data);
      return true;
    });
  }

  Future<WorkspacePrincipal?> principalForToken(String token) {
    return _serialized(() async {
      if (token.trim().isEmpty) return null;
      final data = await _readData();
      final sessions = _sessions(data);
      final now = _clock().toUtc();
      final changed = _pruneExpiredSessions(sessions, now);
      final tokenHash = await _hashToken(token.trim());

      Map<String, dynamic>? matched;
      for (final session in sessions) {
        if (session['tokenHash'] == tokenHash) {
          matched = session;
          break;
        }
      }
      if (changed) await _writeData(data);
      if (matched == null) return null;

      final userId = matched['userId'];
      if (userId is! String || userId.isEmpty) return null;
      for (final user in _users(data)) {
        if (user['userId'] != userId) continue;
        final username = user['username'];
        if (username is! String || username.isEmpty) return null;
        return WorkspacePrincipal(userId: userId, username: username);
      }
      return null;
    });
  }

  @override
  Future<String?> authenticate(HttpRequest request) async {
    return (await authenticatePrincipal(request))?.userId;
  }

  @override
  Future<WorkspacePrincipal?> authenticatePrincipal(HttpRequest request) async {
    final token = workspaceBearerToken(request);
    if (token == null) return null;
    return principalForToken(token);
  }

  Future<WorkspaceAuthenticatedSession> _issueSession({
    required Map<String, dynamic> data,
    required Map<String, dynamic> user,
    required DateTime now,
  }) async {
    final userId = user['userId'];
    final username = user['username'];
    final email = user['email'];
    if (userId is! String ||
        username is! String ||
        email is! String ||
        userId.isEmpty ||
        username.isEmpty ||
        email.isEmpty) {
      throw StateError('Stored Workspace account identity is invalid.');
    }

    final token = _randomToken(32);
    final sessions = _sessions(data);
    _pruneExpiredSessions(sessions, now);
    sessions.add(<String, dynamic>{
      'tokenHash': await _hashToken(token),
      'userId': userId,
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(sessionTtl).toIso8601String(),
    });

    return WorkspaceAuthenticatedSession(
      principal: WorkspacePrincipal(userId: userId, username: username),
      email: email,
      accessToken: token,
    );
  }

  Future<List<int>> _derivePassword(
    String password,
    List<int> salt, {
    int? iterations,
  }) async {
    final algorithm = iterations == null || iterations == passwordIterations
        ? _passwordAlgorithm
        : Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations,
            bits: 256,
          );
    final derived = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return derived.extractBytes();
  }

  Future<String> _hashToken(String token) async {
    final hash = await Sha256().hash(utf8.encode(token));
    return base64UrlEncode(hash.bytes);
  }

  String _normalizeUsername(String value) {
    final username = value.trim().toLowerCase();
    if (!_usernamePattern.hasMatch(username)) {
      throw const FormatException(
        'Username must use lowercase letters, numbers, or hyphens and be at most 39 characters.',
      );
    }
    return username;
  }

  String _normalizeEmail(String value) {
    final email = value.trim().toLowerCase();
    if (email.length > 320 || !_emailPattern.hasMatch(email)) {
      throw const FormatException('A valid email address is required.');
    }
    return email;
  }

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw const FormatException('Password must contain at least 8 characters.');
    }
    if (password.length > 1024) {
      throw const FormatException('Password is too long.');
    }
  }

  bool _pruneExpiredSessions(
    List<Map<String, dynamic>> sessions,
    DateTime now,
  ) {
    final before = sessions.length;
    sessions.removeWhere((session) {
      final source = session['expiresAt'];
      if (source is! String) return true;
      final expiresAt = DateTime.tryParse(source)?.toUtc();
      return expiresAt == null || !expiresAt.isAfter(now);
    });
    return sessions.length != before;
  }

  Future<Map<String, dynamic>> _readData() async {
    final file = _accountsFile;
    if (!await file.exists()) {
      return <String, dynamic>{
        'users': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
      };
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Workspace account store must be a JSON object.');
    }
    final data = Map<String, dynamic>.from(decoded);
    _users(data);
    _sessions(data);
    return data;
  }

  List<Map<String, dynamic>> _users(Map<String, dynamic> data) {
    return _objectList(data, 'users');
  }

  List<Map<String, dynamic>> _sessions(Map<String, dynamic> data) {
    return _objectList(data, 'sessions');
  }

  List<Map<String, dynamic>> _objectList(
    Map<String, dynamic> data,
    String key,
  ) {
    final source = data[key];
    if (source == null) {
      final created = <Map<String, dynamic>>[];
      data[key] = created;
      return created;
    }
    if (source is! List) {
      throw FormatException('Workspace account $key must be a JSON array.');
    }
    final normalized = source.map((item) {
      if (item is! Map) {
        throw FormatException('Workspace account $key entry must be an object.');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: true);
    data[key] = normalized;
    return normalized;
  }

  Future<void> _writeData(Map<String, dynamic> data) async {
    final file = _accountsFile;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  File get _accountsFile => File('${root.path}/auth/accounts.json');

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  String _randomToken(int byteLength) =>
      base64UrlEncode(_randomBytes(byteLength)).replaceAll('=', '');
}

final RegExp _usernamePattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,38})$');
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool _constantTimeEquals(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  final length = min(a.length, b.length);
  for (var index = 0; index < length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference == 0;
}

DateTime _utcNow() => DateTime.now().toUtc();
