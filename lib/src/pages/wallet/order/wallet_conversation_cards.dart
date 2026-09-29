import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';
import 'wallet_order_events.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';

typedef WalletCardPageReader = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> query);

/// REST owns the business card. IM messages only locate/announce it. These rows
/// belong exclusively to display projection, never to SDK history or seq coverage.
class WalletConversationCards extends ChangeNotifier {
  WalletConversationCards(
      {required this.target, required this.group, WalletCardPageReader? reader})
      : _reader = reader ?? _read,
        _identity = SessionIdentityService.instance.capture() {
    SessionIdentityService.instance.addInvalidationListener(_invalidate);
    WalletOrderEvents.recordChanged.addListener(_onOrderChanged);
  }
  final String target;
  final bool group;
  final SessionIdentity _identity;
  final WalletCardPageReader _reader;
  final Map<String, Map<String, dynamic>> _cards = {};
  final Set<String> _represented = {};
  Timer? _timer;
  bool _disposed = false;
  bool _busy = false;
  String? _before;
  String? _beforeId;
  int _oldestVisible = 0;
  int _clearedAt = 0;
  bool get _current =>
      !_disposed && SessionIdentityService.instance.isCurrent(_identity);

  static Future<Map<String, dynamic>> _read(Map<String, dynamic> query) async {
    final response = await ApiClient.instance.dio
        .get('/wallet/card-orders/conversation', queryParameters: query);
    return Map<String, dynamic>.from(unwrapApiPayload(response.data) as Map);
  }

  void start() {
    if (_timer != null || !_current || target.isEmpty) return;
    unawaited(refresh());
    _timer =
        Timer.periodic(const Duration(seconds: 4), (_) => unawaited(refresh()));
  }

  void _onOrderChanged() {
    unawaited(refresh());
  }

