import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// C2C 会话展示名合并：禁止用昵称盖掉已有备注（Store / existing）。
class ConversationC2cShowNamePrefer {
  ConversationC2cShowNamePrefer._();

  /// [storeName] 为 DisplayNameStore.c2c；非空时优先于会话行。
  static String preferC2cShowName({
    required String? existingShowName,
    required String? incomingShowName,
    required String? storeName,
  }) {
    final store = storeName?.trim() ?? '';
    final existing = existingShowName?.trim() ?? '';
    final incoming = incomingShowName?.trim() ?? '';

    if (store.isNotEmpty) {
      return store;
    }
    if (existing.isNotEmpty) {
      // Store 空时：已有行名优先，避免 SDK 昵称帧盖掉本地备注行。
      if (incoming.isEmpty || incoming == existing) {
        return existing;
      }
      // incoming 不同且 existing 非空：仍保 existing（禁降级）。
      return existing;
    }
    return incoming;
  }

  static String preferForConversationIds({
    required String conversationID,
    required String? userID,
    required String? existingShowName,
    required String? incomingShowName,
    required String? Function(String userId) readStore,
  }) {
    final id = conversationID.trim();
    final uid = ChatIdFormat.rawUserUid(
      (userID?.trim().isNotEmpty == true)
          ? userID
          : (id.startsWith('c2c_') ? id.substring(4) : ''),
    );
    if (!id.startsWith('c2c_') && uid.isEmpty) {
      final incoming = incomingShowName?.trim() ?? '';
      if (incoming.isNotEmpty) {
        return incoming;
      }
      return existingShowName?.trim() ?? '';
    }
    final store = uid.isEmpty ? '' : (readStore(uid)?.trim() ?? '');
    return preferC2cShowName(
      existingShowName: existingShowName,
      incomingShowName: incomingShowName,
      storeName: store,
    );
  }

  /// SDK 会话落库前的 C2C 展示名合并（Store → 本地备注 → 已有行 → incoming）。
  ///
  /// [remarkConfirmedEmpty] 为 true 表示本地已确认该好友无备注，此时允许
  /// incoming（新昵称）替换过期的 existing；否则一律保 existing，禁降级。
  static String preferC2cShowNameOnUpsert({
    required String? existingShowName,
    required String? incomingShowName,
    required String? storeName,
    required String? localRemark,
    required bool remarkConfirmedEmpty,
  }) {
    final store = storeName?.trim() ?? '';
    if (store.isNotEmpty) {
      return store;
    }
    final remark = localRemark?.trim() ?? '';
    if (remark.isNotEmpty) {
      return remark;
    }
    final existing = existingShowName?.trim() ?? '';
    final incoming = incomingShowName?.trim() ?? '';
    if (existing.isEmpty) {
      return incoming;
    }
    if (incoming.isEmpty || incoming == existing) {
      return existing;
    }
    if (remarkConfirmedEmpty) {
      return incoming;
    }
    return existing;
  }

  /// Store 为空时决定是否把会话 showName 写入 DisplayNameStore。
  ///
  /// 返回 null 表示不写（showName 疑似昵称且备注尚未确认为空）。
  static String? captureNameForStore({
    required String showName,
    required String? localRemark,
    required String? localNickname,
    required bool remarkConfirmedEmpty,
  }) {
    final remark = localRemark?.trim() ?? '';
    if (remark.isNotEmpty) {
      return remark;
    }
    final name = showName.trim();
    if (name.isEmpty) {
      return null;
    }
    final nick = localNickname?.trim() ?? '';
    if (nick.isNotEmpty && name == nick && !remarkConfirmedEmpty) {
      return null;
    }
    return name;
  }
}
