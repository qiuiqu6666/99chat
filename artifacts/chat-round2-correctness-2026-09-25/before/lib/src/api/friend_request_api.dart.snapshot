import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

import 'api_client.dart';

class FriendRequestApi {
  FriendRequestApi._();

  static final FriendRequestApi instance = FriendRequestApi._();

  Dio get _dio => ApiClient.instance.dio;

  String? _nextCursor;
  bool _hasMore = false;

  /// FFB-6（v17）：cold_start 期间多 service 并发请求同一资源，单 in-flight 复用。
  /// 只去重"完全相同参数的并发请求"。Key 由 limit + 调用方身份组成（这里简化为 limit）。
  Future<List<FriendRequestRecord>>? _fetchIncomingInFlight;
  int? _fetchIncomingInFlightLimit;
  SessionIdentity? _fetchIncomingInFlightIdentity;

  String? get nextCursor => _nextCursor;
  bool get hasMore => _hasMore;

  /// POST /friend-requests
  ///
  /// 发起好友申请，后端会按 addSource 统一校验搜索/手机号/二维码/名片/群聊等隐私规则。
  Future<FriendRequestCreateResult> create({
    required String targetUserId,
    required String addWording,
    required String addSource,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final res = await _dio.post('/friend-requests', data: {
      'targetUserId': targetUserId.trim(),
      'addWording': addWording.trim(),
      'addSource': _normalizeAddSource(addSource),
    });
    final result = FriendRequestCreateResult.fromJson(_payloadMap(res.data));
    if (SessionIdentityService.instance.isCurrent(identity)) {
      unawaited(ContactsProtocolSyncService.instance
          .sync(reason: 'friend_request_created'));
    }
    return result;
  }

  /// GET /friend-requests/incoming?limit=100
  ///
  /// FFB-6（v17）：并发去重。如果当前已有同 limit 的 in-flight 请求，
  /// 直接 `await` 同一 Future，避免 cold_start 期间 4-5 个 service 同时打到后端。
  Future<List<FriendRequestRecord>> fetchIncomingPending({
    int limit = 100,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final pending = _fetchIncomingInFlight;
    if (pending != null &&
        _fetchIncomingInFlightLimit == limit &&
        _fetchIncomingInFlightIdentity == identity) {
      return await pending;
    }
    final future = _doFetchIncomingPending(limit: limit);
    _fetchIncomingInFlight = future;
    _fetchIncomingInFlightLimit = limit;
    _fetchIncomingInFlightIdentity = identity;
    try {
      return await future;
    } finally {
      if (identical(_fetchIncomingInFlight, future)) {
        _fetchIncomingInFlight = null;
        _fetchIncomingInFlightLimit = null;
        _fetchIncomingInFlightIdentity = null;
      }
    }
  }

  Future<List<FriendRequestRecord>> _doFetchIncomingPending({
    required int limit,
  }) async {
    final res = await _dio.get(
      '/friend-requests/incoming',
      queryParameters: {'limit': limit},
    );
    final list = extractApiList(res.data, listKeys: const ['items']);
    return _mapRequestListRaw(list, direction: FriendRequestDirection.incoming);
  }

  List<FriendRequestRecord> _mapRequestList(
    dynamic raw, {
    required String direction,
  }) {
    final list = extractApiList(raw, listKeys: const ['items']);
    return _mapRequestListRaw(list, direction: direction);
  }

  List<FriendRequestRecord> _mapRequestListRaw(
    List<dynamic> list, {
    required String direction,
  }) {
    return list
        .whereType<Map>()
        .map((e) => FriendRequestRecord.fromPendingJson(
              Map<String, dynamic>.from(e),
              direction: direction,
            ))
        .where((e) => e.userID.isNotEmpty)
        .toList();
  }

  /// GET /friend-requests/sent?limit=100
  ///
  /// 我发起的加好友记录（含 pending / accepted / rejected）。
  Future<List<FriendRequestRecord>> fetchSent({
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/friend-requests/sent',
      queryParameters: {'limit': limit.clamp(1, 200)},
    );
    return _mapRequestList(
      res.data,
      direction: FriendRequestDirection.outgoing,
    );
  }

  /// GET /friend-requests/outgoing?limit=100
  ///
  /// 仅 pending；完整记录请用 [fetchSent]。
  Future<List<FriendRequestRecord>> fetchOutgoingPending({
    int limit = 100,
  }) async {
    final sent = await fetchSent(limit: limit);
    return sent.where((item) => item.isPending).toList();
  }

  /// DELETE /friend-requests/incoming/{id}
  Future<void> deleteIncomingById(int requestId) async {
    if (requestId <= 0) {
      throw ArgumentError.value(requestId, 'requestId', 'invalid request id');
    }
    await _dio.delete('/friend-requests/incoming/$requestId');
  }

  /// DELETE /friend-requests/incoming/batch
  Future<int> deleteIncomingBatch(List<int> ids) async {
    final cleaned = ids.where((id) => id > 0).toList(growable: false);
    if (cleaned.isEmpty) {
      return 0;
    }
    final res = await _dio.delete(
      '/friend-requests/incoming/batch',
      data: {'ids': cleaned},
    );
    return _parseDeletedCount(res.data);
  }

  /// DELETE /friend-requests/sent/{id}
  Future<void> deleteSentById(int requestId) async {
    if (requestId <= 0) {
      throw ArgumentError.value(requestId, 'requestId', 'invalid request id');
    }
    await _dio.delete('/friend-requests/sent/$requestId');
  }

  /// DELETE /friend-requests/sent/batch
  Future<int> deleteSentBatch(List<int> ids) async {
    final cleaned = ids.where((id) => id > 0).toList(growable: false);
    if (cleaned.isEmpty) {
      return 0;
    }
    final res = await _dio.delete(
      '/friend-requests/sent/batch',
      data: {'ids': cleaned},
    );
    return _parseDeletedCount(res.data);
  }

  /// POST /friend-requests/{id}/accept
  Future<void> acceptById(int requestId) async {
    if (requestId <= 0) {
      throw ArgumentError.value(requestId, 'requestId', 'invalid request id');
    }
    final identity = SessionIdentityService.instance.capture();
    await _dio.post('/friend-requests/$requestId/accept');
    if (SessionIdentityService.instance.isCurrent(identity)) {
      unawaited(ContactsProtocolSyncService.instance
          .sync(reason: 'friend_request_accepted'));
    }
  }

  /// POST /friend-requests/{id}/reject
  Future<void> rejectById(int requestId) async {
    if (requestId <= 0) {
      throw ArgumentError.value(requestId, 'requestId', 'invalid request id');
    }
    await _dio.post('/friend-requests/$requestId/reject');
  }

  /// 兼容旧代码：后端新文档没有 history 接口，保留旧接口作为本地历史兜底数据源。
  Future<List<FriendRequestRecord>> fetchHandledHistory({
    String? cursor,
    int limit = 100,
  }) async {
    final page = await fetchHandledHistoryPage(cursor: cursor, limit: limit);
    _nextCursor = page.nextCursor;
    _hasMore = page.hasMore;
    return page.items;
  }

  Future<FriendRequestPage> fetchHandledHistoryPage({
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      '/friend-application/history',
      queryParameters: {
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        'limit': limit,
      },
    );
    final payload = unwrapApiPayload(res.data);
    final map = payload is Map<String, dynamic>
        ? payload
        : payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};
    final nextCursor = map['nextCursor']?.toString();
    final list = extractApiList(map, listKeys: const ['content']);
    final items = list
        .whereType<Map>()
        .map((e) => FriendRequestRecord.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.userID.isNotEmpty)
        .toList();
    return FriendRequestPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: map['hasMore'] == true &&
          nextCursor != null &&
          nextCursor.isNotEmpty &&
          nextCursor != cursor,
    );
  }

