import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

const workspaceSecretContexts = <String>{
  'runner',
  'git',
  'deploy',
};

class FileWorkspaceSecretStore {
  FileWorkspaceSecretStore(
    this.root, {
    required List<int> masterKey,
    DateTime Function()? clock,
  })  : _masterKey = SecretKey(List<int>.unmodifiable(masterKey)),
        _clock = clock ?? _utcNow {
    if (masterKey.length != 32) {
      throw ArgumentError.value(
        masterKey.length,
        'masterKey',
        'Workspace secret master key must contain exactly 32 bytes.',
      );
    }
  }

  final Directory root;
  final SecretKey _masterKey;
  final DateTime Function() _clock;
  final AesGcm _cipher = AesGcm.with256bits();

  static List<int> decodeMasterKey(String encoded) {
    final source = encoded.trim();
    if (source.isEmpty) {
      throw const FormatException('Workspace secret master key is empty.');
    }
    try {
      final bytes = base64Url.decode(base64Url.normalize(source));
      if (bytes.length != 32) {
        throw const FormatException(
          'Workspace secret master key must decode to exactly 32 bytes.',
        );
      }
      return bytes;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'WORKSPACE_SECRET_MASTER_KEY must be base64url encoded.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> listSecrets({
    required String userId,
    required String workspaceId,
  }) async {
    final directory = _workspaceSecretDirectory(userId, workspaceId);
    if (!await directory.exists()) return <Map<String, dynamic>>[];

    final metadata = <Map<String, dynamic>>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final record = await _readRecord(entity);
      metadata.add(_metadataFromRecord(record));
    }
    metadata.sort(
      (a, b) => (a['name'] as String).compareTo(b['name'] as String),
    );
    return metadata;
  }

  Future<Map<String, dynamic>> putSecret({
    required String userId,
    required String workspaceId,
    required String name,
    required String value,
    required Set<String> contexts,
  }) async {
    final normalizedName = _validateName(name);
    final normalizedValue = _validateValue(value);
    final normalizedContexts = _validateContexts(contexts);
    final file = _secretFile(userId, workspaceId, normalizedName);
    final now = _clock().toUtc();

    DateTime createdAt = now;
    if (await file.exists()) {
      final current = await _readRecord(file);
      final source = current['createdAt'];
      if (source is String) {
        createdAt = DateTime.tryParse(source)?.toUtc() ?? now;
      }
    }

    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(normalizedValue),
      secretKey: _masterKey,
      nonce: nonce,
      aad: _aad(userId, workspaceId, normalizedName),
    );

    final record = <String, dynamic>{
      'name': normalizedName,
      'contexts': normalizedContexts.toList()..sort(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'algorithm': 'aes-gcm-256',
      'nonce': base64Url.encode(box.nonce),
      'cipherText': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    };
    await _writeJson(file, record);
    return _metadataFromRecord(record);
  }

  Future<bool> deleteSecret({
    required String userId,
    required String workspaceId,
    required String name,
  }) async {
    final file = _secretFile(userId, workspaceId, _validateName(name));
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  Future<void> deleteWorkspaceSecrets({
    required String userId,
    required String workspaceId,
  }) async {
    final directory = _workspaceSecretDirectory(userId, workspaceId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> retainWorkspaces({
    required String userId,
    required Set<String> workspaceIds,
  }) async {
    final rootDirectory = _userSecretsDirectory(userId);
    if (!await rootDirectory.exists()) return;

    final validKeys = workspaceIds.map(_key).toSet();
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is Directory && !validKeys.contains(_basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// Trusted server-side resolution point for future Runner/Git integration.
  /// This method is deliberately not exposed by the public HTTP API.
  Future<String> resolveForTrustedExecution({
    required String userId,
    required String workspaceId,
    required String name,
    required String context,
  }) async {
    final normalizedName = _validateName(name);
    final normalizedContext = _validateContext(context);
    final file = _secretFile(userId, workspaceId, normalizedName);
    if (!await file.exists()) {
      throw StateError('Workspace secret does not exist: $normalizedName');
    }

    final record = await _readRecord(file);
    final contexts = _contextsFromRecord(record);
    if (!contexts.contains(normalizedContext)) {
      throw StateError(
        'Workspace secret $normalizedName is not allowed for $normalizedContext.',
      );
    }

    if (record['algorithm'] != 'aes-gcm-256') {
      throw const FormatException('Unsupported Workspace secret algorithm.');
    }
    try {
      final nonce = base64Url.decode(base64Url.normalize(record['nonce'] as String));
      final cipherText = base64Url.decode(
        base64Url.normalize(record['cipherText'] as String),
      );
      final mac = base64Url.decode(base64Url.normalize(record['mac'] as String));
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: _masterKey,
        aad: _aad(userId, workspaceId, normalizedName),
      );
      return utf8.decode(clearText);
    } catch (_) {
      throw const FormatException(
        'Workspace secret could not be decrypted with the configured master key.',
      );
    }
  }

  Map<String, dynamic> _metadataFromRecord(Map<String, dynamic> record) =>
      <String, dynamic>{
        'name': record['name'],
        'contexts': _contextsFromRecord(record).toList()..sort(),
        'createdAt': record['createdAt'],
        'updatedAt': record['updatedAt'],
      };

  Set<String> _contextsFromRecord(Map<String, dynamic> record) {
    final raw = record['contexts'];
    if (raw is! Iterable) {
      throw const FormatException('Workspace secret contexts are invalid.');
    }
    return _validateContexts(raw.map((item) {
      if (item is! String) {
        throw const FormatException('Workspace secret context is invalid.');
      }
      return item;
    }).toSet());
  }

  Future<Map<String, dynamic>> _readRecord(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Workspace secret record must be an object.');
    }
    final record = Map<String, dynamic>.from(decoded);
    if (record['name'] is! String ||
        record['createdAt'] is! String ||
        record['updatedAt'] is! String ||
        record['nonce'] is! String ||
        record['cipherText'] is! String ||
        record['mac'] is! String) {
      throw const FormatException('Workspace secret record is invalid.');
    }
    return record;
  }

  Future<void> _writeJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  List<int> _aad(String userId, String workspaceId, String name) =>
      utf8.encode('workspace-secret:v1:$userId:$workspaceId:$name');

  String _validateName(String value) {
    final source = value.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(source)) {
      throw const FormatException(
        'Secret name must be an environment-style identifier up to 64 characters.',
      );
    }
    return source;
  }

  String _validateValue(String value) {
    if (value.isEmpty) {
      throw const FormatException('Workspace secret value cannot be empty.');
    }
    if (utf8.encode(value).length > 65536) {
      throw const FormatException(
        'Workspace secret value must be 64 KiB or smaller.',
      );
    }
    return value;
  }

  Set<String> _validateContexts(Set<String> contexts) {
    if (contexts.isEmpty) {
      throw const FormatException(
        'Workspace secret must allow at least one execution context.',
      );
    }
    return contexts.map(_validateContext).toSet();
  }

  String _validateContext(String value) {
    final source = value.trim();
    if (!workspaceSecretContexts.contains(source)) {
      throw FormatException('Unsupported Workspace secret context: $source');
    }
    return source;
  }

  Directory _userSecretsDirectory(String userId) =>
      Directory('${root.path}/users/${_key(userId)}/secrets');

  Directory _workspaceSecretDirectory(String userId, String workspaceId) =>
      Directory('${_userSecretsDirectory(userId).path}/${_key(workspaceId)}');

  File _secretFile(String userId, String workspaceId, String name) => File(
        '${_workspaceSecretDirectory(userId, workspaceId).path}/${_key(name)}.json',
      );

  String _key(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}

DateTime _utcNow() => DateTime.now().toUtc();
