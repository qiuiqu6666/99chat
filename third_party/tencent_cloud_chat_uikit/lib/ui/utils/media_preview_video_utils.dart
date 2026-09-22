import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_class.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_network_url.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/permission.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';
import 'package:universal_html/html.dart' as html;

export 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_network_url.dart';

const SystemUiOverlayStyle mediaPreviewVideoOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

int _mediaPreviewSystemUiGeneration = 0;

Future<void> applySystemUiForMediaPreview() async {
  _mediaPreviewSystemUiGeneration++;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(mediaPreviewVideoOverlayStyle);
}

Future<void> restoreSystemUiAfterMediaPreview({
  SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle.dark,
  Duration delay = Duration.zero,
  bool applyOverlayStyle = false,
}) async {
  final generation = ++_mediaPreviewSystemUiGeneration;
  if (delay > Duration.zero) {
    await Future<void>.delayed(delay);
  }
  if (generation != _mediaPreviewSystemUiGeneration) {
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (applyOverlayStyle) {
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
  }
  noteVideoPlaybackRestoredToPortrait();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await WidgetsBinding.instance.endOfFrame;
  if (generation != _mediaPreviewSystemUiGeneration) {
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (applyOverlayStyle) {
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
  }
}

bool? _videoPlaybackLandscapeLock;

/// 横/竖分类未变时返回 false，调用方应跳过 SystemChrome，避免进场抖动。
bool noteVideoPlaybackLandscapeLock(bool landscape) {
  if (_videoPlaybackLandscapeLock == landscape) {
    return false;
  }
  _videoPlaybackLandscapeLock = landscape;
  return true;
}

void noteVideoPlaybackRestoredToPortrait() {
  _videoPlaybackLandscapeLock = false;
}

/// Leave enough time for the thumbnail to expand without a sharp visual jump.
const Duration mediaPreviewBackdropDuration = Duration(milliseconds: 340);
const Duration mediaPreviewCloseDuration = Duration(milliseconds: 280);

/// A symmetric fade avoids holding a dark backdrop until the last pop frames.
const Curve mediaPreviewBackdropCurve = Curves.easeInOut;
const Curve mediaPreviewBackdropReverseCurve = Curves.easeInOut;

const double mediaPreviewVideoBottomOverlayReserve = 56;

bool _mediaPreviewAudioSessionWarmedUp = false;

/// iOS 预览前预热音频会话 category，减轻播放时主线程 setActive 阻塞。
Future<void> warmUpMediaPreviewAudioSession() async {
  if (!Platform.isIOS || _mediaPreviewAudioSessionWarmedUp) {
    return;
  }
  _mediaPreviewAudioSessionWarmedUp = true;
  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
      ),
    );
  } catch (_) {}
}

/// 下滑位移由 SlidePage 处理；缩放由 [MediaPreviewSlideMetrics] 下发到图片本体
///（[MediaPreviewSlideVisualScope]），避免全屏中心缩放导致小图回吸跳动。
/// 视频全屏也复用微信式下滑缩放，提供跟手反馈。
double mediaPreviewSlideScaleHandler(
  Offset offset, {
  ExtendedImageSlidePageState? state,
}) {
  // 视频全屏下滑时也跟手缩小，与图片预览行为一致。
  return mediaPreviewWeChatSlideScale(offset);
}

/// 微信式下滑缩放：随位移缩小，约半屏时到 ~0.55。
double mediaPreviewWeChatSlideScale(
  Offset offset, {
  double referenceDy = 520,
}) {
  final t = (offset.dy.abs() / referenceDy).clamp(0.0, 1.0);
  return (1.0 - 0.42 * Curves.easeOut.transform(t)).clamp(0.55, 1.0);
}

/// 跟手时内容透明度（轻微变淡，与离场淡出连贯）。
double mediaPreviewWeChatDragContentOpacity(
  Offset offset, {
  required Size size,
}) {
  final span = size.height <= 0 ? 800.0 : size.height;
  final t = (offset.dy.abs() / (span * 0.9)).clamp(0.0, 1.0);
  return (1.0 - 0.22 * t).clamp(0.78, 1.0);
}

/// 滑动时透明，由 [mediaPreviewScrimOpacityForSlideOffset] 控制全屏黑遮罩透明度。
Color mediaPreviewSlideBackgroundHandler(Offset offset, Size size) =>
    Colors.transparent;