  Future<void> accept(FriendRequestRecord record) async {
    if (record.hasServerId) {
      await acceptById(record.id!);
      return;
    }
    await _dio.post(
      '/friend-application/accept',
      data: record.toActionJson(),
    );
  }

  Future<void> reject(FriendRequestRecord record) async {
    if (record.hasServerId) {
      await rejectById(record.id!);
      return;
    }
    await _dio.post(
      '/friend-application/reject',
      data: record.toActionJson(),
    );
  }

  Future<void> deleteHistory(FriendRequestRecord record) async {
    final id = record.id;
    if (id == null || id <= 0) {
      return;
    }
    await _dio.delete('/friend-application/history/$id');
  }
}

class FriendRequestPage {
  const FriendRequestPage(
      {required this.items, required this.hasMore, this.nextCursor});
  final List<FriendRequestRecord> items;
  final bool hasMore;
  final String? nextCursor;
}

int _parseDeletedCount(dynamic raw) {
  final payload = _payloadMap(raw);
  final deleted = payload['deleted'];
  if (deleted is int) {
    return deleted;
  }
  if (deleted is num) {
    return deleted.toInt();
  }
  return int.tryParse(deleted?.toString() ?? '') ?? 0;
}

class FriendRequestCreateResult {
  FriendRequestCreateResult({
    required this.outcome,
    this.requestId,
  });

  final String outcome;
  final int? requestId;

  bool get isPending => outcome == FriendRequestOutcome.pending;
  bool get isAutoAccepted => outcome == FriendRequestOutcome.autoAccepted;
  bool get isRestored => outcome == FriendRequestOutcome.restored;

  factory FriendRequestCreateResult.fromJson(Map<String, dynamic> json) {
    return FriendRequestCreateResult(
      outcome: (json['outcome'] ?? '').toString().trim().toLowerCase(),
      requestId: _parseOptionalId(json['requestId'] ?? json['id']),
    );
  }
}

class FriendRequestOutcome {
  FriendRequestOutcome._();

  static const String pending = 'pending';
  static const String autoAccepted = 'auto_accepted';
  static const String restored = 'restored';
}

Map<String, dynamic> _payloadMap(dynamic raw) {
  final payload = unwrapApiPayload(raw);
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map) {
    return Map<String, dynamic>.from(payload);
  }
  return const <String, dynamic>{};
}

int? _parseOptionalId(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value > 0 ? value : null;
  }
  if (value is num) {
    final parsed = value.toInt();
    return parsed > 0 ? parsed : null;
  }
  final parsed = int.tryParse(value.toString().trim());
  return parsed != null && parsed > 0 ? parsed : null;
}

String _normalizeAddSource(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'search';
  final normalized = value
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll('addsource_type_', '')
      .replaceAll('addsource_', '');
  switch (normalized) {
    case 'qr':
    case 'qrcode':
    case 'qr_code':
      return 'qr_code';
    case 'phone':
    case 'mobile':
      return 'phone';
    case 'nearby':
      return 'nearby';
    case 'card':
    case 'contactcard':
      return 'card';
    case 'group':
      return 'group';
    case 'search':
    case 'chat':
    case 'android':
    case 'ios':
    case 'iphone':
    case 'web':
    case 'h5':
      return 'search';
    default:
      return 'search';
  }
}
