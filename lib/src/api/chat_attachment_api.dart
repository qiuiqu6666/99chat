import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_diagnostics.dart';

/// Only business JSON requests use ApiClient. Signed OSS transfers must use a
/// separate client without the JWT, device headers or authentication interceptors.
class ChatAttachmentApi {
  ChatAttachmentApi({Dio? dio}) : _injectedDio = dio;
  final Dio? _injectedDio;
  Dio get _dio => _injectedDio ?? ApiClient.instance.dio;
  static const prefix = '/me/chat';

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        '$prefix$path',
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, headers: const {
          'X-Chat-Attachment-Protocol-Version': '1',
        }),
      );
      final decoded = _decodeResponse(response.data);
      final envelope = attachmentMap(decoded);
      final wrapped = envelope.containsKey('code');
      final payload = wrapped ? envelope['data'] : decoded;
      if (path == '/attachment-policy') {
        ChatAttachmentDiagnostics.event('policy_format', {
          'rawType': response.data.runtimeType.toString(),
          'wrapped': wrapped,
          'hasData': envelope.containsKey('data'),
          'hasPolicyFields': envelope.containsKey('nativeMaxBytes'),
        });
        ChatAttachmentDiagnostics.policyResponse(
            status: response.statusCode,
            headers: response.requestOptions.headers,
            payload: payload);
      }
      if (wrapped && (envelope['code'] != 0 || !envelope.containsKey('data'))) {
        throw _error(envelope, response.statusCode);
      }
      // Existing backend APIs can return a DTO directly. Each endpoint still
      // validates its required fields; explicit error codes never become success.
      return payload;
    } on DioError catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const ChatAttachmentException('CANCELLED', '任务已暂停');
      }
      Map<String, dynamic> body = {};
      try {
        body = attachmentMap(_decodeResponse(error.response?.data));
      } on ChatAttachmentException {
        // Preserve the transport status when the gateway returns non-JSON.
      }
      throw _error(body, error.response?.statusCode,
          retryAfter: error.response?.headers.value('retry-after'));
    }
  }

  static dynamic _decodeResponse(dynamic raw) {
    if (raw is Map || raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map || decoded is List) return decoded;
      } on FormatException {
        // Do not log HTML, raw bodies, URLs or tokens from a gateway response.
      }
    }
    ChatAttachmentDiagnostics.event('invalid_response_format', {
      'rawType': raw.runtimeType.toString(),
    });
    throw const ChatAttachmentException(
        'INVALID_RESPONSE', '附件接口未返回有效 JSON，请检查服务端接口');
  }

  ChatAttachmentException _error(Map<String, dynamic> body, int? status,
      {String? retryAfter}) {
    final code = attachmentString(body['code']);
    final seconds = attachmentPositiveInt(body['retryAfter']) ??
        int.tryParse(retryAfter ?? '');
    return ChatAttachmentException(
      code.isNotEmpty && code != '0'
          ? code
          : status == null
              ? 'NETWORK_ERROR'
              : 'INVALID_RESPONSE',
      attachmentString(body['message']),
      retryAfter:
          seconds != null && seconds > 0 ? Duration(seconds: seconds) : null,
    );
  }

  Future<ChatAttachmentPolicy> policy({CancelToken? cancelToken}) async =>
      ChatAttachmentPolicy.fromJson(attachmentMap(await request(
          'GET', '/attachment-policy',
          cancelToken: cancelToken)));

  Future<Map<String, dynamic>> initUpload(Map<String, dynamic> body,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request('POST', '/uploads',
          data: body, cancelToken: cancelToken));

  Future<Map<String, dynamic>> status(String id,
          {int afterPartNumber = 0,
          int limit = 100,
          CancelToken? cancelToken}) async =>
      attachmentMap(await request('GET', '/uploads/${Uri.encodeComponent(id)}',
          query: {
            'afterPartNumber': afterPartNumber,
            'limit': limit,
          },
          cancelToken: cancelToken));

  Future<List<Map<String, dynamic>>> partUrls(String id, List<int> numbers,
      {CancelToken? cancelToken}) async {
    if (numbers.isEmpty || numbers.length > 32) {
      throw ArgumentError('1..32 part numbers required');
    }
    final result = await request(
        'POST', '/uploads/${Uri.encodeComponent(id)}/part-urls',
        data: {'partNumbers': numbers}, cancelToken: cancelToken);
    final map = attachmentMap(result);
    final rows = result is List ? result : map['parts'] ?? map['partUrls'];
    if (rows is! List) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '缺少分片上传地址');
    }
    return rows.map(attachmentMap).toList(growable: false);
  }

  Future<Map<String, dynamic>> complete(String id,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request(
          'POST', '/uploads/${Uri.encodeComponent(id)}/complete',
          data: {}, cancelToken: cancelToken));

  Future<Map<String, dynamic>> cancel(String id) async => attachmentMap(
      await request('DELETE', '/uploads/${Uri.encodeComponent(id)}'));

  Future<Map<String, dynamic>> thumbnailUpload(String id,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request(
          'POST', '/uploads/${Uri.encodeComponent(id)}/thumbnail-upload',
          data: {}, cancelToken: cancelToken));

  Future<Map<String, dynamic>> thumbnailComplete(String id,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request(
          'POST', '/uploads/${Uri.encodeComponent(id)}/thumbnail-complete',
          data: {}, cancelToken: cancelToken));

  Future<Map<String, dynamic>> sendNativeVideo({
    required String attachmentId,
    required String referenceId,
    required String operationId,
    required ChatAttachmentTarget target,
    int? durationMs,
    CancelToken? cancelToken,
  }) async =>
      attachmentMap(await request('POST', '/native-video-messages',
          data: {
            'clientOperationId': operationId,
            'attachmentId': attachmentId,
            'referenceId': referenceId,
            if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
            ...target.toJson()
          },
          cancelToken: cancelToken));

  Future<Map<String, dynamic>> nativeVideoStatus(String operationId,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request(
          'GET', '/native-video-messages/${Uri.encodeComponent(operationId)}',
          cancelToken: cancelToken));

  Future<Map<String, dynamic>> metadata(String id,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request(
          'GET', '/attachments/${Uri.encodeComponent(id)}',
          cancelToken: cancelToken));

  Future<String> reference(
      String id, ChatAttachmentTarget target, String operationId,
      {CancelToken? cancelToken}) async {
    final result = attachmentMap(await request(
        'POST', '/attachments/${Uri.encodeComponent(id)}/references',
        data: {'clientOperationId': operationId, ...target.toJson()},
        cancelToken: cancelToken));
    final ref = attachmentString(result['referenceId']);
    if (ref.isEmpty) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '附件引用缺失');
    }
    return ref;
  }

  Future<Map<String, dynamic>> access(ChatAttachment attachment, String purpose,
          {CancelToken? cancelToken}) async =>
      attachmentMap(await request('POST',
          '/attachments/${Uri.encodeComponent(attachment.attachmentId)}/access',
          data: {'referenceId': attachment.referenceId, 'purpose': purpose},
          cancelToken: cancelToken));
}
