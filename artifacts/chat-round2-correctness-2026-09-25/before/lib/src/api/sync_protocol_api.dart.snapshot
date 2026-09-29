import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

import 'api_client.dart';

/// The backend-owned snapshot/delta contract from the realtime isolation plan.
/// SDK messages, histories and SDK conversation state intentionally do not use
/// this API.
class SyncProtocolItem {
  const SyncProtocolItem({
    required this.id,
    required this.itemVersion,
    required this.updatedAt,
    required this.data,
    this.deleted = false,
  });

  final String id;
  final int itemVersion;
  final int updatedAt;
  final Map<String, dynamic> data;
  final bool deleted;

  factory SyncProtocolItem.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final deleted = json.containsKey('deleted')
        ? _requiredBool(json['deleted'], 'deleted')
        : false;
    if (!deleted && rawData != null && rawData is! Map) {
      throw const FormatException('sync item data must be an object');
    }
    // v2 returns domain fields flattened on the item (for example
    // peerNickname/groupName) rather than nesting them under `data`.
    // Preserve those fields so domain stores can build their records.
    final id = _requiredString(
      json['id'] ??
          json['noticeId'] ??
          json['notice_id'] ??
          json['groupId'] ??
          json['group_id'] ??
          json['userId'] ??
          json['user_id'] ??
          json['peerUserId'] ??
          json['peer_user_id'],
      'id',
    );
    final data = <String, dynamic>{
      if (rawData is Map) ...Map<String, dynamic>.from(rawData),
      for (final entry in json.entries)
        if (!_itemEnvelopeFields.contains(entry.key)) entry.key: entry.value,
    };
    // Contacts from older v2 deployments use peer* names while the local
    // friend model uses friend* names. Preserve both without dropping rows.
    data['friendUserId'] = id;
    data.putIfAbsent('friendNickname',
        () => json['peerNickname'] ?? json['peer_nickname'] ?? '');
    data.putIfAbsent('friendAvatarUrl',
        () => json['peerAvatarUrl'] ?? json['peer_avatar_url'] ?? '');
    return SyncProtocolItem(
      id: id,
      itemVersion: _requiredInt(
          json['itemVersion'] ?? json['item_version'], 'itemVersion'),
      // Some v2 domains omit updatedAt on snapshot rows; serverTime remains
      // available for diagnostics. Keep zero for those valid rows.
      updatedAt: _optionalInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
      data: data,
      deleted: deleted,
    );
  }
}

const Set<String> _itemEnvelopeFields = <String>{
  'id',
  'itemVersion',
  'item_version',
  'updatedAt',
  'updated_at',
  'deleted',
  'data',
};

class SyncSnapshotPage {
  const SyncSnapshotPage({
    required this.snapshotRevision,
    required this.opaqueCursor,
    required this.hasMore,
    required this.items,
    this.estimatedTotal,
    this.checksum,
    this.serverTime,
  });

  final String snapshotRevision;
  final String opaqueCursor;
  final bool hasMore;
  final List<SyncProtocolItem> items;
  final int? estimatedTotal;
  final String? checksum;
  final int? serverTime;

  bool get isComplete => !hasMore;

  /// Compatibility alias for older callers. v2 names this field
  /// `opaqueCursor`; clients must treat it as opaque.
  String get nextCursor => opaqueCursor;

  factory SyncSnapshotPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('sync snapshot items is required');
    }
    // An empty cursor is the normal terminal page value.  Only require the
    // field to be present and treat null as an invalid response.
    final opaqueCursor = _cursorValue(
      json.containsKey('opaqueCursor')
          ? json['opaqueCursor']
          : (json.containsKey('nextCursor')
              ? json['nextCursor']
              : json['next_cursor']),
    );
    final hasMore = _requiredBool(
      json.containsKey('hasMore') ? json['hasMore'] : json['has_more'],
      'hasMore',
    );
    if (hasMore && opaqueCursor.isEmpty) {
      throw const FormatException(
          'sync snapshot nextCursor required when hasMore');
    }
    final snapshotRevision = _requiredString(
      json['snapshotRevision'] ?? json['snapshot_revision'],
      'snapshotRevision',
    );
    final items = <SyncProtocolItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw const FormatException('sync snapshot item must be an object');
      }
      items.add(
        SyncProtocolItem.fromJson(Map<String, dynamic>.from(rawItem)),
      );
    }
    return SyncSnapshotPage(
      snapshotRevision: snapshotRevision,
      opaqueCursor: opaqueCursor,
      hasMore: hasMore,
      items: List<SyncProtocolItem>.unmodifiable(items),
      estimatedTotal: _optionalInt(
          json['estimatedTotal'] ?? json['estimated_total'] ?? json['total']),
      checksum: _optionalString(json['checksum']),
      serverTime: _optionalInt(json['serverTime'] ?? json['server_time']),
    );
  }
}

