import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

import 'api_client.dart';

/// 自建后端归档状态写入 API。
///
/// 消息正文历史统一由腾讯 IM SDK 提供；这里仅保留清空同步所需的
/// 后端水位写入，避免业务操作改变后端归档状态后产生漂移。
class MessageArchiveApi {
  MessageArchiveApi._();
  static final MessageArchiveApi instance = MessageArchiveApi._();

  Dio get _dio => ApiClient.instance.dio;

  /// 清空当前用户对单聊会话的归档历史水位（不删归档表，仅对本用户生效）。
  Future<int?> clearC2c({required String peerUserId}) {
    return _clear('/me/messages/c2c', <String, dynamic>{
      'peerUserId': peerUserId,
    });
  }

  /// 清空当前用户对群聊会话的归档历史水位（不删归档表，仅对本用户生效）。
  Future<int?> clearGroup({required String groupId}) {
    return _clear('/me/messages/group', <String, dynamic>{'groupId': groupId});
  }

  Future<int?> _clear(String path, Map<String, dynamic> query) async {
    final res = await _dio.delete(path, queryParameters: query);
    final payload = unwrapApiPayload(res.data);
    if (payload is! Map) {
      return null;
    }
    return _asInt(Map<String, dynamic>.from(payload)['clearedBeforeMs']);
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
