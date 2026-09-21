import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'wallet_order.dart';

class WalletPendingStore {
  static final Map<String, WalletOrderDraft> _items = {};
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _key = 'wallet_pending_orders_v2';
  static const int _maxItems = 50;
  static bool _loaded = false;
  static Future<void> _writeChain = Future<void>.value();
  static Completer<void>? _pendingSave;

  /// Only records explicitly owned by the active account can be observed.
  /// Legacy records without an owner remain quarantined rather than being
  /// adopted by the next account that happens to log in.
  List<WalletOrderDraft> get all {
    final owner = _currentOwner();
    if (owner.isEmpty) return const <WalletOrderDraft>[];
    return _items.values
        .where((item) => item.ownerUserId == owner)
        .toList(growable: false);
  }

  Future<List<WalletOrderDraft>> load() async {
    if (_loaded) return all;

    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.trim().isEmpty) {
        _loaded = true;
        return all;
      }

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _items
          ..clear()
          ..addEntries(
            decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .map(WalletOrderDraft.fromJson)
                .where((e) => e.clientOrderId.isNotEmpty)
                .map((e) => MapEntry(_itemKey(e), e)),
          );
        for (final owner in _items.values
            .map((item) => item.ownerUserId)
            .where((owner) => owner.isNotEmpty)
            .toSet()) {
          _trimIfNeeded(owner);
        }
      }
    } catch (_) {
      _items.clear();
    }

    _loaded = true;
    return all;
  }

  Future<void> put(WalletOrderDraft item) async {
    if (item.clientOrderId.trim().isEmpty) return;
    await load();
    final owner = _currentOwner();
    if (owner.isEmpty ||
        (item.ownerUserId.isNotEmpty && item.ownerUserId != owner)) {
      return;
    }
    final scoped = item.ownerUserId == owner
        ? item
        : item.copyWith(ownerUserId: owner);
    _items[_itemKey(scoped)] = scoped;
    _trimIfNeeded(owner);
    await _queueSave();
  }

  Future<void> remove(String clientOrderId) async {
    if (clientOrderId.trim().isEmpty) return;
    await load();
    final owner = _currentOwner();
    if (owner.isEmpty) return;
    _items.remove(_itemKeyFor(owner, clientOrderId));
    await _queueSave();
  }

  Future<void> clear() async {
    await load();
    final owner = _currentOwner();
    if (owner.isEmpty) return;
    _items.removeWhere((_, item) => item.ownerUserId == owner);
    await _queueSave();
  }

  Future<void> _queueSave() {
    final existing = _pendingSave;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _pendingSave = completer;

    _writeChain = _writeChain.catchError((_) {}).then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final c = _pendingSave;
      _pendingSave = null;
      try {
        await _saveNow();
        c?.complete();
      } catch (e, st) {
        c?.completeError(e, st);
      }
    });

    return completer.future;
  }

  Future<void> _saveNow() async {
    final raw = jsonEncode(_items.values.map((e) => e.toJson()).toList());
    await _storage.write(key: _key, value: raw);
  }

  static void _trimIfNeeded(String owner) {
    final scoped = _items.values
        .where((item) => item.ownerUserId == owner)
        .toList(growable: false);
    if (scoped.length <= _maxItems) return;

    final values = scoped
      ..sort((a, b) {
        final pa = _keepPriority(a);
        final pb = _keepPriority(b);
        if (pa != pb) return pb.compareTo(pa);
        return _timeOf(b).compareTo(_timeOf(a));
      });

    final keep = values.take(_maxItems).map((e) => e.clientOrderId).toSet();
    _items.removeWhere(
      (_, item) => item.ownerUserId == owner && !keep.contains(item.clientOrderId),
    );
  }

  static String _itemKey(WalletOrderDraft item) =>
      _itemKeyFor(item.ownerUserId, item.clientOrderId);

  static String _itemKeyFor(String owner, String clientOrderId) =>
      '$owner::$clientOrderId';

  static String _currentOwner() {
    final identity = SessionIdentityService.instance.capture();
    return SessionIdentityService.instance.isCurrent(identity)
        ? identity.ownerUserId
        : '';
  }

  static int _keepPriority(WalletOrderDraft item) {
    if (item.needsChatCard && !item.cardSent && !item.cardIgnored) return 3;
    if (!item.isDoneOrder) return 2;
    if (item.needsChatCard && item.cardSent) return 1;
    return 0;
  }

  static DateTime _timeOf(WalletOrderDraft item) {
    final raw = item.updatedAt.isNotEmpty ? item.updatedAt : item.createdAt;
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
