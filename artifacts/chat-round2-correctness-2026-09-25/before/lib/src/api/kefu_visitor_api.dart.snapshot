import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/utils/dio_factory.dart';

class KefuVisitorContact {
  const KefuVisitorContact({
    required this.sourceId,
    required this.pubsubToken,
  });

  final String sourceId;
  final String pubsubToken;
}

class KefuVisitorAttachment {
  const KefuVisitorAttachment({
    required this.fileType,
    required this.dataUrl,
    required this.thumbUrl,
    required this.fileName,
    this.width = 0,
    this.height = 0,
  });

  final String fileType;
  final String dataUrl;
  final String thumbUrl;
  final String fileName;
  final int width;
  final int height;
}

class KefuVisitorMessage {
  const KefuVisitorMessage({
    required this.id,
    required this.content,
    required this.messageType,
    required this.echoId,
    required this.attachments,
  });

  final String id;
  final String content;
  final int messageType;
  final String echoId;
  final List<KefuVisitorAttachment> attachments;

  factory KefuVisitorMessage.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'];
    final attachments = <KefuVisitorAttachment>[];
    if (attachmentsRaw is List) {
      for (final row in attachmentsRaw) {
        if (row is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(row);
        var fileName = _firstString(map, const <String>[
          'file_name',
          'filename',
          'name',
        ]);
        if (fileName.isEmpty) {
          final ext = _firstString(map, const <String>['extension']);
          fileName = ext.isEmpty ? 'file' : 'file.$ext';
        }
        attachments.add(
          KefuVisitorAttachment(
            fileType: _parseFileType(map['file_type']),
            dataUrl: KefuVisitorApi.instance.resolveMediaUrl(
              _firstString(map, const <String>[
                'data_url',
                'dataUrl',
                'file_url',
                'fileUrl',
                'url',
              ]),
            ),
            thumbUrl: KefuVisitorApi.instance.resolveMediaUrl(
              _firstString(map, const <String>['thumb_url', 'thumbUrl']),
            ),
            fileName: fileName,
            width: _asInt(map['width']),
            height: _asInt(map['height']),
          ),
        );
      }
    }
    return KefuVisitorMessage(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: _parseMessageType(json),
      echoId: json['echo_id']?.toString() ?? json['echoId']?.toString() ?? '',
      attachments: attachments,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final text = map[key]?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

String _parseFileType(dynamic raw) {
  if (raw is int || raw is num) {
    switch (raw.toInt()) {
      case 0:
        return 'image';
      case 1:
        return 'audio';
      case 2:
        return 'video';
      default:
        return 'file';
    }
  }
  final text = raw?.toString().trim().toLowerCase() ?? '';
  switch (text) {
    case '0':
    case 'image':
      return 'image';
    case '1':
    case 'audio':
      return 'audio';
    case '2':
    case 'video':
      return 'video';
    default:
      return text.isEmpty ? 'file' : text;
  }
}

int _parseMessageType(Map<String, dynamic> json) {
  final sender = json['sender'];
  if (sender is Map) {
    final type = sender['type']?.toString().toLowerCase().trim() ?? '';
    if (type == 'contact') {
      return 0;
    }
    if (type == 'user' || type == 'agent' || type == 'agent_bot') {
      return 1;
    }
  }
  final raw = json['message_type'] ?? json['messageType'];
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case 'incoming':
      case '0':
        return 0;
      case 'outgoing':
      case '1':
        return 1;
      case 'activity':
      case '2':
        return 2;
      case 'template':
      case '3':
        return 3;
    }
  }
  return _asInt(raw);
}

class KefuVisitorApi {
  KefuVisitorApi._();

  static final KefuVisitorApi instance = KefuVisitorApi._();

  static const String inboxIdentifier = 'BDvRRToBN6sRG42N53AhxCc2';
  static const int maxAttachmentBytes = 40 * 1024 * 1024;

  Dio? _dio;
  String? _dioBase;

  String get kefuBase {
    final main = ApiClient.resolveBaseUrl().replaceAll(RegExp(r'/$'), '');
    return '$main/kefu';
  }

  Dio get _client {
    final base = kefuBase;
    if (_dio == null || _dioBase != base) {
      _dio = createAppDio(
        BaseOptions(
          baseUrl: base,
          connectTimeout: 30000,
          receiveTimeout: 120000,
          sendTimeout: 120000,
        ),
      );
      _dioBase = base;
    }
    return _dio!;
  }