  void _invalidate(int generation, String reason) {
    _timer?.cancel();
    _timer = null;
    _cards.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_busy || !_current || target.isEmpty) return;
    _busy = true;
    bool changed = false;
    try {
      final cleared = await ArchiveHistoryProvider.historyClearedAtMs(
          '${group ? 'group' : 'c2c'}_$target');
      if (!_current) return;
      if (cleared > _clearedAt) {
        _clearedAt = cleared;
        changed = true;
      }
      // Always catch the newest orders first. Historical pagination is durable
      // in this route and advances independently so busy chats cannot starve it.
      final newest = await _reader({'target': target, 'group': group});
      if (!_current) return;
      changed = _accept(newest) || changed;
      _before ??= newest['nextBefore']?.toString();
      _beforeId ??= newest['nextBeforeId']?.toString();
      for (var page = 0; page < 2 && _before != null; page++) {
        final requested = _before;
        final older = await _reader({
          'target': target,
          'group': group,
          'before': _before,
          'beforeId': _beforeId
        });
        if (!_current) return;
        changed = _accept(older) || changed;
        _before = older['nextBefore']?.toString();
        _beforeId = older['nextBeforeId']?.toString();
        final time = _before == null ? null : DateTime.tryParse(_before!);
        if (_before == requested ||
            (time != null &&
                _oldestVisible > 0 &&
                time.millisecondsSinceEpoch ~/ 1000 < _oldestVisible)) {
          _before = null;
          _beforeId = null;
          break;
        }
      }
    } on DioError catch (e) {
      if (_current &&
          (e.response?.statusCode == 401 ||
              e.response?.statusCode == 403 ||
              e.response?.statusCode == 404)) {
        changed = _cards.isNotEmpty;
        _cards.clear();
      }
    } catch (_) {
      // A network failure cannot invent a card, remove a committed order, or pay again.
    } finally {
      _busy = false;
      if (_current && changed) notifyListeners();
    }
  }

  bool _accept(Map<String, dynamic> page) {
    if (page['cards'] is! List) {
      throw const FormatException('Invalid wallet card page');
    }
    var changed = false;
    for (final raw in page['cards'] as List) {
      if (raw is! Map) continue;
      final card = Map<String, dynamic>.from(raw);
      final id = card['cardId']?.toString() ?? '';
      final sender = ChatIdFormat.rawUserUid(card['senderUserId']?.toString());
      final recipient = card['conversationId']?.toString() ?? '';
      if (id.isEmpty ||
          card['paymentState'] != 'COMMITTED' ||
          card['isGroup'] != group) {
        continue;
      }
      if (group
          ? recipient != target
          : !((sender == _identity.ownerUserId && recipient == target) ||
              (sender == target && recipient == _identity.ownerUserId))) {
        continue;
      }
      final previousVersion =
          (_cards[id]?['cardStateVersion'] as num?)?.toInt() ?? 0;
      final incomingVersion = (card['cardStateVersion'] as num?)?.toInt() ?? 0;
      if (incomingVersion < previousVersion) continue;
      if (jsonEncode(_cards[id]) != jsonEncode(card)) {
        _cards[id] = card;
        changed = true;
      }
    }
    return changed;
  }

  String? _knownId(V2TimMessage message) {
    try {
      dynamic value = jsonDecode(message.customElem?.data ?? '');
      if (value is String) value = jsonDecode(value);
      if (value is! Map) return null;
      final type = value['customType'] ?? value['type'];
      if (!const [
        'wallet_transfer',
        'wallet_red_packet',
        'wallet_group_transfer'
      ].contains(type)) {
        return null;
      }
      final id =
          '${type == 'wallet_transfer' ? 'transfer' : 'rp'}:${value['orderId'] ?? value['id']}';
      final card = _cards[id];
      if (card == null ||
          ChatIdFormat.rawUserUid(message.sender) !=
              ChatIdFormat.rawUserUid(card['senderUserId']?.toString())) {
        return null;
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  bool _visible(Map<String, dynamic> card) {
    final created = DateTime.tryParse(card['createdAt']?.toString() ?? '')
            ?.millisecondsSinceEpoch ??
        ((card['timestamp'] as num?)?.toInt() ?? 0) * 1000;
    return created > _clearedAt;
  }

  List<V2TimMessage> formalRows(List<V2TimMessage> messages,
      {int clearEpoch = 0}) {
    if (clearEpoch > _clearedAt) _clearedAt = clearEpoch;
    _represented.clear();
    if (!_current || _cards.isEmpty) return messages;
    final times = messages
        .where((m) => m.elemType != 11)
        .map((m) => m.timestamp ?? 0)
        .where((t) => t > 0);
    _oldestVisible = times.isEmpty ? 0 : times.reduce((a, b) => a < b ? a : b);
    final newestTransport = <String, V2TimMessage>{};
    for (final message in messages) {
      final id = _knownId(message);
      if (id == null) continue;
      if ((message.msgID ?? '').isEmpty ||
          (message.msgID ?? '').startsWith('local_') ||
          (message.isSelf == true && message.status != 2)) {
        continue;
      }
      final previous = newestTransport[id];
      if (previous == null ||
          (message.timestamp ?? 0) > (previous.timestamp ?? 0) ||
          ((message.timestamp ?? 0) == (previous.timestamp ?? 0) &&
              (int.tryParse(message.seq ?? '') ?? 0) >
                  (int.tryParse(previous.seq ?? '') ?? 0))) {
        newestTransport[id] = message;
      }
    }
    final result = <V2TimMessage>[];
    for (final message in messages) {
      final id = _knownId(message);
      if (id == null) {
        result.add(message);
      } else if (_visible(_cards[id]!) &&
          identical(newestTransport[id], message) &&
          _represented.add(id)) {
        result.add(_row(_cards[id]!, physical: message));
      }
    }
    return result;
  }

  List<V2TimMessage> get displayRows {
    if (!_current) return const [];
    return _cards.entries
        .where((e) => !_represented.contains(e.key) && _visible(e.value))
        .map((e) => _row(e.value))
        .toList(growable: false);
  }

  V2TimMessage _row(Map<String, dynamic> card, {V2TimMessage? physical}) {
    final sender = card['senderUserId']?.toString() ?? '';
    // A display record must not call the native IM clock or createMessage API.
    return V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = physical?.msgID ?? 'local_wallet_card:${card['cardId']}'
      ..id = physical?.id ??
          physical?.msgID ??
          'local_wallet_card:${card['cardId']}'
      ..seq = physical?.seq
      ..elemType = 2
      ..sender = sender
      ..userID = group ? '' : target
      ..groupID = group ? target : ''
      ..isSelf = sender == _identity.ownerUserId
      ..timestamp = physical?.timestamp ?? (card['timestamp'] as num).toInt()
      ..nickName = card['senderName']?.toString()
      ..faceUrl = card['senderAvatar']?.toString()
      ..customElem = V2TimCustomElem(
          data: jsonEncode(card),
          desc: 'wallet_order',
          extension: 'wallet_order')
      ..status = 2;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    SessionIdentityService.instance.removeInvalidationListener(_invalidate);
    WalletOrderEvents.recordChanged.removeListener(_onOrderChanged);
    _cards.clear();
    super.dispose();
  }
}
