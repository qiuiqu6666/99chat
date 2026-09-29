import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

class GroupLiveApiException implements Exception {
  GroupLiveApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message.isNotEmpty ? message : code;
}

class GroupLiveApi {
  GroupLiveApi._();

  static final GroupLiveApi instance = GroupLiveApi._();

  static const _prefix = '/group-live/api/v1';

  Dio get _dio => ApiClient.instance.dio;

  Future<GroupLiveSession> authorize({
    required String groupId,
    required String anchorUserId,
    required String roomName,
    DateTime? scheduledStartAt,
    String? description,
  }) async {
    // 群 ID 可能含 '#'/'@' 等保留字（如 @TGS#_xxx），
    // 必须按组件编码，否则 '#' 会被当成 URL fragment 截断路径。
    final encodedGroupId = Uri.encodeComponent(groupId.trim());
    final body = <String, dynamic>{
      'anchorUserId': anchorUserId.trim(),
      'roomName': roomName.trim(),
    };
    if (scheduledStartAt != null) {
      body['scheduledStartAt'] = scheduledStartAt.toUtc().toIso8601String();
    }
    final descriptionText = description?.trim() ?? '';
    if (descriptionText.isNotEmpty) {
      body['description'] = descriptionText;
    }
    final res = await _post(
      '$_prefix/groups/$encodedGroupId/live/authorize',
      data: body,
    );
    return GroupLiveSession.fromJson(_mapPayload(res.data));
  }

  Future<GroupLiveSession> updateSchedule({
    required String groupId,
    DateTime? scheduledStartAt,
    String? roomName,
  }) async {
    final body = <String, dynamic>{};
    if (scheduledStartAt != null) {
      body['scheduledStartAt'] = scheduledStartAt.toUtc().toIso8601String();
    }
    if (roomName != null) {
      body['roomName'] = roomName.trim();
    }
    final encodedGroupId = Uri.encodeComponent(groupId.trim());
    final res = await _patch(
      '$_prefix/groups/$encodedGroupId/live/schedule',
      data: body,
    );
    return GroupLiveSession.fromJson(_mapPayload(res.data));
  }

  Future<GroupLiveSession> revoke({required String groupId}) async {
    final encodedGroupId = Uri.encodeComponent(groupId.trim());
    final res = await _post('$_prefix/groups/$encodedGroupId/live/revoke');
    return GroupLiveSession.fromJson(_mapPayload(res.data));
  }

  Future<GroupLiveSession> stop({required String groupId}) async {
    final encodedGroupId = Uri.encodeComponent(groupId.trim());
    final res = await _post('$_prefix/groups/$encodedGroupId/live/stop');
    return GroupLiveSession.fromJson(_mapPayload(res.data));
  }

  Future<GroupLiveCurrentSnapshot> current({
    required String groupId,
    String? ifNoneMatch,
  }) async {
    final encodedGroupId = Uri.encodeComponent(groupId.trim());
    final etag = ifNoneMatch?.trim() ?? '';
    try {
      final res = await _dio.get(
        '$_prefix/groups/$encodedGroupId/live/current',
        options: Options(
          headers:
              etag.isNotEmpty ? <String, dynamic>{'If-None-Match': etag} : null,
          validateStatus: (status) =>
              status != null && (status == 200 || status == 304),
        ),
      );
      if (res.statusCode == 304) {
        return GroupLiveCurrentSnapshot.notModified(etag: _readEtag(res));
      }
      final snapshot = GroupLiveCurrentSnapshot.fromJson(_mapPayload(res.data));
      final responseEtag = _readEtag(res);
      if (snapshot.active && snapshot.session != null) {
        return GroupLiveCurrentSnapshot.active(
          snapshot.session!,
          etag: responseEtag,
        );
      }
      return GroupLiveCurrentSnapshot.inactive(etag: responseEtag);
    } on DioError catch (e) {
      if (e.response?.statusCode == 304) {
        return const GroupLiveCurrentSnapshot.notModified();
      }
      throw _mapDio(e);
    }
  }

