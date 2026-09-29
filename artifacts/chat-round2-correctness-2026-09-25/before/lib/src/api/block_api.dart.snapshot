import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

import 'api_client.dart';

class BlockListItem {
  BlockListItem({
    required this.userId,
    this.nickname,
    this.avatarUrl,
    this.blockedAt,
  });

  final String userId;
  final String? nickname;
  final String? avatarUrl;
  final int? blockedAt;

  String get displayName {
    final name = nickname?.trim() ?? '';
    if (name.isNotEmpty) {
      return name;
    }
    return userId;
  }

  factory BlockListItem.fromJson(Map<String, dynamic> json) {
    final userId = ChatIdFormat.rawUserUid(
      json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
    );
    final nickname = json['nickname']?.toString().trim();
    final avatarUrl = json['avatarUrl']?.toString().trim() ??
        json['avatar_url']?.toString().trim();
    return BlockListItem(
      userId: userId,
      nickname: (nickname == null || nickname.isEmpty) ? null : nickname,
      avatarUrl: (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
      blockedAt: _readMillis(json['blockedAt'] ?? json['blocked_at']),
    );
  }
}

class BlockListPage {
  BlockListPage({
    required this.items,
    required this.startIndex,
    required this.hasMore,
  });

  final List<BlockListItem> items;
  final int startIndex;
  final bool hasMore;

  factory BlockListPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => BlockListItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.userId.isNotEmpty)
            .toList()
        : <BlockListItem>[];
    final startIndex = _readInt(json['startIndex'] ?? json['start_index']) ?? 0;
    final hasMore = json['hasMore'] as bool? ??
        json['has_more'] as bool? ??
        startIndex > 0;
    return BlockListPage(
      items: items,
      startIndex: startIndex,
      hasMore: hasMore,
    );
  }
}

class BlockMutationResult {
  BlockMutationResult({
    required this.ok,
    required this.userId,
  });

  final bool ok;
  final String userId;

  factory BlockMutationResult.fromJson(Map<String, dynamic> json) {
    return BlockMutationResult(
      ok: json['ok'] as bool? ?? true,
      userId: ChatIdFormat.rawUserUid(
        json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      ),
    );
  }
}

class BlockApi {
  BlockApi._();

  static final BlockApi instance = BlockApi._();

  Dio get _dio => ApiClient.instance.dio;

  Map<String, dynamic> _asMap(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return <String, dynamic>{};
  }

  /// POST /me/blocks
  Future<BlockMutationResult> block(String userId) async {
    final id = ChatIdFormat.rawUserUid(userId);
    final res = await _dio.post('/me/blocks', data: {
      'userId': id,
    });
    final result = BlockMutationResult.fromJson(_asMap(res.data));
    if (result.userId.isEmpty) {
      return BlockMutationResult(ok: result.ok, userId: id);
    }
    return result;
  }

  /// DELETE /me/blocks/{userId}
  Future<BlockMutationResult> unblock(String userId) async {
    final id = ChatIdFormat.rawUserUid(userId);
    final res = await _dio.delete(
      '/me/blocks/${Uri.encodeComponent(id)}',
    );
    final result = BlockMutationResult.fromJson(_asMap(res.data));
    if (result.userId.isEmpty) {
      return BlockMutationResult(ok: result.ok, userId: id);
    }
    return result;
  }

  /// GET /me/blocks?startIndex=&limit=
  Future<BlockListPage> list({
    int startIndex = 0,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/me/blocks',
      queryParameters: {
        'startIndex': startIndex < 0 ? 0 : startIndex,
        'limit': limit.clamp(1, 100),
      },
    );
    return BlockListPage.fromJson(_asMap(res.data));
  }

  /// 分页拉齐当前账号黑名单。
  Future<List<BlockListItem>> fetchAll({int limit = 50}) async {
    final items = <BlockListItem>[];
    var cursor = 0;
    for (var page = 0; page < 40; page++) {
      final result = await list(startIndex: cursor, limit: limit);
      items.addAll(result.items);
      if (!result.hasMore) {
        break;
      }
      cursor = result.startIndex;
      if (cursor <= 0) {
        break;
      }
    }
    return items;
  }
}

int? _readInt(dynamic raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
  }
  return null;
}

int? _readMillis(dynamic raw) {
  return _readInt(raw);
}
