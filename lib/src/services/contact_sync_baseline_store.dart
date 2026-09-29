import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contact_social_cache_store.dart';
import 'contact_sync_transaction.dart';

class ContactSyncBaselineStore {
  static Future<void> _tail = Future<void>.value();
  static String _prefix(String owner) =>
      'device_sync_contact_baseline_v2_${ContactSocialCacheStore.accountScopeForUserId(owner)}_';
  static String _key(String owner, String device) =>
      '${_prefix(owner)}${sha256.convert(utf8.encode(device))}';

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<ContactSyncBaseline?> read(String owner, String device) async {
    await _tail;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(owner, device));
    if (raw == null) return null;
    try {
      final baseline = ContactSyncBaseline.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return baseline?.ownerUserId == owner && baseline?.deviceId == device
          ? baseline
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    ContactSyncBaseline baseline, {
    required bool Function() isCurrent,
  }) =>
      _serialized(() async {
        if (!isCurrent()) return;
        final prefs = await SharedPreferences.getInstance();
        if (!isCurrent()) return;
        final saved = await prefs.setString(
            _key(baseline.ownerUserId, baseline.deviceId),
            jsonEncode(baseline.toJson()));
        if (!saved) throw StateError('contact_baseline_write_failed');
      });

  Future<void> clearOwner(String owner) => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        for (final key
            in prefs.getKeys().where((key) => key.startsWith(_prefix(owner)))) {
          await prefs.remove(key);
        }
      });
}
