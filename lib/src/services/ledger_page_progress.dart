import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resume page-number APIs only while the first-page identity is unchanged.
/// A new head invalidates the position, avoiding gaps from offset drift.
class LedgerPageProgress {
  static String _prefix(String owner) =>
      'ledger_page_v1.${Uri.encodeComponent(owner)}.';
  static String _key(String owner, String scope, int size) =>
      '${_prefix(owner)}${sha256.convert(utf8.encode('$size:$scope'))}';
  static String fingerprint(Iterable<String> ids) =>
      sha256.convert(utf8.encode(jsonEncode(ids.toList()))).toString();

  static Future<int> read(
      {required String owner,
      required String scope,
      required int size,
      required String head}) async {
    if (owner.isEmpty) return 1;
    final prefs = await SharedPreferences.getInstance();
    try {
      final value =
          jsonDecode(prefs.getString(_key(owner, scope, size)) ?? '{}');
      if (value['head'] == head && value['next'] is int && value['next'] >= 1) {
        return value['next'] as int;
      }
    } catch (_) {/* A corrupt checkpoint safely restarts at page 1. */}
    return 1;
  }

  static Future<void> save(
      {required String owner,
      required String scope,
      required int size,
      required String head,
      required int next}) async {
    if (owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(owner, scope, size), jsonEncode({'head': head, 'next': next}));
  }

  static Future<void> clear(String owner) async {
    if (owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix(owner)))
        .toList()) {
      await prefs.remove(key);
    }
  }
}