  Future<GroupLiveIndexFetchResult> liveIndex({String? ifNoneMatch}) async {
    final etag = ifNoneMatch?.trim() ?? '';
    try {
      final res = await _dio.get(
        '$_prefix/me/live-index',
        options: Options(
          headers: etag.isNotEmpty ? <String, dynamic>{'If-None-Match': etag} : null,
          validateStatus: (status) =>
              status != null && (status == 200 || status == 304),
        ),
      );
      if (res.statusCode == 304) {
        return const GroupLiveIndexFetchResult.notModified();
      }
      final responseEtag = _readEtag(res);
      return GroupLiveIndexFetchResult.updated(
        snapshot: GroupLiveIndexSnapshot.fromJson(_mapPayload(res.data)),
        etag: responseEtag,
      );
    } on DioError catch (e) {
      if (e.response?.statusCode == 304) {
        return const GroupLiveIndexFetchResult.notModified();
      }
      throw _mapDio(e);
    }
  }

  String _readEtag(Response<dynamic> res) {
    final raw = res.headers.value('etag')?.trim() ??
        res.headers.value('ETag')?.trim() ??
        '';
    if (raw.isEmpty) {
      return '';
    }
    return raw.replaceAll('"', '');
  }

  Future<GroupLiveSession> sessionDetail({required String liveSessionId}) async {
    final res = await _get('$_prefix/live/${liveSessionId.trim()}');
    return GroupLiveSession.fromJson(_mapPayload(res.data));
  }

  Future<GroupLivePushInfo> pushInfo({required String liveSessionId}) async {
    final res = await _get('$_prefix/live/${liveSessionId.trim()}/push-info');
    return GroupLivePushInfo.fromJson(_mapPayload(res.data));
  }

  Future<GroupLivePlayInfo> playInfo({required String liveSessionId}) async {
    final res = await _get('$_prefix/live/${liveSessionId.trim()}/play-info');
    return GroupLivePlayInfo.fromJson(_mapPayload(res.data));
  }

  Future<GroupLiveTipResult> tip({
    required String liveSessionId,
    required String currency,
    required int amount,
    required String payPin,
    required String clientOrderId,
    String? memo,
  }) async {
    final body = <String, dynamic>{
      'currency': currency.trim(),
      'amount': amount,
      'payPin': payPin.trim(),
      'clientOrderId': clientOrderId.trim(),
    };
    final memoText = memo?.trim() ?? '';
    if (memoText.isNotEmpty) {
      body['memo'] = memoText;
    }
    final res = await _post(
      '$_prefix/live/${liveSessionId.trim()}/tip',
      data: body,
    );
    return GroupLiveTipResult.fromJson(_mapPayload(res.data));
  }

  Future<Response<dynamic>> _get(String path) async {
    try {
      return await _dio.get(path);
    } on DioError catch (e) {
      throw _mapDio(e);
    }
  }

  Future<Response<dynamic>> _post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _dio.post(path, data: data);
    } on DioError catch (e) {
      throw _mapDio(e);
    }
  }

  Future<Response<dynamic>> _patch(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _dio.patch(path, data: data);
    } on DioError catch (e) {
      throw _mapDio(e);
    }
  }

  Map<String, dynamic> _mapPayload(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return <String, dynamic>{};
  }

  GroupLiveApiException _mapDio(DioError e) {
    final data = e.response?.data;
    var code = '';
    var message = e.message.toString().trim();
    if (message.isEmpty) {
      message = '请求失败';
    }
    if (data is Map) {
      code = data['code']?.toString().trim() ?? '';
      message = data['message']?.toString().trim() ??
          data['msg']?.toString().trim() ??
          message;
    }
    if (code.isEmpty && e.response?.statusCode == 401) {
      code = 'UNAUTHORIZED';
    }
    return GroupLiveApiException(code, message);
  }
}
