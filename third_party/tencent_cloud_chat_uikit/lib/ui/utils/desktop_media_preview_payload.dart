import 'dart:convert';
import 'dart:io';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_img_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_header_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

class DesktopMediaPreviewPayload {
  static const kindMedia = 'media';

  static Map<String, dynamic> fromChat({
    required List<V2TimMessage> originList,
    required V2TimMessage tappedMessage,
    required Set<ChatMediaPreviewType> types,
    required ChatMediaHeroTagBuilder heroTagBuilder,
    String? conversationID,
    ConvType? conversationType,
    bool allowForward = true,
    bool fitTallImagesToScreenWidth = true,
  }) {
    final preview = buildChatMediaPreviewItems(
      originList: originList,
      tappedMessage: tappedMessage,
      types: types,
      heroTagBuilder: heroTagBuilder,
    );
    final items = <Map<String, dynamic>>[];
    for (final item in preview.items) {
      items.add(_itemFromChat(item));
    }
    return {
      'kind': kindMedia,
      'source': 'chat',
      'initialIndex': preview.initialIndex,
      'downloadOnly': false,
      'allowForward': allowForward,
      'fitTallImagesToScreenWidth': fitTallImagesToScreenWidth,
      'conversationID': conversationID ?? '',
      'conversationType': conversationType?.index ?? ConvType.c2c.index,
      'items': items,
    };
  }

  static Map<String, dynamic> image({
    required String source,
    String? url,
    String? localPath,
    String? assetPath,
    String? assetPackage,
    String? headerTitle,
    bool downloadOnly = true,
    bool allowForward = false,
    bool fitTallImagesToScreenWidth = false,
    String? originalPath,
  }) {
    return {
      'kind': kindMedia,
      'source': source,
      'initialIndex': 0,
      'downloadOnly': downloadOnly,
      'allowForward': allowForward,
      'fitTallImagesToScreenWidth': fitTallImagesToScreenWidth,
      'items': [
        {
          'type': 'image',
          'heroTag': '',
          'headerTitle': headerTitle ?? '',
          'url': url ?? '',
          'localPath': localPath ?? '',
          'assetPath': assetPath ?? '',
          'assetPackage': assetPackage ?? '',
          'originalPath': originalPath ?? '',
        },
      ],
    };
  }

  static Map<String, dynamic> images({
    required String source,
    required List<Map<String, dynamic>> items,
    int initialIndex = 0,
    bool downloadOnly = false,
    bool allowForward = true,
    bool fitTallImagesToScreenWidth = false,
  }) {
    return {
      'kind': kindMedia,
      'source': source,
      'initialIndex': initialIndex,
      'downloadOnly': downloadOnly,
      'allowForward': allowForward,
      'fitTallImagesToScreenWidth': fitTallImagesToScreenWidth,
      'items': items,
    };
  }

  static Map<String, dynamic> video({
    required String source,
    String? videoUrl,
    String? localPath,
    String? headerTitle,
    bool allowForward = false,
    String? originalPath,
    int? width,
    int? height,
  }) {
    return {
      'kind': kindMedia,
      'source': source,
      'initialIndex': 0,
      'downloadOnly': false,
      'allowForward': allowForward,
      'items': [
        {
          'type': 'video',
          'heroTag': '',
          'headerTitle': headerTitle ?? '',
          'videoUrl': videoUrl ?? '',
          'localVideoUrl': localPath ?? '',
          'videoPath': localPath ?? '',
          'originalPath': originalPath ?? '',
          'width': width ?? 0,
          'height': height ?? 0,
        },
      ],
    };
  }

  static Map<String, dynamic> _itemFromChat(ChatMediaPreviewItem item) {
    final message = item.message;
    final mapped = <String, dynamic>{
      'type': item.type == ChatMediaPreviewType.video ? 'video' : 'image',
      'heroTag': item.heroTag.toString(),
      'messageID': item.messageID ?? message.msgID ?? '',
      'headerTitle': item.headerTitle ??
          MediaPreviewHeaderUtils.titleForMessage(message),
      'headerSubtitle': item.headerSubtitle ??
          MediaPreviewHeaderUtils.subtitleForMessage(message.timestamp),
      'message': _safeMessageJson(message),
    };
    if (item.type == ChatMediaPreviewType.video) {
      final video = item.videoElement ?? message.videoElem;
      mapped['videoUrl'] = video?.videoUrl ?? '';
      mapped['localVideoUrl'] = video?.localVideoUrl ?? '';
      mapped['videoPath'] = video?.videoPath ?? '';
      mapped['snapshotUrl'] = video?.snapshotUrl ?? '';
      mapped['snapshotPath'] =
          video?.snapshotPath ?? video?.localSnapshotUrl ?? '';
      mapped['width'] = video?.snapshotWidth ?? 0;
      mapped['height'] = video?.snapshotHeight ?? 0;
    } else {
      _fillImageSources(message, mapped);
    }
    return mapped;
  }