/// 静止时 1.0（全黑）；随下滑位移增大而降低，露出下层聊天页。
double mediaPreviewScrimOpacityForSlideOffset(Offset offset, Size size) {
  final denominator = Offset(size.width, size.height).distance / 2.0;
  if (denominator <= 0) {
    return 1.0;
  }
  final progress = offset.distance / denominator;
  return (1.0 - progress).clamp(0.0, 1.0);
}

String? existingLocalMediaPath(String? path) {
  final value = TencentUtils.checkString(path);
  if (value == null || PlatformUtils().isWeb) {
    return null;
  }
  return File(value).existsSync() ? value : null;
}

double resolveVideoAspectRatio(V2TimVideoElem elem) {
  final width = elem.snapshotWidth;
  final height = elem.snapshotHeight;
  if (width != null && height != null && height > 0) {
    return width / height;
  }
  return 9 / 16;
}

bool videoElemHasSnapshotSource(V2TimVideoElem elem) {
  return existingLocalMediaPath(elem.snapshotPath) != null ||
      existingLocalMediaPath(elem.localSnapshotUrl) != null ||
      TencentUtils.checkString(elem.snapshotUrl) != null;
}

V2TimVideoElem mergeVideoElemKeepingLocalPreview(
  V2TimVideoElem current,
  V2TimVideoElem incoming,
) {
  incoming.snapshotPath = TencentUtils.checkString(incoming.snapshotPath) ??
      TencentUtils.checkString(current.snapshotPath);
  incoming.localSnapshotUrl =
      TencentUtils.checkString(incoming.localSnapshotUrl) ??
          TencentUtils.checkString(current.localSnapshotUrl);
  incoming.videoPath = TencentUtils.checkString(incoming.videoPath) ??
      TencentUtils.checkString(current.videoPath);
  incoming.localVideoUrl = TencentUtils.checkString(incoming.localVideoUrl) ??
      TencentUtils.checkString(current.localVideoUrl);
  incoming.snapshotWidth ??= current.snapshotWidth;
  incoming.snapshotHeight ??= current.snapshotHeight;
  incoming.duration ??= current.duration;
  return incoming;
}

/// 全屏预览封面解码宽度（高于气泡缩略图，减轻拉伸发糊）。
int mediaPreviewSnapshotCacheWidth(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final longest = math.max(size.width, size.height);
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (longest * dpr).round().clamp(512, 2048);
}

