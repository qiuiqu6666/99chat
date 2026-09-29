import 'dart:convert';
import 'dart:math' as math;

/// The wire protocol is independent of Tencent's native media element types.
class ChatAttachment {
  const ChatAttachment({
    required this.attachmentId,
    required this.referenceId,
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.thumbnailAttachmentId,
  });

  static const type = 'chat.attachment';
  static const protocolVersion = 1;
  final String attachmentId;
  final String referenceId;
  final String kind;
  final String name;
  final int sizeBytes;
  final String mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final String? thumbnailAttachmentId;

  static ChatAttachment? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 16384) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      return fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  static ChatAttachment? fromJson(Map<String, dynamic> data) {
    if (data['type'] != type || data['version'] != protocolVersion) return null;
    final id = attachmentString(data['attachmentId']);
    final ref = attachmentString(data['referenceId']);
    final kind = attachmentString(data['kind']);
    final size = attachmentInt(data['sizeBytes']);
    if (id.isEmpty ||
        ref.isEmpty ||
        size <= 0 ||
        !const {'image', 'video', 'audio', 'file'}.contains(kind)) {
      return null;
    }
    return ChatAttachment(
      attachmentId: id,
      referenceId: ref,
      kind: kind,
      name: attachmentString(data['name']),
      sizeBytes: size,
      mimeType: attachmentString(data['mimeType']),
      durationMs: attachmentPositiveInt(data['durationMs']),
      width: attachmentPositiveInt(data['width']),
      height: attachmentPositiveInt(data['height']),
      thumbnailAttachmentId:
          attachmentOptionalString(data['thumbnailAttachmentId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': protocolVersion,
        'attachmentId': attachmentId,
        'referenceId': referenceId,
        'kind': kind,
        'name': name,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
        if (durationMs != null) 'durationMs': durationMs,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (thumbnailAttachmentId != null)
          'thumbnailAttachmentId': thumbnailAttachmentId,
      };

  String get label => switch (kind) {
        'image' => '[图片]',
        'video' => '[视频]',
        'audio' => '[音频]',
        _ => '[文件]',
      };
  String get preview => '$label ${name.isEmpty ? "附件" : name}';
}

class ChatAttachmentPolicy {
  const ChatAttachmentPolicy({
    this.uploadEnabled = false,
    this.nativeVideoMessageEnabled = false,
    this.sendEnabled = false,
    this.readEnabled = true,
    this.routingThresholdBytes = 104857600,
    this.nativeMaxBytes = const {
      'image': 29360128,
      'sound': 29360128,
      'video': 104857600,
      'file': 104857600
    },
    this.maxAttachmentBytes = 2147483648,
    this.partSizeBytes = 8388608,
    this.maxParallelPartsPerUpload = 2,
    this.policyVersion = '',
  });
  final bool uploadEnabled;
  final bool nativeVideoMessageEnabled;
  final bool sendEnabled;
  final bool readEnabled;
  final int routingThresholdBytes;
  final Map<String, int> nativeMaxBytes;
  final int maxAttachmentBytes;
  final int partSizeBytes;
  final int maxParallelPartsPerUpload;
  final String policyVersion;

  factory ChatAttachmentPolicy.fromJson(Map<String, dynamic> json) {
    if (json['sizeComparison'] != 'strictGreaterThan') {
      throw const ChatAttachmentException('INVALID_RESPONSE', '附件大小策略不兼容');
    }
    final native = attachmentMap(json['nativeMaxBytes']);
    final limits = <String, int>{};
    for (final kind in const ['image', 'sound', 'video', 'file']) {
      final limit = attachmentInt(native[kind]);
      if (limit <= 0) {
        throw const ChatAttachmentException('INVALID_RESPONSE', '附件大小策略不完整');
      }
      limits[kind] = limit;
    }
    final threshold = attachmentInt(json['routingThresholdBytes']);
    if (threshold <= 0) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '附件分流阈值无效');
    }
    return ChatAttachmentPolicy(
      uploadEnabled: json['uploadEnabled'] == true,
      nativeVideoMessageEnabled: json['nativeVideoMessageEnabled'] == true,
      sendEnabled: json['sendEnabled'] == true,
      readEnabled: json['readEnabled'] == true,
      routingThresholdBytes: threshold,
      nativeMaxBytes: Map.unmodifiable(limits),
      maxAttachmentBytes:
          attachmentPositiveInt(json['maxAttachmentBytes']) ?? 2147483648,
      partSizeBytes: attachmentPositiveInt(json['partSizeBytes']) ?? 8388608,
      maxParallelPartsPerUpload: math.min(
          2, attachmentPositiveInt(json['maxParallelPartsPerUpload']) ?? 2),
      policyVersion: attachmentString(json['policyVersion']),
    );
  }

  bool routesToBackend(int size, String nativeKind) {
    final limit = nativeMaxBytes[nativeKind];
    if (limit == null || size <= 0) {
      throw const ChatAttachmentException('INVALID_ATTACHMENT', '附件类型或大小无效');
    }
    return size > math.min(routingThresholdBytes, limit);
  }
}