  static void _fillImageSources(
    V2TimMessage message,
    Map<String, dynamic> mapped,
  ) {
    final elem = message.imageElem;
    String? localPath;
    String? originalLocalPath;
    String? originalUrl;
    String? bigUrl;
    String? smallUrl;
    int? originalWidth;
    int? originalHeight;
    int? bigWidth;
    int? bigHeight;
    int? otherWidth;
    int? otherHeight;
    if (elem != null) {
      if (_fileExists(elem.path)) {
        localPath = elem.path;
        if (message.isSelf == true) {
          originalLocalPath = elem.path;
        }
      }
      for (final img in elem.imageList ?? const []) {
        if (img == null) {
          continue;
        }
        if (_fileExists(img.localUrl)) {
          localPath ??= img.localUrl;
          if (img.type ==
              HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['ORIGINAL']) {
            originalLocalPath ??= img.localUrl;
          }
        }
        final type = img.type;
        final width = img.width;
        final height = img.height;
        if (width != null && height != null && width > 0 && height > 0) {
          if (type == HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['ORIGINAL']) {
            originalWidth = width;
            originalHeight = height;
          } else if (type ==
              HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['BIG']) {
            bigWidth = width;
            bigHeight = height;
          } else {
            otherWidth ??= width;
            otherHeight ??= height;
          }
        }
        final url = img.url;
        if (url == null || url.isEmpty) {
          continue;
        }
        if (type == HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['ORIGINAL']) {
          originalUrl = url;
        } else if (type ==
            HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['BIG']) {
          bigUrl = url;
        } else if (type ==
            HistoryMessageDartConstant.V2_TIM_IMAGE_TYPES['SMALL']) {
          smallUrl = url;
        } else {
          originalUrl ??= url;
        }
      }
    }
    mapped['originalUrl'] = originalUrl ?? '';
    mapped['originalLocalPath'] = originalLocalPath ?? '';
    mapped['smallUrl'] = smallUrl ?? '';
    mapped['bigUrl'] = bigUrl ?? '';
    mapped['url'] = (originalUrl != null && originalUrl.isNotEmpty)
        ? originalUrl
        : (bigUrl ?? smallUrl ?? '');
    // 原图本地文件才进 localPath。气泡 BIG/SMALL 缓存走 previewLocalPath，供首屏小图。
    mapped['localPath'] = originalLocalPath ?? '';
    mapped['previewLocalPath'] = localPath ?? '';
    mapped['width'] = originalWidth ?? bigWidth ?? otherWidth ?? 0;
    mapped['height'] = originalHeight ?? bigHeight ?? otherHeight ?? 0;
    ChatImgTrace.log(
      '[ChatImg] event=popout_payload_image '
      'orig=${originalUrl != null && originalUrl.isNotEmpty} '
      'big=${bigUrl != null && bigUrl.isNotEmpty} '
      'small=${smallUrl != null && smallUrl.isNotEmpty} '
      'diskAny=${localPath != null && localPath.isNotEmpty} '
      'originLocal=${originalLocalPath != null && originalLocalPath.isNotEmpty} '
      'payloadLocal=${originalLocalPath != null && originalLocalPath.isNotEmpty} '
      'origSize=${originalWidth ?? 0}x${originalHeight ?? 0} '
      'bigSize=${bigWidth ?? 0}x${bigHeight ?? 0} '
      'mapped=${originalUrl != null && originalUrl.isNotEmpty ? 'origin' : bigUrl != null && bigUrl.isNotEmpty ? 'big' : 'small_or_empty'}',
    );
  }

  static Map<String, dynamic>? _safeMessageJson(V2TimMessage message) {
    try {
      final json = message.toJson();
      jsonEncode(json);
      return json;
    } catch (_) {
      return {
        'message_msg_id': message.msgID,
        'elem_type': message.elemType,
      };
    }
  }

  static bool _fileExists(String? path) {
    if (path == null || path.isEmpty || PlatformUtils().isWeb) {
      return false;
    }
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
