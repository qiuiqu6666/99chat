import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Flutter 与移动端原生媒体预览之间的唯一协议入口。
///
/// 旧的 Flutter 预览页面暂时保留，但移动端切换完成后只通过这里打开
/// Android Activity / iOS ViewController。媒体资源使用路径或 URL 传输，
/// 不把图片/视频二进制塞进 MethodChannel。
class NativeMediaPreviewBridge {
  NativeMediaPreviewBridge._();

  static const MethodChannel _channel =
      MethodChannel('ninechat/native_media_preview');
  static const EventChannel _events =
      EventChannel('ninechat/native_media_preview_events');

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static NativeMediaPreviewItem itemFromMessage(V2TimMessage message) {
    final image = message.imageElem;
    final video = message.videoElem;
    final isVideo = video != null;
    final imageOrigin = image?.imageList?.isNotEmpty == true
        ? image!.imageList!.last
        : null;
    return NativeMediaPreviewItem(
      messageId: (message.msgID ?? message.id?.toString() ?? '').trim(),
      type: isVideo ? 'video' : 'image',
      remoteUrl: isVideo ? video?.videoUrl : imageOrigin?.url,
      localPath: isVideo ? video?.videoPath : image?.path,
      width: isVideo ? video?.snapshotWidth?.toDouble() : imageOrigin?.width?.toDouble(),
      height: isVideo ? video?.snapshotHeight?.toDouble() : imageOrigin?.height?.toDouble(),
      durationMs: isVideo ? ((video?.duration ?? 0) * 1000) : null,
    );
  }

  static Stream<NativeMediaPreviewResult> get results => _events
      .receiveBroadcastStream()
      .map((event) => NativeMediaPreviewResult.fromMap(
            Map<String, Object?>.from(event as Map),
          ));

  static Future<NativeMediaPreviewResult> open({
    required String conversationId,
    required List<NativeMediaPreviewItem> items,
    required int initialIndex,
    bool allowDownload = true,
    bool allowForward = true,
    bool allowDelete = true,
  }) async {
    if (!supported) {
      throw UnsupportedError('Native media preview is mobile-only');
    }
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'open',
      <String, Object?>{
        'conversationId': conversationId,
        'initialIndex': initialIndex.clamp(0, items.length - 1),
        'items': items.map((item) => item.toMap()).toList(growable: false),
        'permissions': <String, Object?>{
          'download': allowDownload,
          'forward': allowForward,
          'delete': allowDelete,
        },
      },
    );
    return NativeMediaPreviewResult.fromMap(result ?? const {});
  }
}

class NativeMediaPreviewItem {
  const NativeMediaPreviewItem({
    required this.messageId,
    required this.type,
    this.remoteUrl,
    this.localPath,
    this.thumbnailUrl,
    this.senderName,
    this.timestamp,
    this.width,
    this.height,
    this.durationMs,
    this.sourceRect,
    this.sourceThumbnailPath,
  });

  final String messageId;
  final String type;
  final String? remoteUrl;
  final String? localPath;
  final String? thumbnailUrl;
  final String? senderName;
  final int? timestamp;
  final double? width;
  final double? height;
  final int? durationMs;
  final Map<String, double>? sourceRect;
  final String? sourceThumbnailPath;

  Map<String, Object?> toMap() => <String, Object?>{
        'messageId': messageId,
        'type': type,
        'remoteUrl': remoteUrl,
        'localPath': localPath,
        'thumbnailUrl': thumbnailUrl,
        'senderName': senderName,
        'timestamp': timestamp,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'sourceRect': sourceRect,
        'sourceThumbnailPath': sourceThumbnailPath,
      };
}

class NativeMediaPreviewResult {
  const NativeMediaPreviewResult({
    required this.reason,
    this.operation,
    this.finalIndex,
    this.messageId,
    this.playbackPositionMs,
    this.errorCode,
    this.errorMessage,
  });

  factory NativeMediaPreviewResult.fromMap(Map<String, Object?> map) {
    return NativeMediaPreviewResult(
      reason: map['reason']?.toString() ?? 'close',
      operation: map['operation']?.toString(),
      finalIndex: (map['finalIndex'] as num?)?.toInt(),
      messageId: map['messageId']?.toString(),
      playbackPositionMs: (map['playbackPositionMs'] as num?)?.toInt(),
      errorCode: map['errorCode']?.toString(),
      errorMessage: map['errorMessage']?.toString(),
    );
  }

  final String reason;
  final String? operation;
  final int? finalIndex;
  final String? messageId;
  final int? playbackPositionMs;
  final String? errorCode;
  final String? errorMessage;
}