class ChatAttachmentTarget {
  const ChatAttachmentTarget({required this.isGroup, required this.id});
  factory ChatAttachmentTarget.fromConversationId(String conversationId,
      {required bool isGroup}) {
    final prefix = isGroup ? 'group_' : 'c2c_';
    final value = conversationId.trim();
    return ChatAttachmentTarget(
        isGroup: isGroup,
        id: value.startsWith(prefix) ? value.substring(prefix.length) : value);
  }
  final bool isGroup;
  final String id;
  Map<String, dynamic> toJson() => {
        'conversationType': isGroup ? 'group' : 'c2c',
        if (isGroup) 'groupId': id else 'peerUserId': id,
      };
  String get key => '${isGroup ? "group" : "c2c"}:$id';
}

/// Ephemeral playback grants are never serialized into a message or cache index.
class ChatAttachmentPlayback {
  const ChatAttachmentPlayback(this.location,
      {this.local = false, this.headers = const {}});
  final String location;
  final bool local;
  final Map<String, String> headers;
}

class ChatAttachmentException implements Exception {
  const ChatAttachmentException(this.code, this.message, {this.retryAfter});
  final String code;
  final String message;
  final Duration? retryAfter;
  bool get retryable => const {
        'NETWORK_ERROR',
        'STORAGE_UNAVAILABLE',
        'RATE_LIMITED',
        'PART_MISSING',
        'ATTACHMENT_NOT_READY',
        'URL_EXPIRED',
      }.contains(code);
  String get userMessage => switch (code) {
        'ATTACHMENT_DISABLED' => '大附件发送暂未开放',
        'NATIVE_CHANNEL_REQUIRED' => '此附件应使用普通发送通道，请重新选择发送',
        'FILE_TOO_LARGE' => '附件超过大小限制或文件大小已改变',
        'QUOTA_EXCEEDED' => '存储、每日上传额度或并发任务已达上限',
        'CONVERSATION_FORBIDDEN' => '当前会话暂不支持大附件，请确认权限及双方版本',
        'UPLOAD_EXPIRED' => '上传任务已过期或已取消，请重新发送',
        'ATTACHMENT_EXPIRED' => '附件已过期（云端保留 30 天）',
        'ATTACHMENT_GONE' => '云端附件已失效或不可用',
        'ACCESS_DENIED' => '没有访问此附件的权限',
        'SESSION_CHANGED' => '账号已切换，任务已暂停',
        'CANCELLED' => '任务已暂停',
        'LOCAL_FILE_MISSING' => '本地文件不可用，请重新选择',
        'STORAGE_UNAVAILABLE' => '附件存储暂不可用，请稍后重试',
        'RATE_LIMITED' => retryAfter == null
            ? '请求过于频繁，请稍后重试'
            : '请求过于频繁，请 ${retryAfter!.inSeconds} 秒后重试',
        'NETWORK_ERROR' => '网络中断，请重试',
        'IDEMPOTENCY_CONFLICT' => '发送任务信息冲突，请重新选择文件发送',
        'OUTCOME_UNKNOWN' => '发送结果待确认，请勿重复发送',
        _ => message.isNotEmpty ? message : '附件操作失败，请重试',
      };
  @override
  String toString() => '$code: $userMessage';
}

Map<String, dynamic> attachmentMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String attachmentString(dynamic value) => value is String
    ? value.trim()
    : value is num
        ? value.toString()
        : '';
String? attachmentOptionalString(dynamic value) {
  final text = attachmentString(value);
  return text.isEmpty ? null : text;
}

int attachmentInt(dynamic value) =>
    value is int ? value : int.tryParse('$value') ?? 0;
int? attachmentPositiveInt(dynamic value) {
  final n = attachmentInt(value);
  return n > 0 ? n : null;
}

DateTime? attachmentDate(dynamic value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

String attachmentSizeLabel(int bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(2)} GiB';
  }
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}
