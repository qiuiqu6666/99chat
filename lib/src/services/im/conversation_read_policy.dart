/// SDK 8.9.7545 conversation-clean boundaries differ from per-message visibility.
class ConversationReadPolicy {
  static int conservativeTimestamp(int raw) {
    final seconds = raw > 9999999999 ? raw ~/ 1000 : raw;
    // Inclusive seconds cannot distinguish visible M1 from unseen M2 at T.
    // Zero is an all-unread command, so callers must defer nonpositive values.
    return seconds > 1 ? seconds - 1 : 0;
  }

  static bool validTarget(String id, int timestamp, int sequence,
      {bool explicitTypeClear = false,
      bool explicitConversationClear = false}) {
    if (id == 'c2c' || id == 'group') return explicitTypeClear;
    final clearCurrent =
        explicitConversationClear && timestamp == 0 && sequence == 0;
    if (id.startsWith('c2c_') && id.substring(4).trim().isNotEmpty) {
      return clearCurrent || (timestamp > 0 && sequence == 0);
    }
    if (id.startsWith('group_') && id.substring(6).trim().isNotEmpty) {
      return clearCurrent || (sequence > 0 && timestamp == 0);
    }
    return false;
  }

  /// Reasons are persisted, without message contents or provider descriptions.
  static String failureReason(int code) {
    if (code == -10113) return 'transient:sdk_frequency_block';
    if ({6017, 6027, 7003, 7013, 7014, 10004, 10007, 10010}.contains(code)) {
      return 'blocked:sdk_$code';
    }
    if ({6005, 6019, 6022}.contains(code)) return 'blocked:storage_$code';
    if ({6012, 6015, 6200, 6201, 7008, 10002}.contains(code))
      return 'transient:sdk_$code';
    return 'reconnect:sdk_$code';
  }
}
