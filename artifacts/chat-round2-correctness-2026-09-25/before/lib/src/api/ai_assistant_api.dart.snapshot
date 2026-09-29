import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_sse.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_upload_mime.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

class AiAssistantException implements Exception {
  const AiAssistantException(this.code, this.message);

  final String code;
  final String message;

  bool get isBusy => code == 'CHAT_BUSY';
  bool get cancelled => code == 'CANCELLED';

  @override
  String toString() => message.isEmpty ? code : message;
}

class AiAssistantAnalyze {
  const AiAssistantAnalyze.c2c(this.peerUserId)
      : type = 'c2c',
        groupId = null,
        text = null;

  const AiAssistantAnalyze.group(this.groupId)
      : type = 'group',
        peerUserId = null,
        text = null;

  const AiAssistantAnalyze.paste(this.text)
      : type = 'paste',
        peerUserId = null,
        groupId = null;

  final String type;
  final String? peerUserId;
  final String? groupId;
  final String? text;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      if (peerUserId != null && peerUserId!.isNotEmpty)
        'peerUserId': peerUserId,
      if (groupId != null && groupId!.isNotEmpty) 'groupId': groupId,
      if (text != null) 'text': text,
    };
  }
}

class AiAssistantHistoryItem {
  const AiAssistantHistoryItem({
    required this.id,
    required this.role,
    required this.content,
    required this.capability,
    required this.analyzeType,
    required this.analyzePeerUserId,
    required this.analyzeGroupId,
    required this.status,
    required this.compressed,
    required this.sourceMessageCount,
    required this.createdAt,
    required this.imageUrl,
    required this.fileIds,
  });

  final String id;
  final String role;
  final String content;
  final String capability;
  final String analyzeType;
  final String analyzePeerUserId;
  final String analyzeGroupId;
  final String status;
  final bool compressed;
  final int sourceMessageCount;
  final int createdAt;
  final String imageUrl;
  final List<String> fileIds;

  factory AiAssistantHistoryItem.fromJson(Map<String, dynamic> json) {
    final files = json['fileIds'];
    return AiAssistantHistoryItem(
      id: _asString(json['id']),
      role: _asString(json['role']),
      content: _asString(json['content']),
      capability: _asString(json['capability']),
      analyzeType: _asString(json['analyzeType']),
      analyzePeerUserId: _asString(json['analyzePeerUserId']),
      analyzeGroupId: _asString(json['analyzeGroupId']),
      status: _asString(json['status']),
      compressed: json['compressed'] == true,
      sourceMessageCount: _asInt(json['sourceMessageCount']),
      createdAt: _asInt(json['createdAt']),
      imageUrl: _asString(json['imageUrl']),
      fileIds: files is List
          ? files
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }
}

class AiAssistantHistoryPage {
  const AiAssistantHistoryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<AiAssistantHistoryItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory AiAssistantHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => AiAssistantHistoryItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : const <AiAssistantHistoryItem>[];
    final cursor = _asString(json['nextCursor']);
    return AiAssistantHistoryPage(
      items: items,
      hasMore: json['hasMore'] == true,
      nextCursor: cursor.isEmpty ? null : cursor,
    );
  }
}

class AiAssistantUploadedFile {
  const AiAssistantUploadedFile({
    required this.fileId,
    required this.contentType,
    required this.sizeBytes,
    required this.fileName,
  });

  final String fileId;
  final String contentType;
  final int sizeBytes;
  final String fileName;

  factory AiAssistantUploadedFile.fromJson(Map<String, dynamic> json) {
    return AiAssistantUploadedFile(
      fileId: _asString(json['fileId']),
      contentType: _asString(json['contentType']),
      sizeBytes: _asInt(json['sizeBytes']),
      fileName: _asString(json['fileName']),
    );
  }
}

enum AiAssistantStreamKind { meta, delta, done, error }

class AiAssistantStreamEvent {
  const AiAssistantStreamEvent({
    required this.kind,
    this.userMessageId,
    this.assistantMessageId,
    this.text = '',
    this.compressed = false,
    this.sourceMessageCount = 0,
    this.imageUrl = '',
    this.code = '',
    this.message = '',
  });

  final AiAssistantStreamKind kind;
  final String? userMessageId;
  final String? assistantMessageId;
  final String text;
  final bool compressed;
  final int sourceMessageCount;
  final String imageUrl;
  final String code;
  final String message;