class SyncChangeEvent {
  const SyncChangeEvent({
    required this.eventId,
    required this.id,
    required this.itemVersion,
    required this.operation,
    required this.occurredAt,
    required this.data,
    this.deleted = false,
  });

  final String eventId;
  final String id;
  final int itemVersion;
  final String operation;
  final int occurredAt;
  final Map<String, dynamic> data;
  final bool deleted;

  bool get isDelete => deleted || operation.toLowerCase() == 'delete';

  factory SyncChangeEvent.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final operation = (json['operation'] ?? json['op'] ?? '').toString().trim();
    final deleted = _optionalBool(json['deleted']) == true ||
        operation.toLowerCase() == 'delete';
    final data = <String, dynamic>{
      if (rawData is Map) ...Map<String, dynamic>.from(rawData),
      for (final entry in json.entries)
        if (!_eventEnvelopeFields.contains(entry.key)) entry.key: entry.value,
    };
    return SyncChangeEvent(
      eventId: _requiredString(json['eventId'] ?? json['event_id'], 'eventId'),
      id: _requiredString(
        json['id'] ??
            json['noticeId'] ??
            json['notice_id'] ??
            json['userId'] ??
            json['user_id'] ??
            json['groupId'] ??
            json['group_id'] ??
            json['peerUserId'] ??
            json['peer_user_id'] ??
            json['friendUserId'] ??
            json['friend_user_id'],
        'id',
      ),
      itemVersion: _requiredInt(
          json['itemVersion'] ?? json['item_version'], 'itemVersion'),
      operation:
          operation.isEmpty ? (deleted ? 'delete' : 'upsert') : operation,
      occurredAt: _optionalInt(
            json['occurredAt'] ??
                json['occurred_at'] ??
                json['updatedAt'] ??
                json['updated_at'],
          ) ??
          0,
      data: data,
      deleted: deleted,
    );
  }
}

const Set<String> _eventEnvelopeFields = <String>{
  'eventId',
  'event_id',
  'id',
  'itemVersion',
  'item_version',
  'operation',
  'op',
  'occurredAt',
  'occurred_at',
  'updatedAt',
  'updated_at',
  'deleted',
  'data',
};

class SyncChangesPage {
  const SyncChangesPage({
    required this.snapshotRevision,
    required this.toRevision,
    required this.opaqueCursor,
    required this.hasMore,
    required this.events,
  });

  final String snapshotRevision;
  final String toRevision;
  final String opaqueCursor;
  final bool hasMore;
  final List<SyncChangeEvent> events;

  bool get isComplete => !hasMore;
  String get nextCursor => opaqueCursor;

  /// Legacy name retained for source compatibility; v2 uses snapshotRevision.
  String get fromRevision => snapshotRevision;

  factory SyncChangesPage.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    if (rawEvents is! List) {
      throw const FormatException('sync changes events is required');
    }
    final opaqueCursor = _cursorValue(
      json.containsKey('opaqueCursor')
          ? json['opaqueCursor']
          : (json.containsKey('nextCursor')
              ? json['nextCursor']
              : json['next_cursor']),
    );
    final hasMore = _requiredBool(
      json.containsKey('hasMore') ? json['hasMore'] : json['has_more'],
      'hasMore',
    );
    if (hasMore && opaqueCursor.isEmpty) {
      throw const FormatException(
          'sync changes nextCursor required when hasMore');
    }
    final events = <SyncChangeEvent>[];
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map) {
        throw const FormatException('sync change event must be an object');
      }
      events.add(
        SyncChangeEvent.fromJson(Map<String, dynamic>.from(rawEvent)),
      );
    }
    return SyncChangesPage(
      snapshotRevision: (json['snapshotRevision'] ??
              json['snapshot_revision'] ??
              json['fromRevision'] ??
              json['from_revision'] ??
              '')
          .toString(),
      toRevision: _requiredString(
          json['toRevision'] ?? json['to_revision'], 'toRevision'),
      opaqueCursor: opaqueCursor,
      hasMore: hasMore,
      events: List<SyncChangeEvent>.unmodifiable(events),
    );
  }
}

class SyncProtocolApi {
  SyncProtocolApi._();