/// 全屏预览 Hero 飞行用静态封面（勿把 [VideoPlayer] 平台视图包进 Hero）。
Widget buildMediaPreviewVideoSnapshot(
  BuildContext context,
  V2TimVideoElem elem,
) {
  final cacheWidth = mediaPreviewSnapshotCacheWidth(context);
  final screenSize = MediaQuery.sizeOf(context);

  Widget wrapFullScreen(Widget image) {
    return SizedBox(
      width: screenSize.width,
      height: screenSize.height,
      child: image,
    );
  }

  if (!PlatformUtils().isWeb) {
    final snapshotPath = TencentUtils.checkString(elem.snapshotPath);
    if (snapshotPath != null && File(snapshotPath).existsSync()) {
      return wrapFullScreen(
        Image.file(
          File(snapshotPath),
          fit: BoxFit.contain,
          width: screenSize.width,
          height: screenSize.height,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    final localSnapshot = TencentUtils.checkString(elem.localSnapshotUrl);
    if (localSnapshot != null && File(localSnapshot).existsSync()) {
      return wrapFullScreen(
        Image.file(
          File(localSnapshot),
          fit: BoxFit.contain,
          width: screenSize.width,
          height: screenSize.height,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
  }
  final snapshotUrl = TencentUtils.checkString(elem.snapshotUrl);
  if (snapshotUrl != null) {
    return wrapFullScreen(
      buildChatMediaSnapshotImage(
        snapshotUrl,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        width: screenSize.width,
        height: screenSize.height,
      ),
    );
  }
  // 无封面时用纯黑占位，避免 Overlay(opaque:false) 透出聊天灰底。
  return wrapFullScreen(const ColoredBox(color: Colors.black));
}

Widget buildChatMediaSnapshotImage(
  String rawUrl, {
  BoxFit fit = BoxFit.contain,
  int? cacheWidth,
  double? width,
  double? height,
}) {
  final resolved = resolveChatMediaNetworkUrl(rawUrl.trim());
  if (resolved.isEmpty) {
    return const SizedBox.shrink();
  }
  return Image.network(
    resolved,
    fit: fit,
    width: width,
    height: height,
    gaplessPlayback: true,
    headers: chatMediaNetworkHeaders(resolved),
    cacheWidth: cacheWidth,
  );
}

double mediaPreviewBottomOverlayOffset(BuildContext context) {
  return 16.0 + MediaQuery.paddingOf(context).bottom;
}

EdgeInsets mediaPreviewVideoContentPadding(
  BuildContext context, {
  bool includeBottomOverlayReserve = true,
}) {
  final bottom = MediaQuery.paddingOf(context).bottom +
      (includeBottomOverlayReserve ? mediaPreviewVideoBottomOverlayReserve : 0);
  return EdgeInsets.only(bottom: bottom);
}

bool saveVideoResultSuccess(dynamic result) {
  if (result is Map) {
    final raw = result['isSuccess'] ?? result['success'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true';
    if (raw is num) return raw != 0;
  }
  return false;
}

void notifySaveVideoResult(
  BuildContext context, {
  required bool success,
}) {
  TIMUIKitClass.onTIMCallback(TIMCallback(
    type: TIMCallbackType.INFO,
    infoRecommendText: TIM_t(success ? '视频保存成功' : '视频保存失败'),
    infoCode: success ? 6660402 : 6660403,
  ));
  if (!context.mounted) return;
  MediaPreviewSaveNotice.show(
    context,
    success: success,
    kind: MediaPreviewSaveKind.video,
  );
}

/// Stream the complete remote original to disk before invoking the Photos API.
/// A failed or non-media response must never be handed to the gallery plugin.
Future<File> downloadVideoForGallery(String url, Directory directory,
    {Map<String, String>? headers}) async {
  final uri = Uri.parse(url);
  if (!const ['https', 'http'].contains(uri.scheme)) {
    throw const FormatException('Invalid video URL');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  File? file;
  try {
    final request = await client.getUrl(uri);
    headers?.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final mime = response.headers.contentType?.mimeType ?? '';
    if (response.statusCode != HttpStatus.ok ||
        (mime.isNotEmpty &&
            !mime.startsWith('video/') &&
            mime != 'application/octet-stream')) {
      throw const HttpException('Invalid video response');
    }
    final extension = mime == 'video/quicktime' ? 'mov' : 'mp4';
    file = File('${directory.path}/video.$extension');
    await response.timeout(const Duration(seconds: 60)).pipe(file.openWrite());
    final size = await file.length();
    if (size == 0 ||
        (response.contentLength >= 0 && size != response.contentLength)) {
      throw const HttpException('Incomplete video response');
    }
    return file;
  } catch (_) {
    if (file != null && await file.exists()) await file.delete();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

Future<void> saveNetworkVideoFile(
  BuildContext context, {
  required TUIChatGlobalModel model,
  required V2TimMessage message,
  required String videoUrl,
  bool isAsset = true,
}) async {
  if (PlatformUtils().isWeb) {
    final exp = RegExp(r'((\.){1}[^?]{2,4})');
    final suffix = exp.allMatches(videoUrl).last.group(0);
    final xhr = html.HttpRequest();
    xhr.open('get', videoUrl);
    xhr.responseType = 'arraybuffer';
    xhr.onLoad.listen((event) {
      final a = html.AnchorElement(
        href: html.Url.createObjectUrl(html.Blob([xhr.response])),
      );
      a.download = '${md5.convert(utf8.encode(videoUrl)).toString()}$suffix';
      a.click();
      a.remove();
    });
    xhr.send();
    return;
  }
  if (PlatformUtils().isMobile) {
    debugPrint('[VideoSave] stage=permission');
    if (PlatformUtils().isIOS) {
      if (!await Permissions.checkPermission(
        context,
        Permission.photosAddOnly.value,
      )) {
        debugPrint('[VideoSave] stage=permission_denied');
        return;
      }
    } else {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (!context.mounted) return;
      if (androidInfo.version.sdkInt < 29) {
        final storage = await Permissions.checkPermission(
          context,
          Permission.storage.value,
        );
        if (!storage) {
          return;
        }
      }
    }
  }

  if (!context.mounted) return;
  OverlayEntry? loadingEntry;
  void hideLoading() {
    loadingEntry?.remove();
    loadingEntry?.dispose();
    loadingEntry = null;
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) {
    loadingEntry = OverlayEntry(
        builder: (_) => Stack(children: [
              const ModalBarrier(dismissible: false, color: Colors.black26),
              Center(
                  child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(height: 16),
                    Text(TIM_t('正在保存视频…')),
                  ]),
                ),
              )),
            ]));
    overlay.insert(loadingEntry!);
  }
  Directory? downloadDirectory;
  try {
    await WidgetsBinding.instance.endOfFrame;
    var savePath = videoUrl;
    if (!isAsset) {
      final local = message.videoElem?.localVideoUrl;
      final cached = message.msgID == null ||
              model.getMessageProgress(message.msgID!) != 100
          ? ''
          : model.getFileMessageLocation(message.msgID!);
      if (local != null && local.isNotEmpty && File(local).existsSync()) {
        savePath = local;
      } else if (cached.isNotEmpty && File(cached).existsSync()) {
        savePath = cached;
      } else {
        final resolvedUrl = resolveChatMediaNetworkUrl(videoUrl);
        debugPrint(
            '[VideoSave] stage=download scheme=${Uri.tryParse(resolvedUrl)?.scheme}');
        downloadDirectory = await (await getTemporaryDirectory())
            .createTemp('chat-video-save-');
        final file = await downloadVideoForGallery(
          resolvedUrl,
          downloadDirectory,
          headers: chatMediaNetworkHeaders(resolvedUrl),
        );
        savePath = file.path;
      }
    }
    if (!context.mounted) return;
    debugPrint('[VideoSave] stage=photos_write');
    final result = await ImageGallerySaverPlus.saveFile(savePath);
    debugPrint(
        '[VideoSave] stage=complete success=${saveVideoResultSuccess(result)}');
    if (!context.mounted) return;
    hideLoading();
    notifySaveVideoResult(context, success: saveVideoResultSuccess(result));
  } catch (error) {
    hideLoading();
    debugPrint('Video save failed: ${error.runtimeType}');
    if (context.mounted) notifySaveVideoResult(context, success: false);
  } finally {
    hideLoading();
    if (downloadDirectory != null) {
      try {
        await downloadDirectory.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<void> saveChatVideoMessage({
  required BuildContext context,
  required V2TimMessage message,
  required V2TimVideoElem videoElement,
  required TUIChatGlobalModel model,
}) async {
  if (PlatformUtils().isWeb) {
    final webPath = TencentUtils.checkString(videoElement.videoPath);
    if (webPath == null) {
      TIMUIKitClass.onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('视频地址不可用'),
        infoCode: -1,
      ));
      return;
    }
    await saveNetworkVideoFile(
      context,
      model: model,
      message: message,
      videoUrl: webPath,
      isAsset: true,
    );
    return;
  }

  final videoPath = TencentUtils.checkString(videoElement.videoPath);
  if (videoPath != null && File(videoPath).existsSync()) {
    await saveNetworkVideoFile(
      context,
      model: model,
      message: message,
      videoUrl: videoPath,
      isAsset: true,
    );
    return;
  }

  final localVideoUrl = TencentUtils.checkString(videoElement.localVideoUrl);
  if (localVideoUrl != null && File(localVideoUrl).existsSync()) {
    await saveNetworkVideoFile(
      context,
      model: model,
      message: message,
      videoUrl: localVideoUrl,
      isAsset: true,
    );
    return;
  }

  final videoUrl = TencentUtils.checkString(videoElement.videoUrl);
  if (videoUrl == null) {
    TIMUIKitClass.onTIMCallback(TIMCallback(
      type: TIMCallbackType.INFO,
      infoRecommendText: TIM_t('正在下载中'),
      infoCode: 6660414,
    ));
    return;
  }

  await saveNetworkVideoFile(
    context,
    model: model,
    message: message,
    videoUrl: videoUrl,
    isAsset: false,
  );
}