  String resolveMediaUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final prefix = kefuBase.replaceAll(RegExp(r'/$'), '');
    final base = Uri.parse(prefix);
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    ).origin;
    if (trimmed.startsWith('//')) {
      return '${base.scheme}:$trimmed';
    }
    if (trimmed.startsWith('/kefu/')) {
      return '$origin$trimmed';
    }
    if (trimmed.startsWith('/')) {
      return '$prefix$trimmed';
    }
    return '$prefix/$trimmed';
  }

  String cableUrl() {
    final uri = Uri.parse(kefuBase);
    final scheme = uri.scheme.toLowerCase() == 'https' ? 'wss' : 'ws';
    final path =
        uri.path.endsWith('/') ? '${uri.path}cable' : '${uri.path}/cable';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  String _contactPath(String contactId) {
    return '/public/api/v1/inboxes/$inboxIdentifier/contacts/${Uri.encodeComponent(contactId)}';
  }

  String _messagesPath(String contactId, String conversationId) {
    return '${_contactPath(contactId)}/conversations/${Uri.encodeComponent(conversationId)}/messages';
  }

  Future<KefuVisitorContact> createContact({
    required String identifier,
    required String name,
    String avatarUrl = '',
  }) async {
    final res = await _client.post<dynamic>(
      '/public/api/v1/inboxes/$inboxIdentifier/contacts',
      data: _contactPayload(name: name, identifier: identifier, avatarUrl: avatarUrl),
      options: Options(contentType: 'application/json'),
    );
    final map = _asMap(_decode(res.data));
    final sourceId = map['source_id']?.toString().trim() ?? '';
    final pubsubToken = map['pubsub_token']?.toString().trim() ?? '';
    if (sourceId.isEmpty || pubsubToken.isEmpty) {
      throw StateError('kefu contact missing source_id or pubsub_token');
    }
    return KefuVisitorContact(sourceId: sourceId, pubsubToken: pubsubToken);
  }

  Future<void> updateContact({
    required String sourceId,
    required String name,
    String avatarUrl = '',
  }) async {
    await _client.patch<dynamic>(
      _contactPath(sourceId),
      data: _contactPayload(name: name, avatarUrl: avatarUrl),
      options: Options(contentType: 'application/json'),
    );
  }

  Map<String, dynamic> _contactPayload({
    required String name,
    String identifier = '',
    String avatarUrl = '',
  }) {
    final data = <String, dynamic>{
      'name': name,
    };
    if (identifier.trim().isNotEmpty) {
      data['identifier'] = identifier.trim();
    }
    final avatar = avatarUrl.trim();
    if (avatar.isNotEmpty) {
      data['avatar_url'] = avatar;
    }
    return data;
  }

  Future<String> createConversation(String contactId) async {
    final res = await _client.post<dynamic>(
      '${_contactPath(contactId)}/conversations',
      data: <String, dynamic>{},
      options: Options(contentType: 'application/json'),
    );
    final map = _asMap(_decode(res.data));
    final id = map['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw StateError('kefu conversation missing id');
    }
    return id;
  }

  Future<List<KefuVisitorMessage>> listMessages({
    required String contactId,
    required String conversationId,
  }) async {
    final res = await _client.get<dynamic>(
      _messagesPath(contactId, conversationId),
    );
    final rows = _asList(_decode(res.data));
    return rows
        .whereType<Map>()
        .map((row) => KefuVisitorMessage.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<KefuVisitorMessage> sendText({
    required String contactId,
    required String conversationId,
    required String content,
    required String echoId,
  }) async {
    final res = await _client.post<dynamic>(
      _messagesPath(contactId, conversationId),
      data: <String, dynamic>{
        'content': content,
        'echo_id': echoId,
      },
      options: Options(contentType: 'application/json'),
    );
    return KefuVisitorMessage.fromJson(_asMap(_decode(res.data)));
  }

  Future<KefuVisitorMessage> sendAttachments({
    required String contactId,
    required String conversationId,
    required String echoId,
    String content = '',
    required String filename,
    required String path,
    List<int>? bytes,
    int width = 0,
    int height = 0,
    String thumbnailPath = '',
    List<int>? thumbnailBytes,
  }) async {
    final multipart = await _multipartFile(
      filename: filename,
      path: path,
      bytes: bytes,
    );
    final form = FormData();
    form.fields.add(MapEntry('content', content));
    form.fields.add(MapEntry('echo_id', echoId));
    if (width > 0 && height > 0) {
      form.fields.add(MapEntry('width', '$width'));
      form.fields.add(MapEntry('height', '$height'));
    }
    form.files.add(MapEntry('attachments[]', multipart));
    final thumb = await _thumbnailFile(
      path: thumbnailPath,
      bytes: thumbnailBytes,
    );
    if (thumb != null) {
      form.files.add(MapEntry('thumbnail', thumb));
    }
    final res = await _client.post<dynamic>(
      _messagesPath(contactId, conversationId),
      data: form,
    );
    return KefuVisitorMessage.fromJson(_asMap(_decode(res.data)));
  }

  Future<MultipartFile?> _thumbnailFile({
    required String path,
    List<int>? bytes,
  }) async {
    final trimmed = path.trim();
    if (!kIsWeb && trimmed.isNotEmpty) {
      return MultipartFile.fromFile(
        trimmed,
        filename: 'cover.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
    }
    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(
        bytes,
        filename: 'cover.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
    }
    return null;
  }

  Future<MultipartFile> _multipartFile({
    required String filename,
    required String path,
    List<int>? bytes,
  }) async {
    final type = mediaTypeFor('$path $filename');
    if (!kIsWeb && path.trim().isNotEmpty) {
      return MultipartFile.fromFile(
        path,
        filename: filename,
        contentType: type,
      );
    }
    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: type,
      );
    }
    throw StateError('kefu attachment has no file bytes');
  }

  static MediaType mediaTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    if (lower.endsWith('.gif')) {
      return MediaType('image', 'gif');
    }
    if (lower.endsWith('.mp4')) {
      return MediaType('video', 'mp4');
    }
    if (lower.endsWith('.mov')) {
      return MediaType('video', 'quicktime');
    }
    if (lower.endsWith('.pdf')) {
      return MediaType('application', 'pdf');
    }
    return MediaType('application', 'octet-stream');
  }

  dynamic _decode(dynamic data) {
    if (data is String && data.trim().isNotEmpty) {
      return jsonDecode(data);
    }
    return data;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      if (map.containsKey('source_id') ||
          map.containsKey('attachments') ||
          map.containsKey('message_type') ||
          map.containsKey('echo_id') ||
          (map.containsKey('id') && map.containsKey('content'))) {
        return map;
      }
      final payload = map['payload'];
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return map;
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic raw) {
    if (raw is List) {
      return raw;
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in <String>['payload', 'messages', 'data']) {
        final value = map[key];
        if (value is List) {
          return value;
        }
      }
    }
    return const <dynamic>[];
  }
}