  static final SyncProtocolApi instance = SyncProtocolApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<SyncSnapshotPage> fetchSnapshot({
    String? accountId,
    required String domain,
    String cursor = '',
    String? snapshotRevision,
    String? groupId,
    int limit = 200,
  }) async {
    try {
      final normalizedDomain = _domain(domain);
      final response = await _dio.get(
        '/sync/$normalizedDomain/snapshot',
        queryParameters: <String, dynamic>{
          'limit': _limit(limit, normalizedDomain),
          if (cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
          if (snapshotRevision != null && snapshotRevision.trim().isNotEmpty)
            'snapshotRevision': snapshotRevision.trim(),
          if (groupId != null && groupId.trim().isNotEmpty)
            'groupId': groupId.trim(),
        },
      );
      return SyncSnapshotPage.fromJson(_payloadMap(response.data));
    } on DioError catch (error) {
      throw SyncProtocolException.fromDio(error);
    }
  }

  Future<SyncChangesPage> fetchChanges({
    String? accountId,
    required String domain,
    String afterRevision = '',
    String cursor = '',
    String? groupId,
    int limit = 200,
  }) async {
    try {
      final normalizedDomain = _domain(domain);
      final response = await _dio.get(
        '/sync/$normalizedDomain/changes',
        queryParameters: <String, dynamic>{
          'limit': _limit(limit, normalizedDomain),
          if (afterRevision.trim().isNotEmpty)
            'afterRevision': afterRevision.trim(),
          if (cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
          if (groupId != null && groupId.trim().isNotEmpty)
            'groupId': groupId.trim(),
        },
      );
      return SyncChangesPage.fromJson(_payloadMap(response.data));
    } on DioError catch (error) {
      throw SyncProtocolException.fromDio(error);
    }
  }

  static Map<String, dynamic> _payloadMap(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (payload is! Map) {
      throw const FormatException('sync response must be an object');
    }
    return Map<String, dynamic>.from(payload);
  }

  static String _domain(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, 'domain');
    if (!_domains.contains(normalized)) {
      throw ArgumentError.value(value, 'domain', 'unsupported sync domain');
    }
    return normalized;
  }

  static const Set<String> _domains = <String>{
    'contacts',
    'groups',
    'groupMembers',
    'groupNotices',
  };

  static int _limit(int value, String domain) =>
      value.clamp(1, domain == 'contacts' ? 1000 : 200);
}

class SyncProtocolException implements Exception {
  const SyncProtocolException(this.code, [this.message = '']);

  final String code;
  final String message;

  bool get snapshotExpired =>
      code == 'SNAPSHOT_EXPIRED' ||
      code == 'SNAPSHOT_REQUIRED' ||
      code == 'INVALID_CURSOR' ||
      code == 'CURSOR_INVALID' ||
      code == 'CURSOR_EXPIRED';
  bool get revisionTooOld => code == 'REVISION_TOO_OLD';

  factory SyncProtocolException.fromDio(DioError error) {
    final raw = error.response?.data;
    var code = '';
    var message = error.message;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final data = map['data'];
      final payload = data is Map ? Map<String, dynamic>.from(data) : map;
      code = (payload['code'] ??
              payload['errorCode'] ??
              payload['error_code'] ??
              '')
          .toString()
          .trim()
          .toUpperCase();
      message = (payload['message'] ?? payload['error'] ?? message).toString();
    }
    if (code.isEmpty) {
      final status = error.response?.statusCode;
      code = switch (status) {
        400 => 'SYNC_BAD_REQUEST',
        404 => 'NOT_FOUND',
        410 => 'SNAPSHOT_REQUIRED',
        _ => 'SYNC_REQUEST_FAILED',
      };
    }
    return SyncProtocolException(code, message);
  }

  @override
  String toString() => 'SyncProtocolException($code)';
}

String _requiredString(Object? value, String field) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw FormatException('sync field $field is required');
  return text;
}

String _cursorValue(Object? value) {
  if (value == null) {
    throw const FormatException('sync field opaqueCursor is required');
  }
  return value.toString().trim();
}

int _requiredInt(Object? value, String field) {
  final parsed = _optionalInt(value);
  if (parsed == null) throw FormatException('sync field $field is required');
  return parsed;
}

bool _requiredBool(Object? value, String field) {
  final parsed = _optionalBool(value);
  if (parsed == null) {
    throw FormatException('sync field $field is required and must be boolean');
  }
  return parsed;
}

bool? _optionalBool(Object? value) {
  if (value is bool) return value;
  if (value is num && (value == 0 || value == 1)) return value == 1;
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