  static AiAssistantStreamEvent? parse(String event, String data) {
    final trimmed = data.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') {
      return null;
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    switch (event) {
      case 'meta':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.meta,
          userMessageId: _nullableId(json['userMessageId']),
          assistantMessageId: _nullableId(json['assistantMessageId']),
        );
      case 'delta':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.delta,
          text: _asString(json['text']),
        );
      case 'done':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.done,
          assistantMessageId: _nullableId(json['assistantMessageId']),
          compressed: json['compressed'] == true,
          sourceMessageCount: _asInt(json['sourceMessageCount']),
          imageUrl: _asString(json['imageUrl']),
        );
      case 'error':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.error,
          code: _asString(json['code']),
          message: _asString(json['message']),
        );
      default:
        return null;
    }
  }
}

class AiAssistantApi {
  AiAssistantApi({Dio? dio}) : _injectedDio = dio;

  static final AiAssistantApi instance = AiAssistantApi();

  static const prefix = '/ai-assistant/api/v1/chat';

  final Dio? _injectedDio;
  Dio get _dio => _injectedDio ?? ApiClient.instance.dio;

  static String filePath(String fileId) =>
      '$prefix/files/${Uri.encodeComponent(fileId)}';

  static String? fileIdFromUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    const marker = '/api/v1/chat/files/';
    final index = raw.indexOf(marker);
    if (index < 0) {
      return raw.contains('/') ? null : raw;
    }
    final id = raw.substring(index + marker.length).split('?').first.trim();
    return id.isEmpty ? null : Uri.decodeComponent(id);
  }

  Future<AiAssistantHistoryPage> history({
    int limit = 50,
    String? cursor,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.clamp(1, 100),
    };
    final next = cursor?.trim() ?? '';
    if (next.isNotEmpty) {
      query['cursor'] = next;
    }
    final res = await _dio.get<dynamic>(
      '$prefix/history',
      queryParameters: query,
    );
    _ensureSuccess(res.data);
    final payload = unwrapApiPayload(res.data);
    final map = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    return AiAssistantHistoryPage.fromJson(map);
  }

  Future<int> deleteHistory() async {
    final res = await _dio.delete<dynamic>('$prefix/history');
    _ensureSuccess(res.data);
    final payload = unwrapApiPayload(res.data);
    if (payload is Map) {
      return _asInt(payload['deleted']);
    }
    return 0;
  }

  Future<AiAssistantUploadedFile> uploadFile({
    required String fileName,
    String? path,
    Uint8List? bytes,
    String? mimeType,
  }) async {
    final safeName = AiAssistantUploadMime.ensureFileName(fileName, mimeType);
    final mime = (mimeType ?? '').trim().isNotEmpty
        ? mimeType!.trim()
        : (AiAssistantUploadMime.fromName(safeName) ?? '');
    if (mime.isEmpty) {
      throw const AiAssistantException('INVALID_INPUT', '不支持的文件类型');
    }
    final MultipartFile part;
    if (bytes != null && bytes.isNotEmpty) {
      part = MultipartFile.fromBytes(
        bytes,
        filename: safeName,
        contentType: MediaType.parse(mime),
      );
    } else {
      final filePath = path?.trim() ?? '';
      if (filePath.isEmpty) {
        throw const AiAssistantException('INVALID_INPUT', '文件不可用');
      }
      part = await MultipartFile.fromFile(
        filePath,
        filename: safeName,
        contentType: MediaType.parse(mime),
      );
    }
    try {
      final res = await _dio.post<dynamic>(
        '$prefix/files',
        data: FormData.fromMap(<String, dynamic>{'file': part}),
        options: Options(
          sendTimeout: 60000,
          receiveTimeout: 60000,
        ),
      );
      _ensureSuccess(res.data);
      final payload = unwrapApiPayload(res.data);
      if (payload is! Map) {
        throw const AiAssistantException('INVALID_RESPONSE', '上传未返回有效数据');
      }
      final file = AiAssistantUploadedFile.fromJson(
        Map<String, dynamic>.from(payload),
      );
      if (file.fileId.isEmpty) {
        throw const AiAssistantException('INVALID_RESPONSE', '上传未返回文件');
      }
      return file;
    } on AiAssistantException {
      rethrow;
    } on DioError catch (error) {
      throw await _fromDio(error);
    }
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final id = fileId.trim();
    if (id.isEmpty) {
      throw const AiAssistantException('FILE_UNAVAILABLE', '文件不可用');
    }
    try {
      final res = await _dio.get<dynamic>(
        filePath(id),
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: 60000,
        ),
      );
      final data = res.data;
      if (data is Uint8List) {
        return data;
      }
      if (data is List<int>) {
        return Uint8List.fromList(data);
      }
      throw const AiAssistantException('FILE_UNAVAILABLE', '文件不可用');
    } on AiAssistantException {
      rethrow;
    } on DioError catch (error) {
      throw await _fromDio(error);
    }
  }

  Stream<AiAssistantStreamEvent> stream({
    String? capability,
    required String content,
    AiAssistantAnalyze? analyze,
    List<String>? fileIds,
    CancelToken? cancelToken,
  }) {
    final body = <String, dynamic>{
      'content': content,
    };
    final cap = (capability ?? '').trim();
    if (cap.isNotEmpty) {
      body['capability'] = cap;
    }
    if (analyze != null) {
      body['analyze'] = analyze.toJson();
    }
    if (fileIds != null && fileIds.isNotEmpty) {
      body['fileIds'] = fileIds;
    }
    final controller = StreamController<AiAssistantStreamEvent>();
    () async {
      try {
        final response = await _dio.post<ResponseBody>(
          '$prefix/stream',
          data: body,
          cancelToken: cancelToken,
          options: Options(
            headers: const <String, dynamic>{
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            },
            responseType: ResponseType.stream,
            sendTimeout: 60000,
            receiveTimeout: 0,
            validateStatus: (status) => true,
          ),
        );
        final status = response.statusCode ?? 0;
        final payload = response.data;
        if (payload == null) {
          throw const AiAssistantException('MAIN_UNAVAILABLE', '助手服务不可用');
        }
        final contentType =
            response.headers.value(Headers.contentTypeHeader) ?? '';
        if (status != 200 || !contentType.contains('text/event-stream')) {
          final text = await utf8.decoder.bind(payload.stream).join();
          throw _fromBody(text, status);
        }
        final parser = AiAssistantSseParser();
        await for (final chunk in payload.stream) {
          if (controller.isClosed) {
            break;
          }
          parser.feed(utf8.decode(chunk), (event, data) {
            final parsed = AiAssistantStreamEvent.parse(event, data);
            if (parsed != null && !controller.isClosed) {
              controller.add(parsed);
            }
          });
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } on AiAssistantException catch (error) {
        if (!controller.isClosed) {
          controller.addError(error);
          await controller.close();
        }
      } on DioError catch (error) {
        if (!controller.isClosed) {
          controller.addError(await _fromDio(error));
          await controller.close();
        }
      } catch (error) {
        if (!controller.isClosed) {
          controller.addError(
            AiAssistantException('MAIN_UNAVAILABLE', error.toString()),
          );
          await controller.close();
        }
      }
    }();
    return controller.stream;
  }

  void _ensureSuccess(dynamic raw) {
    if (raw is! Map) {
      return;
    }
    final map = Map<String, dynamic>.from(raw);
    final code = map['code'];
    if (code == null || _isSuccessCode(code)) {
      return;
    }
    throw AiAssistantException(
      code.toString().trim(),
      _asString(map['message']),
    );
  }

  Future<AiAssistantException> _fromDio(DioError error) async {
    if (CancelToken.isCancel(error)) {
      return const AiAssistantException('CANCELLED', '');
    }
    final status = error.response?.statusCode;
    final data = error.response?.data;
    if (data is Map) {
      return _fromMap(Map<String, dynamic>.from(data), status);
    }
    if (data is String && data.trim().isNotEmpty) {
      return _fromBody(data, status);
    }
    if (data is List<int>) {
      return _fromBody(utf8.decode(data), status);
    }
    if (data is ResponseBody) {
      try {
        final text = await utf8.decoder.bind(data.stream).join();
        return _fromBody(text, status);
      } catch (_) {}
    }
    return AiAssistantException(
      status == 401 ? 'UNAUTHORIZED' : 'MAIN_UNAVAILABLE',
      _asString(error.message),
    );
  }

  AiAssistantException _fromBody(String raw, int? status) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _fromMap(Map<String, dynamic>.from(decoded), status);
      }
    } on FormatException {
      // Gateway HTML or empty body.
    }
    return AiAssistantException(
      status == 401
          ? 'UNAUTHORIZED'
          : status == 409
              ? 'CHAT_BUSY'
              : status == 400
                  ? 'INVALID_INPUT'
                  : 'MAIN_UNAVAILABLE',
      raw.trim(),
    );
  }

  AiAssistantException _fromMap(Map<String, dynamic> map, int? status) {
    final code = _asString(map['code']);
    if (code.isNotEmpty && code != '0') {
      return AiAssistantException(code, _asString(map['message']));
    }
    return AiAssistantException(
      status == 401
          ? 'UNAUTHORIZED'
          : status == 409
              ? 'CHAT_BUSY'
              : 'INVALID_INPUT',
      _asString(map['message']),
    );
  }
}

bool _isSuccessCode(dynamic code) {
  if (code is num) {
    return code == 0 || code == 200;
  }
  final text = code.toString().trim().toLowerCase();
  return text.isEmpty || text == '0' || text == 'ok' || text == 'success';
}

String _asString(dynamic value) => value?.toString().trim() ?? '';

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableId(dynamic value) {
  final text = _asString(value);
  return text.isEmpty ? null : text;
}
