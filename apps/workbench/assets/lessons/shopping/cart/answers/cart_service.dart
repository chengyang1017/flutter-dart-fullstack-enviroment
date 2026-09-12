import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';

/// 购物车数据服务的抽象接口。
///
/// 定义了购物车数据的加载、保存和清除操作，不关心具体存储实现。
/// 业务层（如购物车页面、结算页面）应依赖此接口，以便于单元测试和将来切换存储方案。
abstract class CartService {
  /// 从持久化存储中加载购物车商品列表。
  ///
  /// 返回 [Future] 包装的 [List<CartItem>]。
  /// 若无数据或数据损坏，应返回空列表（而不是抛出异常）。
  Future<List<CartItem>> loadItems();

  /// 将购物车商品列表保存到持久化存储。
  ///
  /// 传入的 [items] 应为完整列表（非增量），每次保存会完全覆盖旧数据。
  Future<void> saveItems(List<CartItem> items);

  /// 清除购物车所有数据（例如用户退出登录或手动清空）。
  Future<void> clear();
}

/// 基于 [SharedPreferences] 的本地购物车服务实现。
///
/// 使用键值对存储，数据以 JSON 字符串形式序列化。
/// 采用 [SharedPreferencesAsync]（异步版本）以避免阻塞 UI 线程。
class LocalCartService implements CartService {
  /// 存储购物车数据的键名。
  ///
  /// 加入 `_v1` 后缀，便于未来数据迁移（如更换序列化格式时可增加版本号）。
  static const String _cartKey = 'shopping_cart_items_v1';

  /// 底层 [SharedPreferencesAsync] 实例。
  ///
  /// 通过构造函数注入，便于测试时传入 mock 实现。
  final SharedPreferencesAsync _preferences;

  /// 构造函数，可注入自定义 [SharedPreferencesAsync] 实例。
  ///
  /// 若未传入，则使用默认构造 `SharedPreferencesAsync()`。
  LocalCartService({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  /// 从本地存储加载购物车数据。
  ///
  /// 流程：
  /// 1. 通过键名读取字符串。
  /// 2. 若为空或不存在，返回空列表。
  /// 3. 将 JSON 字符串解析为 List，并逐项转换为 [CartItem] 对象。
  /// 4. 若解析过程中发生任何异常（包括类型错误或 JSON 格式错误），
  ///    则认为数据已损坏，删除损坏的键，并返回空列表，保证应用不会因数据问题崩溃。
  @override
  Future<List<CartItem>> loadItems() async {
    // 1. 从 SharedPreferences 中异步获取原始 JSON 字符串
    final rawData = await _preferences.getString(_cartKey);

    // 2. 若无数据或字符串为空，直接返回空列表
    if (rawData == null || rawData.isEmpty) {
      return const [];
    }

    try {
      // 3. 解码 JSON 字符串
      final decoded = jsonDecode(rawData);

      // 4. 确保根类型是 List，否则视为数据损坏
      if (decoded is! List) {
        return const [];
      }

      // 5. 将每个元素转换为 Map，再用 CartItem.fromJson 构造实体
      //    使用 growable: false 生成固定长度列表，提升性能并减少内存占用
      return decoded
          .map(
            (item) => CartItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    } catch (_) {
      // 6. 任何异常（如类型转换失败、字段缺失等）都视为数据损坏
      //    为避免应用反复出错，直接删除该键（相当于重置购物车）
      await _preferences.remove(_cartKey);

      // 返回空列表，让业务层表现如无数据一样
      return const [];
    }
  }

  /// 保存购物车商品列表到本地存储。
  ///
  /// 将列表序列化为 JSON 数组字符串，然后通过 [SharedPreferences] 写入。
  /// 若 [items] 为空，会存储 `"[]"`，不会删除键，以保证一致性。
  @override
  Future<void> saveItems(List<CartItem> items) async {
    // 1. 将每个 CartItem 转为 Map 并放入 List
    final encoded = jsonEncode(
      items.map((item) => item.toJson()).toList(growable: false),
    );

    // 2. 异步写入 SharedPreferences
    await _preferences.setString(_cartKey, encoded);
  }

  /// 清除购物车数据。
  ///
  /// 直接删除存储键，与 loadItems 返回空列表的效果一致。
  /// 此操作不可逆，调用前需确保业务逻辑已确认（如用户主动清空）。
  @override
  Future<void> clear() async {
    await _preferences.remove(_cartKey);
  }
}