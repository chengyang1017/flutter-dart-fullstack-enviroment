import 'package:hive/hive.dart';

class WorkspaceAuthSessionStore {
  WorkspaceAuthSessionStore._();

  static const boxName = 'workspace_auth';
  static const _tokenKey = 'accessToken';
  static const _cacheUserIdKey = 'cacheUserId';

  static Future<void> openBox() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<dynamic>(boxName);
    }
  }

  static Box<dynamic> get _box {
    if (!Hive.isBoxOpen(boxName)) {
      throw StateError('Workspace auth box is not open.');
    }
    return Hive.box<dynamic>(boxName);
  }

  static String? get accessToken {
    final value = _box.get(_tokenKey);
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static String? get cacheUserId {
    final value = _box.get(_cacheUserIdKey);
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static Future<void> saveAccessToken(String accessToken) async {
    await _box.put(_tokenKey, accessToken.trim());
  }

  static Future<void> bindCacheToUser(String userId) async {
    await _box.put(_cacheUserIdKey, userId.trim());
  }

  static Future<void> clearAccessToken() => _box.delete(_tokenKey);

  static Future<void> clearAll() => _box.clear();
}
