import 'dart:convert';

/// Isolate / `compute` 入口：批量解码会话表行的 `raw_json`。
/// 只使用可 Send 的 Map/基本类型；不碰 `V2TimConversation`。

/// 将 SQLite 行转为主 isolate 可组装的 payload。
///
/// 每项包含列字段副本，以及可选的 `decoded`（`raw_json` 解析后的 Map）。
List<Map<String, dynamic>> decodeConversationRowsForIsolate(
  List<Map<String, Object?>> rows,
) {
  final out = <Map<String, dynamic>>[];
  for (final row in rows) {
    out.add(_decodeOneRow(row));
  }
  return out;
}

Map<String, dynamic> _decodeOneRow(Map<String, Object?> row) {
  final payload = <String, dynamic>{
    'conversation_id': row['conversation_id']?.toString() ?? '',
    'conv_type': _asInt(row['conv_type']),
    'user_id': row['user_id']?.toString() ?? '',
    'group_id': row['group_id']?.toString() ?? '',
    'show_name': row['show_name']?.toString() ?? '',
    'face_url': row['face_url']?.toString() ?? '',
    'unread_count': _asInt(row['unread_count']),
    'recv_opt': _asInt(row['recv_opt']),
    'group_type': row['group_type']?.toString() ?? '',
    'is_pinned': _asInt(row['is_pinned']),
    'order_key': _asInt(row['order_key']),
    'active_time': _asInt(row['active_time']),
    'read_cleared_at': _asInt(row['read_cleared_at']),
    'local_draft_text': row['local_draft_text']?.toString() ?? '',
    'local_draft_updated_at': _asInt(row['local_draft_updated_at']),
    'preview_text': row['preview_text']?.toString() ?? '',
    'preview_elem_type': _asInt(row['preview_elem_type']),
    'preview_sender': row['preview_sender']?.toString() ?? '',
    'preview_sender_name': row['preview_sender_name']?.toString() ?? '',
    'preview_timestamp': _asInt(row['preview_timestamp']),
    'preview_status': _asInt(row['preview_status']),
    'preview_is_self': _asInt(row['preview_is_self']),
    'preview_client_id': row['preview_client_id']?.toString() ?? '',
    'preview_is_peer_read': _asInt(row['preview_is_peer_read']),
    'last_msg_id': row['last_msg_id']?.toString() ?? '',
    'decoded': null,
  };

  final raw = row['raw_json']?.toString() ?? '';
  if (raw.isEmpty) {
    return payload;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      payload['decoded'] = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    payload['decoded'] = null;
  }
  return payload;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? 0;
}
