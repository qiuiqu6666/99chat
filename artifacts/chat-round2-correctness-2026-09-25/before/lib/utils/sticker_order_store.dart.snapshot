import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';

/// 单个表情的本机排序，按账号隔离；服务端尚无单表情排序接口。
class StickerOrderStore {
  StickerOrderStore._();
  static final instance = StickerOrderStore._();

  final _orders = <String, List<String>>{};
  Future<void> _pending = Future<void>.value();

  String get currentOwner => ContactSocialCacheStore.safeLoginUserId().trim();
  String _key(String owner) =>
      'sticker_item_order_v1_${Uri.encodeComponent(owner)}';

  Future<void> load(String owner) async {
    if (owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _orders.putIfAbsent(owner, () => prefs.getStringList(_key(owner)) ?? []);
  }

  Future<void> save(String owner, List<String> ids) {
    if (owner.isEmpty) return Future<void>.value();
    final order = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final task = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_key(owner), order)) {
        throw StateError('Unable to save sticker order');
      }
      _orders[owner] = order;
    });
    _pending = task.catchError((Object _) {});
    return task;
  }

  List<StickerItem> apply(List<StickerItem> items, {String? owner}) {
    final order = _orders[owner ?? currentOwner] ?? const <String>[];
    if (order.isEmpty) return items;
    final byId = {for (final item in items) item.stickerId.trim(): item};
    final result = <StickerItem>[];
    for (final id in order) {
      final item = byId.remove(id);
      if (item != null) result.add(item);
    }
    // 新添加的表情保留默认相对顺序，放在已整理表情之后。
    result.addAll(byId.values);
    return result;
  }
}
