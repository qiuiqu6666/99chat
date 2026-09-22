import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

class DisplayNameChange {
  final String type;
  final String id;
  final String name;

  const DisplayNameChange({
    required this.type,
    required this.id,
    required this.name,
  });
}

class DisplayNameStore extends ChangeNotifier {
  DisplayNameStore._();

  static final DisplayNameStore instance = DisplayNameStore._();

  final Map<String, String> _c2c = <String, String>{};
  final Map<String, String> _group = <String, String>{};
  DisplayNameChange? _lastChange;

  DisplayNameChange? get lastChange => _lastChange;

  String? c2c(String userID) {
    final id = _rawC2cUserId(userID);
    final name = _c2c[id];
    if (name == null || name.isEmpty) {
      return null;
    }
    if (isRawUserIdDisplayName(id, name)) {
      return null;
    }
    return name;
  }

  String? group(String groupID) {
    final committed = GroupLocalStore.instance
            .readCached(groupId: groupID)
            ?.groupName
            .trim() ??
        '';
    return committed.isNotEmpty ? committed : _group[groupID.trim()];
  }

  /// 按调用方提供的等价比较查找群展示名（短码 / `@TGS#` / `group_` 前缀）。
  String? groupWhere(
    String groupID,
    bool Function(String storedId, String queryId) match,
  ) {
    final id = groupID.trim();
    if (id.isEmpty) {
      return null;
    }
    final direct = group(id);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    for (final entry in _group.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      if (match(entry.key, id)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 供 iOS VoIP 离线来电展示名缓存同步。
  Map<String, String> snapshotC2C() {
    final out = <String, String>{};
    for (final entry in _c2c.entries) {
      if (isRawUserIdDisplayName(entry.key, entry.value)) {
        continue;
      }
      out[entry.key] = entry.value;
    }
    return out;
  }

  /// 展示名是否其实就是 userID（含 `@` / `c2c_` 前缀形态）。
  static bool isRawUserIdDisplayName(String? userID, String? name) {
    final id = _canonicalUserId(userID);
    final label = _canonicalUserId(name);
    return id.isNotEmpty && id == label;
  }

  void setC2C(String userID, String name, {bool notify = true}) {
    final id = _rawC2cUserId(userID);
    if (id.isEmpty) {
      return;
    }
    if (isRawUserIdDisplayName(id, name)) {
      if (_c2c.containsKey(id)) {
        _set(_c2c, 'c2c', id, '', notify: notify);
      }
      return;
    }
    _set(_c2c, 'c2c', id, name, notify: notify);
  }

  void setGroup(String groupID, String name, {bool notify = true}) {
    final committed = GroupLocalStore.instance
            .readCached(groupId: groupID)
            ?.groupName
            .trim() ??
        '';
    _set(_group, 'group', groupID, committed.isNotEmpty ? committed : name,
        notify: notify);
  }

  /// 批量 `setC2C`/`setGroup`（`notify: false`）后一次性通知监听者。
  void notifyBatch() {
    notifyListeners();
  }

  /// IM 好友/公开资料写入 C2C 展示名：非空备注覆盖；空备注保留现有 Store（含空 Store）。
  /// 公开昵称不得占用 Store；昵称只在展示解析回退，或备注清空/自建好友灌名等明确写入。
  ///
  /// 返回 `true` 表示 Store 有写入。
  bool applyImFriendShowName({
    required String userID,
    required String imRemark,
    required String imNickName,
    bool notify = false,
  }) {
    final id = _rawC2cUserId(userID);
    if (id.isEmpty) {
      return false;
    }
    final next = resolveImSyncShowName(
      imRemark: imRemark,
      imNickName: imNickName,
      userID: id,
      existingStoreName: c2c(id),
    );
    if (next == null) {
      return false;
    }
    final prev = c2c(id)?.trim() ?? '';
    if (prev == next) {
      return false;
    }
    setC2C(id, next, notify: notify);
    return c2c(id) == next;
  }

  /// 纯决策：返回应写入的展示名；`null` 表示保留现有 Store（不降级）。
  @visibleForTesting
  static String? resolveImSyncShowName({
    required String imRemark,
    required String imNickName,
    required String userID,
    required String? existingStoreName,
  }) {
    final id = userID.trim();
    final remark = imRemark.trim();
    if (remark.isNotEmpty && !isRawUserIdDisplayName(id, remark)) {
      return remark;
    }
    return null;
  }

  /// 与 app 侧 ChatIdFormat.rawUserUid 对齐：去前导 @。
  static String _rawC2cUserId(String? input) {
    final trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('@')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  static String _canonicalUserId(String? input) {
    var text = _rawC2cUserId(input);
    if (text.length > 4 &&
        (text.startsWith('c2c_') || text.startsWith('C2C_'))) {
      text = text.substring(4);
    }
    return text;
  }

  /// 登出或切换账号时清空内存缓存，避免跨账号串数据。
  void clear({bool notify = true}) {
    if (_c2c.isEmpty && _group.isEmpty && _lastChange == null) {
      return;
    }
    _c2c.clear();
    _group.clear();
    _lastChange = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _set(
    Map<String, String> target,
    String type,
    String id,
    String name, {
    required bool notify,
  }) {
    final key = id.trim();
    final text = name.trim();
    if (key.isEmpty) {
      return;
    }
    if (text.isEmpty) {
      target.remove(key);
    } else {
      target[key] = text;
    }
    _lastChange = DisplayNameChange(type: type, id: key, name: text);
    if (notify) {
      notifyListeners();
    }
  }

  bool applyToConversation(V2TimConversation? conversation) {
    final conversationID = conversation?.conversationID?.trim() ?? '';
    if (conversation == null || conversationID.isEmpty) {
      return false;
    }
    String? name;
    if (conversationID.startsWith('c2c_')) {
      name = c2c(conversationID.substring(4));
    } else if (conversationID.startsWith('group_')) {
      name = group(conversationID.substring(6));
    }
    if (name == null || name.isEmpty || conversation.showName == name) {
      return false;
    }
    conversation.showName = name;
    return true;
  }
}
