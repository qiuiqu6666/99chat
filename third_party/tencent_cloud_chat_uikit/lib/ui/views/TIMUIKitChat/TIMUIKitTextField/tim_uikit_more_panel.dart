import 'package:tencent_cloud_chat_uikit/ui/utils/media_send_perf.dart';
// ignore_for_file: unused_field, avoid_print, unused_import

import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:tencent_cloud_chat_demo/src/chat/chat_camerawesome_capture_page.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/uikit_app_strings.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_call_invite_list.dart';
import 'package:video_player/video_player.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_video_draft_preview.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/permission.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_gallery_pick_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/gallery_send_perf_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_edit/editable_asset_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/media_work_state.dart';

// ignore: unnecessary_import
import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_launcher.dart';

import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

abstract final class _ChatUiTokens {
  static const Color backgroundDark = Color(0xFF101114);
  static const Color backgroundLight = Color(0xFFF5F6F8);
  static const Color surfaceDark = Color(0xFF1B1D22);
  static const Color surfaceAltDark = Color(0xFF23262D);
  static const Color surfaceAltLight = Color(0xFFF1F3F5);
  static const Color textPrimaryDark = Color(0xFFF4F4F4);
  static const Color textSecondaryLight = Color(0xFF7A828D);
  static const Color textSecondaryDark = Color(0xFF9A9CA3);
  static const Color borderLight = Color(0xFFE6E8EC);
  static const Color borderDark = Color(0xFF2A2D33);
  static const Color ink500 = Color(0xFF4B5563);
  static const double rLg = 14;
}

/// 更多面板统一日间/深色样式（内置项与 [MorePanelConfig.extraAction] 共用）。
class MorePanelStyles {
  MorePanelStyles._();

  static const double tileSize = 72;
  static const double iconSize = 56;

  static bool isDark(TUITheme theme) {
    final bg =
        theme.wideBackgroundColor ?? theme.weakBackgroundColor ?? Colors.white;
    return bg.computeLuminance() < 0.5;
  }

  static Color panelBackground(TUITheme theme) => isDark(theme)
      ? (theme.weakBackgroundColor ??
          theme.wideBackgroundColor ??
          _ChatUiTokens.backgroundDark)
      : (theme.weakBackgroundColor ?? _ChatUiTokens.backgroundLight);

  static Color tileBackground(TUITheme theme) {
    if (isDark(theme)) {
      final panel = panelBackground(theme);
      final candidate = theme.inputFillColor ??
          theme.conversationItemBgColor ??
          _ChatUiTokens.surfaceAltDark;
      if (candidate == panel) {
        return _ChatUiTokens.surfaceAltDark;
      }
      return candidate;
    }
    return theme.inputFillColor ?? _ChatUiTokens.surfaceAltLight;
  }

  static Color iconColor(TUITheme theme) {
    if (isDark(theme)) {
      return theme.darkTextColor ?? _ChatUiTokens.textPrimaryDark;
    }
    return _ChatUiTokens.ink500;
  }

  static Color labelColor(TUITheme theme) =>
      theme.weakTextColor ??
      (isDark(theme)
          ? _ChatUiTokens.textSecondaryDark
          : _ChatUiTokens.textSecondaryLight);

  static Color dividerColor(TUITheme theme) =>
      theme.weakDividerColor ??
      (isDark(theme) ? _ChatUiTokens.borderDark : _ChatUiTokens.borderLight);

  static Widget iconTile(TUITheme theme, Widget child) {
    return Container(
      height: tileSize,
      width: tileSize,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: tileBackground(theme),
        borderRadius: BorderRadius.circular(_ChatUiTokens.rLg),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  static Widget svgIcon(
    TUITheme theme,
    String asset, {
    String? package,
    double size = iconSize,
  }) {
    return iconTile(
      theme,
      SvgPicture.asset(
        asset,
        package: package,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(iconColor(theme), BlendMode.srcIn),
      ),
    );
  }

  static Widget pngIcon(TUITheme theme, String asset,
      {double size = iconSize}) {
    return iconTile(
      theme,
      Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: iconColor(theme),
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }

  static Widget materialIcon(TUITheme theme, IconData icon,
      {double size = iconSize}) {
    return iconTile(
      theme,
      Icon(icon, size: size, color: iconColor(theme)),
    );
  }
}

typedef _MediaWorkState = MediaWorkState;
typedef _MediaPreviewResult = MediaPreviewResult;

class _PreparedVideoSend {
  const _PreparedVideoSend({
    required this.videoPath,
    this.duration,
    this.snapshotPath,
    this.optimisticId,
  });

  final String videoPath;
  final int? duration;
  final String? snapshotPath;
  final String? optimisticId;
}

class _PendingGalleryImageSend {
  const _PendingGalleryImageSend({
    required this.filePath,
    required this.optimisticId,
    required this.convID,
    required this.convType,
    this.imageWidth,
    this.imageHeight,
    required this.batchId,
    required this.batchIndex,
  });

  final String filePath;
  final String optimisticId;
  final String convID;
  final ConvType convType;
  final int? imageWidth;
  final int? imageHeight;
  final String batchId;
  final int batchIndex;
}

class _ResolvedGalleryImage {
  const _ResolvedGalleryImage({
    required this.filePath,
    this.imageWidth,
    this.imageHeight,
    this.fileBytes,
  });

  final String filePath;
  final int? imageWidth;
  final int? imageHeight;
  final int? fileBytes;
}

class _GalleryMediaPrepared {
  const _GalleryMediaPrepared({
    required this.convID,
    required this.convType,
    this.imagePaths = const [],
    this.videos = const [],
  });

  final String convID;
  final ConvType convType;
  final List<String> imagePaths;
  final List<_PreparedVideoSend> videos;
}

class _CameraMediaPrepared {
  const _CameraMediaPrepared({
    required this.convID,
    required this.convType,
    this.imagePath,
    this.imageWidth,
    this.imageHeight,
    this.video,
  });

  final String convID;
  final ConvType convType;
  final String? imagePath;
  final int? imageWidth;
  final int? imageHeight;
  final _PreparedVideoSend? video;
}

class _VideoPreviewResult {
  final _MediaPreviewResult action;
  final int durationSeconds;

  const _VideoPreviewResult(this.action, this.durationSeconds);
}

class MorePanelConfig {
  static int get FILE_MAX_SIZE => ChatAttachmentService.mobileSupported
      ? ChatAttachmentService.instance.routingPolicy.maxAttachmentBytes
      : 100 * 1024 * 1024;
  static int get VIDEO_MAX_SIZE => FILE_MAX_SIZE;
  static int get IMAGE_MAX_SIZE => ChatAttachmentService.mobileSupported
      ? ChatAttachmentService.instance.routingPolicy.maxAttachmentBytes
      : 28 * 1024 * 1024;

  final bool showGalleryPickAction;
  final bool showCameraAction;
  final bool showFilePickAction;
  final bool showWebImagePickAction;
  final bool showWebVideoPickAction;
  final bool showVoiceCall;
  final bool showVideoCall;
  final List<MorePanelItem>? extraAction;
  final Widget Function(MorePanelItem item)? actionBuilder;

  MorePanelConfig({
    this.showFilePickAction = true,
    this.showGalleryPickAction = true,
    this.showCameraAction = true,
    this.showWebImagePickAction = true,
    this.showWebVideoPickAction = true,
    this.showVoiceCall = true,
    this.showVideoCall = true,
    this.extraAction,
    this.actionBuilder,
  });
}

class MorePanelItem {
  final String title;
  final String id;
  final Widget icon;
  final Function(BuildContext context)? onTap;

  MorePanelItem(
      {this.onTap, required this.icon, required this.id, required this.title});
}

class MorePanel extends StatefulWidget {
  /// 会话ID
  final String conversationID;

  /// 会话类型
  final ConvType conversationType;

  final MorePanelConfig? morePanelConfig;
  final VoidCallback? onImageSent;

  const MorePanel(
      {required this.conversationID,
      required this.conversationType,
      Key? key,
      this.morePanelConfig,
      this.onImageSent})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _MorePanelState();
}

class _MorePanelState extends TIMUIKitState<MorePanel> {
  final ImagePicker _picker = ImagePicker();
  final TUISelfInfoViewModel _selfInfoViewModel =
      serviceLocator<TUISelfInfoViewModel>();
  Uint8List? fileContent;
  String? fileName;
  File? tempFile;
  final _tUICore = TUICore();
  final _tUILogin = TUILogin();
  bool isInstallCallkit = false;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _featureBusy = false;
  int _mediaTaskToken = 0;
  DateTime? _featureBusyStartedAt;
  Timer? _featureBusyResetTimer;
  _MediaWorkState _mediaWorkState = _MediaWorkState.idle;
  static const Duration _mediaTaskTimeout = Duration(seconds: 45);

  void _showPanelNotice(String text) {
    onTIMCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: text,
      ),
    );
  }

  /// 选图/拍摄期间允许会话切换或离开页面：始终按打开相册时捕获的目标发送。
  bool _hasUsableConversation([String? convID]) => true;

  String _capturedConversationId(TUIChatSeparateViewModel model) {
    final modelId = model.conversationID.trim();
    return modelId.isNotEmpty ? modelId : widget.conversationID.trim();
  }

  ConvType _capturedConversationType(TUIChatSeparateViewModel model) {
    return model.conversationType ?? widget.conversationType;
  }

  bool _isCapturedConversationCurrent(
    String convID,
    ConvType convType, {
    bool notify = true,
  }) =>
      true;

  NavigatorState? _captureRootNavigator() {
    try {
      return Navigator.of(context, rootNavigator: true);
    } catch (_) {
      return null;
    }
  }

  void _dispatchImageSendWithoutAwait({
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required String filePath,
    int? imageWidth,
    int? imageHeight,
  }) {
    if (!_hasUsableConversation(convID) ||
        !_isCapturedConversationCurrent(convID, convType)) {
      return;
    }
    final sendFuture = model.sendImageMessage(
      imagePath: filePath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      convID: convID,
      convType: convType,
    );
    widget.onImageSent?.call();
    if (mounted) {
      unawaited(MessageUtils.handleMessageError(sendFuture, context));
    } else {
      unawaited(sendFuture);
    }
  }

  void _dispatchVideoSendWithoutAwait({
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required String videoPath,
    int? duration,
    String? snapshotPath,
    String? existingOptimisticId,
    GallerySendPerfTrace? perf,
  }) {
    if (!_hasUsableConversation(convID) ||
        !_isCapturedConversationCurrent(convID, convType)) {
      final staleId = existingOptimisticId?.trim() ?? '';
      if (staleId.isNotEmpty) {
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: staleId,
        );
      }
      return;
    }
    final optimisticId = existingOptimisticId ??
        model.beginOptimisticVideoPlaceholder(
          convID: convID,
          videoPath: videoPath,
          duration: duration,
          snapshotPath: snapshotPath,
        );
    final sendWatch = Stopwatch()..start();
    perf?.log('video_sdk_send_begin');
    final sendFuture = model.sendVideoMessage(
      videoPath: videoPath,
      duration: duration != null && duration > 0 ? duration : null,
      snapshotPath: snapshotPath,
      convID: convID,
      convType: convType,
      existingOptimisticId: optimisticId,
    );
    final handled = mounted
        ? MessageUtils.handleMessageError(sendFuture, context)
        : sendFuture;
    if (perf != null) {
      perf.retainAsyncOperation();
      unawaited(handled.whenComplete(() {
        perf.log(
          'video_sdk_send_end',
          detail: 'itemMs=${sendWatch.elapsedMilliseconds}',
        );
        perf.releaseAsyncOperation();
      }));
    } else {
      unawaited(handled);
    }
  }

  Future<_ResolvedGalleryImage?> _resolveGalleryImageAsset(
    AssetEntity asset, {
    GallerySendPerfTrace? perf,
    int? index,
  }) async {
    try {
      final resolved = await EditableAssetPicker.resolveFileForChatSendResult(
        asset,
        perf: perf,
        index: index,
      );
      final originFile = resolved.file;
      final filePath = originFile?.path;
      if (originFile == null || filePath == null || filePath.isEmpty) {
        perf?.log('resolve_categorized_failure',
            index: index, detail: 'outcome=${resolved.outcome.name}');
        _showPanelNotice(TIM_t('图片暂时无法读取，请重试'));
        return null;
      }
      final size = await originFile.length();
      if (size > MorePanelConfig.IMAGE_MAX_SIZE) {
        perf?.log('resolve_file_terminal',
            index: index, detail: 'outcome=oversize bytes=$size');
        onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO, infoRecommendText: TIM_t("文件大小超出了限制")));
        return null;
      }
      final orientatedWidth = asset.orientatedWidth;
      final orientatedHeight = asset.orientatedHeight;
      return _ResolvedGalleryImage(
        filePath: filePath,
        imageWidth: orientatedWidth > 0 ? orientatedWidth : null,
        imageHeight: orientatedHeight > 0 ? orientatedHeight : null,
        fileBytes: size,
      );
    } catch (error) {
      outputLogger.i('resolve gallery image failed: $error');
      return null;
    }
  }

  bool _isPickedVideo(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.isNotEmpty) {
      return mimeType.startsWith('video/');
    }
    final extension =
        p.extension(file.name.isNotEmpty ? file.name : file.path).toLowerCase();
    return const <String>{
      '.mp4',
      '.mov',
      '.m4v',
      '.avi',
      '.mkv',
      '.webm',
      '.3gp',
    }.contains(extension);
  }

  Future<void> _dispatchCustomPickedGalleryMedia({
    required List<AssetEntity> pickedAssets,
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required GallerySendPerfTrace perf,
  }) async {
    if (pickedAssets.length > ChatGalleryPickUtils.maxSelectedAssets) {
      _showPanelNotice(TIM_t('每次最多选择9项，请重新选择'));
      return;
    }
    // The picker has settled before dispatch; _runMediaTask also owns cleanup
    // for cancellation and failures.
    // A picker can return the same edited/live-photo asset twice. One asset
    // must own exactly one optimistic bubble and one SDK send.
    final uniqueAssets = <AssetEntity>[];
    final seenAssetKeys = <String>{};
    for (final asset in pickedAssets) {
      final id = asset.id.trim();
      final key = '${asset.type}:$id';
      if (id.isNotEmpty && !seenAssetKeys.add(key)) {
        continue;
      }
      uniqueAssets.add(asset);
    }
    final imageAssets =
        uniqueAssets.where((asset) => asset.type == AssetType.image).toList();
    final videoAssets =
        uniqueAssets.where((asset) => asset.type == AssetType.video).toList();
    perf.log(
      'custom_assets_classified',
      count: imageAssets.length,
      detail: 'videos=${videoAssets.length}',
    );
    if (imageAssets.isEmpty && videoAssets.isEmpty) {
      return;
    }

    // 先按选择顺序一次性显示轻量占位。PhotoKit 导出仍保持串行，避免 iOS
    // 同时导出多张 HEIC/云端图片造成内存尖峰；导出只负责补全同一 stable id。
    final batchId = 'image_batch_${nextChatMediaUniqueToken()}';
    // Create video rows before PhotoKit export/thumbnail work. AssetEntity may
    // point to iCloud, so waiting for originFile here makes the send tap look
    // blocked even though the actual SDK send can run independently.
    final videoOptimisticIds = <String>[];
    for (final asset in videoAssets) {
      videoOptimisticIds.add(
        model.beginOptimisticVideoPlaceholder(
          convID: convID,
          videoPath: '',
          duration: asset.videoDuration.inSeconds > 0
              ? asset.videoDuration.inSeconds
              : null,
          requestInitialPin: false,
        ),
      );
    }
    final optimisticIds = model.beginOptimisticImagePlaceholders(
      convID: convID,
      inputs: imageAssets
          .map(
            (asset) => OptimisticImagePlaceholderInput(
              batchId: batchId,
              batchIndex: imageAssets.indexOf(asset),
              imageWidth:
                  asset.orientatedWidth > 0 ? asset.orientatedWidth : null,
              imageHeight:
                  asset.orientatedHeight > 0 ? asset.orientatedHeight : null,
              sourcePending: true,
            ),
          )
          .toList(growable: false),
      probeSizeSynchronously: false,
      requestInitialPin: false,
    );
    perf.log('placeholder_batch_end', count: optimisticIds.length);
    if (optimisticIds.length != imageAssets.length) {
      for (final optimisticId in optimisticIds) {
        MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
      }
      for (final optimisticId in videoOptimisticIds) {
        MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
      }
      return;
    }
    await ChatGalleryPickUtils.yieldForMediaSend();
    serviceLocator<TUIChatGlobalModel>().requestPinToBottom(
      convID,
      force: true,
      immediate: optimisticIds.length > 1,
    );
    perf.log('placeholder_post_layout_pin_requested');

    final pending = <_PendingGalleryImageSend>[];
    for (var i = 0; i < imageAssets.length; i++) {
      if (!_hasUsableConversation(convID)) {
        perf.log('resolve_cancelled_conversation_changed', index: i);
        for (var pendingIndex = i;
            pendingIndex < optimisticIds.length;
            pendingIndex++) {
          model.cancelOptimisticMediaPlaceholder(
            convID: convID,
            clientId: optimisticIds[pendingIndex],
          );
        }
        for (final optimisticId in videoOptimisticIds) {
          MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
          model.cancelOptimisticMediaPlaceholder(
            convID: convID,
            clientId: optimisticId,
          );
        }
        break;
      }
      final asset = imageAssets[i];
      final itemWatch = Stopwatch()..start();
      perf.log('resolve_begin', index: i, count: imageAssets.length);
      final resolved = await _resolveGalleryImageAsset(
        asset,
        perf: perf,
        index: i,
      );
      perf.log(
        resolved == null ? 'resolve_failed' : 'resolve_end',
        index: i,
        count: imageAssets.length,
        bytes: resolved?.fileBytes,
        detail: 'itemMs=${itemWatch.elapsedMilliseconds}',
      );
      final optimisticId = optimisticIds[i];
      if (resolved == null) {
        MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
        _showPanelNotice(TIM_t('图片发送失败，请重试'));
        continue;
      }
      // The pipeline writes the final stable send file; no picker-side copy.
      final stagedPath = resolved.filePath.trim();
      if (stagedPath.isEmpty) {
        MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
        continue;
      }
      if (!model.canSendCapturedMedia) return;
      model.hydrateOptimisticImagePlaceholder(
        convID: convID,
        clientId: optimisticId,
        imagePath: stagedPath,
        imageWidth: resolved.imageWidth,
        imageHeight: resolved.imageHeight,
      );
      // The chat may have evicted its visible window after navigation. The
      // absence of a UI placeholder must not cancel an accepted send.
      pending.add(_PendingGalleryImageSend(
        filePath: stagedPath,
        optimisticId: optimisticId,
        convID: convID,
        convType: convType,
        imageWidth: resolved.imageWidth,
        imageHeight: resolved.imageHeight,
        batchId: batchId,
        batchIndex: i,
      ));
      _enqueueGalleryImage(model, pending.last, perf);
      // Let UI work run, but keep exporting/sending if frames stop.
      await ChatGalleryPickUtils.yieldForMediaSend();
      perf.log('resolve_frame_yield_end', index: i);
    }

    if (pending.isNotEmpty) {
      perf.log('image_send_queue_start', count: pending.length);
    }

    for (var videoIndex = 0; videoIndex < videoAssets.length; videoIndex++) {
      if (!_hasUsableConversation(convID)) {
        return;
      }
      perf.retainAsyncOperation();
      unawaited(
        _prepareAndDispatchGalleryVideo(
          asset: videoAssets[videoIndex],
          model: model,
          convID: convID,
          convType: convType,
          existingOptimisticId: videoOptimisticIds[videoIndex],
          perf: perf,
        ).whenComplete(perf.releaseAsyncOperation),
      );
    }
    perf.log(
      'custom_dispatch_complete',
      count: pending.length,
      detail: 'videos=${videoAssets.length}',
    );
  }

  Future<void> _dispatchSystemPickedMedia({
    required List<XFile> files,
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required GallerySendPerfTrace perf,
  }) async {
    if (files.length > ChatGalleryPickUtils.maxSelectedAssets) {
      _showPanelNotice(TIM_t('每次最多选择9项，请重新选择'));
      return;
    }
    perf.log('system_dispatch_begin', count: files.length);
    final batchId = 'image_batch_${nextChatMediaUniqueToken()}';
    final imageFiles = <XFile>[];
    final videos = <XFile>[];
    final seenPickerFiles = <String>{};
    for (final picked in files) {
      final pathKey = picked.path.trim();
      final fallbackKey = '${picked.name}|${picked.mimeType ?? ''}';
      final key = pathKey.isNotEmpty ? pathKey : fallbackKey;
      if (key.isNotEmpty && !seenPickerFiles.add(key)) {
        continue;
      }
      if (_isPickedVideo(picked)) {
        videos.add(picked);
      } else {
        imageFiles.add(picked);
      }
    }

    // Insert video rows before copying temporary picker files. The copy and
    // thumbnail extraction can take hundreds of milliseconds for large clips.
    final videoOptimisticIds = <String>[];
    for (final video in videos) {
      videoOptimisticIds.add(
        model.beginOptimisticVideoPlaceholder(
          convID: convID,
          videoPath: video.path,
          requestInitialPin: false,
        ),
      );
    }

    // Insert every row before staging/copying files or starting SDK work.
    final placeholderWatch = Stopwatch()..start();
    perf.log('placeholder_batch_begin', count: imageFiles.length);
    final optimisticIds = imageFiles.isEmpty
        ? const <String>[]
        : model.beginOptimisticImagePlaceholders(
            convID: convID,
            inputs: List.generate(
              imageFiles.length,
              (index) => OptimisticImagePlaceholderInput(
                batchId: batchId,
                batchIndex: index,
                imagePath: imageFiles[index].path,
              ),
              growable: false,
            ),
            probeSizeSynchronously: false,
            requestInitialPin: false,
          );
    perf.log(
      'placeholder_batch_end',
      count: optimisticIds.length,
      detail: 'syncMs=${placeholderWatch.elapsedMilliseconds}',
    );
    for (final id in optimisticIds) {
      MediaSendPerf.begin(id).record('uiInsertMs', placeholderWatch.elapsedMilliseconds);
    }
    if (optimisticIds.isNotEmpty) {
      await ChatGalleryPickUtils.yieldForMediaSend();
      perf.log('placeholder_first_frame_end');
      serviceLocator<TUIChatGlobalModel>().requestPinToBottom(
        convID,
        force: true,
        immediate: optimisticIds.length > 1,
      );
      perf.log('placeholder_post_layout_pin_requested');
    }
    if (videoOptimisticIds.isNotEmpty && optimisticIds.isEmpty) {
      serviceLocator<TUIChatGlobalModel>().requestPinToBottom(
        convID,
        force: true,
      );
    }

    // Start videos as soon as their rows are visible. Image header checks and
    // image sends must not hold back an independently selected video.
    for (var videoIndex = 0; videoIndex < videos.length; videoIndex++) {
      perf.retainAsyncOperation();
      unawaited(
        _prepareAndDispatchSystemGalleryVideo(
          file: videos[videoIndex],
          model: model,
          convID: convID,
          convType: convType,
          existingOptimisticId: videoOptimisticIds[videoIndex],
          perf: perf,
        ).whenComplete(perf.releaseAsyncOperation),
      );
    }

    // Start all header reads, but let each image send when its own result is
    // ready instead of waiting for every selected image.
    perf.log('image_headers_begin', count: imageFiles.length);
    final imageSizes = imageFiles
        .map((file) => readLocalImageSizeFromHeader(file.path))
        .toList(growable: false);
    if (!model.canSendCapturedMedia) {
      for (final id in optimisticIds) { MediaSendPerf.lookup(id)?.finish('session_changed'); }
      return;
    }
    perf.log('image_headers_started', count: imageFiles.length);

    // Stream: resolve → stage → enqueue while keeping the captured
    // conversation ID. Leaving the panel must not cancel queued images.
    final pendingImages = <_PendingGalleryImageSend>[];
    for (var i = 0; i < imageFiles.length; i++) {
      if (!_hasUsableConversation(convID)) {
        for (var j = i; j < optimisticIds.length; j++) {
          model.cancelOptimisticMediaPlaceholder(
            convID: convID,
            clientId: optimisticIds[j],
          );
        }
        break;
      }
      final optimisticId = optimisticIds[i];
      final picked = imageFiles[i];
      try {
        final imageSize = await imageSizes[i];
        final itemWatch = Stopwatch()..start();
        perf.log('system_resolve_begin', index: i, count: imageFiles.length);
        final source = File(picked.path);
        if (!await source.exists()) {
          perf.log('system_resolve_missing', index: i);
          MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
          model.cancelOptimisticMediaPlaceholder(
            convID: convID,
            clientId: optimisticId,
          );
          continue;
        }
        final bytes = await source.length();
        if (bytes > MorePanelConfig.IMAGE_MAX_SIZE) {
          onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t("文件大小超出了限制"),
          ));
          MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
          model.cancelOptimisticMediaPlaceholder(
            convID: convID,
            clientId: optimisticId,
          );
          continue;
        }
        perf.log(
          'system_resolve_end',
          index: i,
          bytes: bytes,
          detail: 'itemMs=${itemWatch.elapsedMilliseconds}',
        );

        final stageWatch = Stopwatch()..start();
        perf.log('stage_begin', index: i, bytes: bytes);
        MediaSendPerf.begin(optimisticId).record('sizeOriginal', bytes);
        final sendPath = source.path;
        pendingImages.add(_PendingGalleryImageSend(
          filePath: sendPath,
          optimisticId: optimisticId,
          convID: convID,
          convType: convType,
          batchId: batchId,
          batchIndex: i,
          imageWidth: imageSize?.width.round(),
          imageHeight: imageSize?.height.round(),
        ));
        _enqueueGalleryImage(model, pendingImages.last, perf);
        perf.log(
          'stage_end',
          index: i,
          bytes: bytes,
          detail: 'itemMs=${stageWatch.elapsedMilliseconds}',
        );
      } catch (error) {
        MediaSendPerf.lookup(optimisticId)?.finish('cancelled');
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
        outputLogger.i('resolve/stage system picked image failed: $error');
        perf.log(
          'system_resolve_failed',
          index: i,
          detail: 'type=${error.runtimeType}',
        );
      }
      await ChatGalleryPickUtils.yieldForMediaSend();
    }

    if (pendingImages.isNotEmpty) {
      perf.log('image_send_queue_start', count: pendingImages.length);
    }
    perf.log(
      'system_dispatch_complete',
      count: pendingImages.length,
      detail: 'videos=${videos.length}',
    );
  }

  Future<void> _prepareAndDispatchSystemGalleryVideo({
    required XFile file,
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required String existingOptimisticId,
    GallerySendPerfTrace? perf,
  }) async {
    String? optimisticId = existingOptimisticId;
    final mediaPerf = MediaSendPerf.begin(existingOptimisticId);
    var dispatched = false;
    try {
      final watch = Stopwatch()..start();
      perf?.log('video_prepare_begin', detail: 'source=system');
      if (!_hasUsableConversation(convID) ||
          !_isCapturedConversationCurrent(convID, convType)) {
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId,
        );
        return;
      }
      // Backend attachments own their durable staging; avoid copying twice.
      final backend = await ChatAttachmentService.instance.handles(file.path, 'video');
      final staged = backend ? file.path : await mediaPerf.measure(
          'staging', () => stageSystemPickerVideoForChatSend(file.path));
      perf?.log(
        'video_stage_end',
        bytes: staged == null ? null : await File(staged).length(),
        detail: 'itemMs=${watch.elapsedMilliseconds}',
      );
      if (staged == null || staged.isEmpty) {
        model.markOptimisticMediaPlaceholderFailed(
          convID: convID,
          clientId: optimisticId,
        );
        _showPanelNotice(TIM_t('视频文件不可用'));
        return;
      }
      if (await File(staged).length() > MorePanelConfig.VIDEO_MAX_SIZE) {
        model.markOptimisticMediaPlaceholderFailed(
          convID: convID,
          clientId: optimisticId,
        );
        onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("文件大小超出当前限制"),
        ));
        return;
      }
      optimisticId = existingOptimisticId;
      final metadata = await mediaPerf.measure('metadata', () => Future.wait<Object?>([
        _loadVideoDurationSeconds(staged),
        buildVideoSnapshotForSend(
          videoPath: staged,
          devicePixelRatio:
              mounted ? MediaQuery.devicePixelRatioOf(context) : null,
        ),
      ]));
      perf?.log('video_metadata_end', detail: 'itemMs=${watch.elapsedMilliseconds}');
      final duration = metadata[0] as int;
      final snapshotPath = metadata[1] as String?;
      model.hydrateOptimisticVideoPlaceholder(
        convID: convID,
        clientId: optimisticId,
        videoPath: staged,
        duration: duration,
        snapshotPath: snapshotPath,
      );
      if (!_isCapturedConversationCurrent(convID, convType)) {
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId!,
        );
        return;
      }
      dispatched = true;
      _dispatchVideoSendWithoutAwait(
        model: model,
        convID: convID,
        convType: convType,
        videoPath: staged,
        duration: duration,
        snapshotPath: snapshotPath,
        existingOptimisticId: optimisticId,
        perf: perf,
      );
      perf?.log('video_send_queued', detail: 'itemMs=${watch.elapsedMilliseconds}');
    } catch (error) {
      if (optimisticId != null) {
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId!,
        );
      }
      outputLogger.i('prepare system picked video failed: $error');
      perf?.log('video_prepare_failed', detail: 'type=${error.runtimeType}');
      _showPanelNotice(TIM_t('视频文件异常'));
    } finally {
      if (!dispatched) mediaPerf.finish('preparation_failed');
    }
  }

  void _enqueueGalleryImage(TUIChatSeparateViewModel model,
      _PendingGalleryImageSend item, GallerySendPerfTrace perf) {
    perf.retainAsyncOperation();
    unawaited(_sendPendingGalleryImagesConcurrently(
      model, [item], perf: perf,
    ).whenComplete(perf.releaseAsyncOperation));
  }

  /// Sends pre-created optimistic bubbles with bounded concurrency. Each item
  /// carries a stable batch index so leaving this panel does not cancel it.
  Future<void> _sendPendingGalleryImagesConcurrently(
    TUIChatSeparateViewModel model,
    List<_PendingGalleryImageSend> pending, {
    required GallerySendPerfTrace perf,
  }) async {
    if (pending.isEmpty) {
      return;
    }
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < pending.length) {
        final index = nextIndex++;
        final item = pending[index];
        if (!_hasUsableConversation(item.convID)) {
          perf.log('send_cancelled_conversation_changed', index: index);
          model.cancelOptimisticMediaPlaceholder(
            convID: item.convID,
            clientId: item.optimisticId,
          );
          return;
        }
        try {
          final sendWatch = Stopwatch()..start();
          perf.log('send_begin', index: index, count: pending.length);
          final sendFuture = model.sendImageMessage(
            imagePath: item.filePath,
            imageWidth: item.imageWidth,
            imageHeight: item.imageHeight,
            convID: item.convID,
            convType: item.convType,
            existingOptimisticId: item.optimisticId,
            batchId: item.batchId,
            batchIndex: item.batchIndex,
          );
          // The send coordinator owns delivery and status updates. Do not
          // bind the batch to this panel's BuildContext after navigation.
          await sendFuture;
          perf.log(
            'send_end',
            index: index,
            count: pending.length,
            detail: 'itemMs=${sendWatch.elapsedMilliseconds}',
          );
        } catch (error) {
          model.markOptimisticMediaPlaceholderFailed(
            convID: item.convID,
            clientId: item.optimisticId,
          );
          perf.log(
            'send_failed',
            index: index,
            count: pending.length,
            detail: 'type=${error.runtimeType}',
          );
          outputLogger.i('send gallery image failed: $error');
        }
      }
    }

    // Preparation and SDK upload have separate bounded pools.
    // All accepted jobs may wait for preparation without occupying upload slots.
    final maxWorkers = ChatGalleryPickUtils.maxSelectedAssets;
    final workerCount =
        pending.length < maxWorkers ? pending.length : maxWorkers;
    perf.log(
      'send_workers_begin',
      count: pending.length,
      detail: 'workers=$workerCount',
    );
    await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()));
    perf.log('all_image_sends_complete', count: pending.length);
  }

  void _dispatchPreparedGalleryMedia(
    TUIChatSeparateViewModel model,
    _GalleryMediaPrepared prepared,
  ) {
    if (!_isCapturedConversationCurrent(prepared.convID, prepared.convType)) {
      for (final video in prepared.videos) {
        if (video.optimisticId != null) {
          model.cancelOptimisticMediaPlaceholder(
            convID: prepared.convID,
            clientId: video.optimisticId!,
          );
        }
      }
      return;
    }
    for (final filePath in prepared.imagePaths) {
      final layoutSize = readLocalImageSizeSync(filePath);
      _dispatchImageSendWithoutAwait(
        model: model,
        convID: prepared.convID,
        convType: prepared.convType,
        filePath: filePath,
        imageWidth: layoutSize != null ? layoutSize.width.round() : null,
        imageHeight: layoutSize != null ? layoutSize.height.round() : null,
      );
    }
    for (final video in prepared.videos) {
      _dispatchVideoSendWithoutAwait(
        model: model,
        convID: prepared.convID,
        convType: prepared.convType,
        videoPath: video.videoPath,
        duration: video.duration,
        snapshotPath: video.snapshotPath,
        existingOptimisticId: video.optimisticId,
      );
    }
    _setMediaState(_MediaWorkState.idle);
  }

  void _dispatchPreparedCameraMedia(
    TUIChatSeparateViewModel model,
    _CameraMediaPrepared prepared,
  ) {
    if (!_isCapturedConversationCurrent(prepared.convID, prepared.convType)) {
      final optimisticId = prepared.video?.optimisticId;
      if (optimisticId != null) {
        model.cancelOptimisticMediaPlaceholder(
          convID: prepared.convID,
          clientId: optimisticId,
        );
      }
      return;
    }
    final imagePath = prepared.imagePath?.trim() ?? '';
    if (imagePath.isNotEmpty) {
      _dispatchImageSendWithoutAwait(
        model: model,
        convID: prepared.convID,
        convType: prepared.convType,
        filePath: imagePath,
        imageWidth: prepared.imageWidth,
        imageHeight: prepared.imageHeight,
      );
    } else if (prepared.video != null) {
      final video = prepared.video!;
      _dispatchVideoSendWithoutAwait(
        model: model,
        convID: prepared.convID,
        convType: prepared.convType,
        videoPath: video.videoPath,
        duration: video.duration,
        snapshotPath: video.snapshotPath,
        existingOptimisticId: video.optimisticId,
      );
    }
    _setMediaState(_MediaWorkState.idle);
  }

  void _setMediaState(_MediaWorkState state) {
    _mediaWorkState = state;
  }

  bool _releaseStaleMediaLockIfNeeded() {
    final startedAt = _featureBusyStartedAt;
    if (!_featureBusy || startedAt == null) {
      return false;
    }
    if (DateTime.now().difference(startedAt) < _mediaTaskTimeout) {
      return false;
    }
    _featureBusyResetTimer?.cancel();
    _featureBusyResetTimer = null;
    _featureBusy = false;
    _featureBusyStartedAt = null;
    _setMediaState(_MediaWorkState.failed);
    DeviceSyncService.instance.endForegroundMediaWork(
      reason: 'media_task_timeout',
      cooldown: const Duration(seconds: 3),
    );
    return true;
  }

  Future<T?> _runMediaTask<T>(
    String reason,
    Future<T?> Function(
      Future<void> Function({bool transitionSettled}) dismissPicker,
    ) action, {
    bool allowNested = false,
  }) async {
    if (_featureBusy && !_releaseStaleMediaLockIfNeeded()) {
      if (allowNested) {
        return action(({bool transitionSettled = false}) async {});
      }
      _showPanelNotice(TIM_t('正在处理上一项操作，请稍候'));
      return null;
    }

    final token = ++_mediaTaskToken;
    _featureBusy = true;
    _featureBusyStartedAt = DateTime.now();
    _setMediaState(_MediaWorkState.picking);
    _featureBusyResetTimer?.cancel();
    _featureBusyResetTimer = Timer(_mediaTaskTimeout, () {
      if (!_featureBusy || token != _mediaTaskToken) {
        return;
      }
      _featureBusy = false;
      _featureBusyStartedAt = null;
      _setMediaState(_MediaWorkState.failed);
      DeviceSyncService.instance.endForegroundMediaWork(
        reason: '${reason}_timeout',
        cooldown: const Duration(seconds: 3),
      );
      if (mounted) {
        _showPanelNotice(TIM_t('操作超时，请重试'));
      }
    });

    DeviceSyncService.instance.beginForegroundMediaWork(
      reason: reason,
      duration: const Duration(seconds: 3),
    );
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    globalModel.beginMediaPickerOverlay();
    Future<void>? dismissTask;
    Future<void> dismissPicker({bool transitionSettled = false}) => dismissTask ??= () async {
      // Idempotent: gallery can release the overlay before file preparation;
      // finally still closes it on cancellation, failure and other media paths.
      await ChatGalleryPickUtils.waitForPickerDismissSettle(
        transitionDuration: transitionSettled
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
      globalModel.endMediaPickerOverlay();
    }();
    try {
      return await action(dismissPicker);
    } finally {
      // Picker Future often completes before the slide-down finishes. Settle
      // before notifying the chat list (covers cancel as well as success).
      await dismissPicker();
      if (token == _mediaTaskToken) {
        _featureBusyResetTimer?.cancel();
        _featureBusyResetTimer = null;
        DeviceSyncService.instance.endForegroundMediaWork(
          reason: reason,
          cooldown: const Duration(seconds: 3),
        );
        _featureBusy = false;
        _featureBusyStartedAt = null;
        if (_mediaWorkState != _MediaWorkState.failed) {
          _setMediaState(_MediaWorkState.idle);
        }
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  Future<_MediaPreviewResult> _previewImageBeforeSend({
    required String filePath,
    required int sizeBytes,
    bool canRetake = false,
    NavigatorState? navigator,
  }) async {
    final nav = navigator ??
        (mounted ? Navigator.of(context, rootNavigator: true) : null);
    if (nav == null) {
      return _MediaPreviewResult.send;
    }
    _setMediaState(_MediaWorkState.previewing);
    final result = await nav.push<_MediaPreviewResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImageMediaPreviewPage(
          filePath: filePath,
          sizeText: _formatBytes(sizeBytes),
          canRetake: canRetake,
        ),
      ),
    );
    return result ?? _MediaPreviewResult.cancel;
  }

  Future<_VideoPreviewResult> _previewVideoBeforeSend({
    required String filePath,
    required int sizeBytes,
    required int durationSeconds,
    bool canRetake = false,
    NavigatorState? navigator,
  }) async {
    final nav = navigator ??
        (mounted ? Navigator.of(context, rootNavigator: true) : null);
    if (nav == null) {
      return _VideoPreviewResult(_MediaPreviewResult.send, durationSeconds);
    }
    _setMediaState(_MediaWorkState.previewing);
    final result = await nav.push<_VideoPreviewResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VideoMediaPreviewPage(
          filePath: filePath,
          sizeText: _formatBytes(sizeBytes),
          durationSeconds: durationSeconds,
          canRetake: canRetake,
        ),
      ),
    );
    return result ??
        _VideoPreviewResult(_MediaPreviewResult.cancel, durationSeconds);
  }

  Future<int> _loadVideoDurationSeconds(
    String filePath, {
    int fallbackSeconds = 0,
  }) async {
    if (fallbackSeconds > 0) {
      return fallbackSeconds;
    }
    final controller = VideoPlayerController.file(File(filePath));
    try {
      await controller.initialize().timeout(const Duration(seconds: 2));
      final milliseconds = controller.value.duration.inMilliseconds;
      if (milliseconds > 0) {
        return (milliseconds / 1000).ceil();
      }
    } catch (_) {
    } finally {
      await controller.dispose();
    }
    return fallbackSeconds;
  }

  @override
  void dispose() {
    _featureBusyResetTimer?.cancel();
    _featureBusyResetTimer = null;
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (PlatformUtils().isMobile) {
      _tUICore.getService(TUICALLKIT_SERVICE_NAME).then((value) {
        if (!mounted) {
          return;
        }
        setState(() {
          isInstallCallkit = value;
        });
      });
    }
  }

  List<MorePanelItem> itemList(
      BuildContext context, TUIChatSeparateViewModel model, TUITheme theme) {
    final tr = Translations.of(context);
    final config = widget.morePanelConfig ?? MorePanelConfig();
    // 顺序：相册/拍摄 → 收藏 → 通话 → 名片 → 文件 → 其余 extra（红包等）
    final extras = List<MorePanelItem>.from(config.extraAction ?? const []);
    MorePanelItem? favoritesItem;
    for (var i = 0; i < extras.length; i++) {
      if (extras[i].id == 'chat_favorites') {
        favoritesItem = extras.removeAt(i);
        break;
      }
    }
    final fileItem = MorePanelItem(
        id: "file",
        title: tr.k_003tnp0,
        onTap: (c) {
          _onFeatureTap(
            "file",
            c,
            model,
            theme,
          );
        },
        icon: MorePanelStyles.svgIcon(theme, 'images/file.svg',
            package: 'tencent_cloud_chat_uikit'));
    final trailing = <MorePanelItem>[];
    final contactIndex =
        extras.indexWhere((element) => element.id == 'contact_card');
    if (contactIndex >= 0) {
      trailing.addAll(extras.sublist(0, contactIndex + 1));
      trailing.add(fileItem);
      trailing.addAll(extras.sublist(contactIndex + 1));
    } else {
      trailing.add(fileItem);
      trailing.addAll(extras);
    }
    return [
      if (!PlatformUtils().isWeb)
        MorePanelItem(
            id: "photo",
            title: tr.k_003kthh,
            onTap: (c) {
              _onFeatureTap(
                "photo",
                c,
                model,
                theme,
              );
            },
            icon: MorePanelStyles.svgIcon(theme, 'images/photo.svg',
                package: 'tencent_cloud_chat_uikit')),
      if (PlatformUtils().isMobile)
        MorePanelItem(
            id: "take_photo",
            title: tr.k_003k6a7,
            onTap: (c) {
              _onFeatureTap("take_photo", c, model, theme);
            },
            icon: MorePanelStyles.svgIcon(theme, 'images/screen.svg',
                package: 'tencent_cloud_chat_uikit')),
      if (PlatformUtils().isWeb)
        MorePanelItem(
            id: "image",
            title: tr.k_0y1a2my,
            onTap: (c) {
              _onFeatureTap(
                "image",
                c,
                model,
                theme,
              );
            },
            icon: MorePanelStyles.svgIcon(theme, 'images/photo.svg',
                package: 'tencent_cloud_chat_uikit')),
      if (PlatformUtils().isWeb)
        MorePanelItem(
            id: "video",
            title: tr.k_002s86q,
            onTap: (c) {
              _onFeatureTap(
                "video",
                c,
                model,
                theme,
              );
            },
            icon: MorePanelStyles.materialIcon(theme, Icons.video_file)),
      if (favoritesItem != null) favoritesItem,
      if (isInstallCallkit && PlatformUtils().isMobile)
        MorePanelItem(
            id: "avCall",
            title: UikitAppStrings.avCall(),
            onTap: (c) {
              _onFeatureTap("avCall", c, model, theme);
            },
            icon: MorePanelStyles.svgIcon(theme, 'images/video-call.svg',
                package: 'tencent_cloud_chat_uikit')),
      ...trailing,
    ].where((element) {
      if (element.id == "take_photo") {
        return config.showCameraAction;
      }

      if (element.id == "file") {
        return config.showFilePickAction;
      }

      if (element.id == "photo") {
        return config.showGalleryPickAction;
      }

      if (element.id == "image") {
        return config.showWebImagePickAction;
      }

      if (element.id == "video") {
        return config.showWebVideoPickAction;
      }
      if (element.id == "avCall") {
        return widget.conversationType != ConvType.group &&
            (config.showVoiceCall || config.showVideoCall);
      }
      if (element.id == "voiceCall") {
        return widget.conversationType != ConvType.group &&
            config.showVoiceCall;
      }
      if (element.id == "videoCall") {
        return widget.conversationType != ConvType.group &&
            config.showVideoCall;
      }
      return true;
    }).toList();
  }

  _sendVideoMessage(String originFilePath, int duration, int size,
      TUIChatSeparateViewModel model) async {
    final canSend = await _runMediaTask<bool>('send_video_message', (_) async {
      if (!_hasUsableConversation()) {
        return null;
      }
      if (originFilePath.trim().isEmpty) {
        _showPanelNotice(TIM_t('视频文件不可用'));
        return null;
      }
      if (size > MorePanelConfig.VIDEO_MAX_SIZE) {
        onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO, infoRecommendText: TIM_t("文件大小超出当前限制")));
        return null;
      }
      return true;
    }, allowNested: true);
    if (canSend != true) {
      return;
    }

    final convID = widget.conversationID;
    final convType = widget.conversationType;
    if (!_hasUsableConversation()) {
      return;
    }
    _dispatchVideoSendWithoutAwait(
      model: model,
      convID: convID,
      convType: convType,
      videoPath: originFilePath,
      duration: duration,
    );
  }

  Future<void> _prepareAndDispatchGalleryVideo({
    required AssetEntity asset,
    required TUIChatSeparateViewModel model,
    required String convID,
    required ConvType convType,
    required String existingOptimisticId,
    GallerySendPerfTrace? perf,
  }) async {
    if (!_hasUsableConversation(convID) ||
        !_isCapturedConversationCurrent(convID, convType)) {
      model.cancelOptimisticMediaPlaceholder(
        convID: convID,
        clientId: existingOptimisticId,
      );
      return;
    }
    final prepared = await _prepareVideoFromGalleryAsset(
      asset,
      model: model,
      convID: convID,
      existingOptimisticId: existingOptimisticId,
      perf: perf,
    );
    if (prepared == null) {
      return;
    }
    if (!_isCapturedConversationCurrent(convID, convType)) {
      model.cancelOptimisticMediaPlaceholder(
        convID: convID,
        clientId: prepared.optimisticId ?? '',
      );
      return;
    }
    _dispatchVideoSendWithoutAwait(
      model: model,
      convID: convID,
      convType: convType,
      videoPath: prepared.videoPath,
      duration: prepared.duration,
      snapshotPath: prepared.snapshotPath,
      existingOptimisticId: prepared.optimisticId,
      perf: perf,
    );
  }

  Future<_PreparedVideoSend?> _prepareVideoFromGalleryAsset(
    AssetEntity asset, {
    required TUIChatSeparateViewModel model,
    required String convID,
    required String existingOptimisticId,
    GallerySendPerfTrace? perf,
  }) async {
    final watch = Stopwatch()..start();
    String? optimisticId = existingOptimisticId;
    try {
      perf?.log('video_prepare_begin', detail: 'source=custom');
      final originFile = await asset.originFile;
      if (originFile == null) {
        model.markOptimisticMediaPlaceholderFailed(
          convID: convID,
          clientId: optimisticId,
        );
        _showPanelNotice(TIM_t('视频文件不可用'));
        return null;
      }
      final size = await originFile.length();
      if (size > MorePanelConfig.VIDEO_MAX_SIZE) {
        model.markOptimisticMediaPlaceholderFailed(
          convID: convID,
          clientId: optimisticId,
        );
        onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("文件大小超出当前限制"),
        ));
        return null;
      }

      final filePath = originFile.path;
      final assetDuration = (asset.videoDuration.inMilliseconds / 1000).ceil();
      perf?.log(
        'video_source_ready',
        bytes: size,
        detail: 'itemMs=${watch.elapsedMilliseconds}',
      );
      final metadata = await Future.wait<Object?>([
        assetDuration > 0
            ? Future<int>.value(assetDuration)
            : _loadVideoDurationSeconds(filePath),
        buildVideoSnapshotForSend(
          videoPath: filePath,
          devicePixelRatio:
              mounted ? MediaQuery.devicePixelRatioOf(context) : null,
        ),
      ]);
      perf?.log('video_metadata_end', detail: 'itemMs=${watch.elapsedMilliseconds}');
      final duration = metadata[0] as int;
      final snapshotPath = metadata[1] as String?;
      model.hydrateOptimisticVideoPlaceholder(
        convID: convID,
        clientId: optimisticId,
        videoPath: filePath,
        duration: duration,
        snapshotPath: snapshotPath,
      );

      return _PreparedVideoSend(
        videoPath: filePath,
        duration: duration,
        snapshotPath: snapshotPath,
        optimisticId: optimisticId,
      );
    } catch (error) {
      if (optimisticId != null) {
        model.cancelOptimisticMediaPlaceholder(
          convID: convID,
          clientId: optimisticId!,
        );
      }
      onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t("视频文件异常"),
        infoCode: 6660415,
      ));
      outputLogger.i('send gallery video failed: $error');
      perf?.log('video_prepare_failed', detail: 'type=${error.runtimeType}');
      return null;
    }
  }

  _sendImageMessage(TUIChatSeparateViewModel model, TUITheme theme) async {
    model = model.captureMediaSender(
      convID: _capturedConversationId(model),
      convType: _capturedConversationType(model),
    );
    final perf = GallerySendPerfTrace(mode: 'more_panel_gallery')
      ..log('tap_send_gallery');
    await _runMediaTask<void>('pick_gallery_media', (dismissPicker) async {
      perf.log('media_task_enter');
      if (!_hasUsableConversation()) {
        perf.log('media_task_rejected_invalid_conversation');
        return;
      }
      try {
        final convID = _capturedConversationId(model);
        final convType = _capturedConversationType(model);

        perf.log('picker_route_decision_begin');
        final preferCustomPicker =
            await ChatGalleryPickUtils.shouldPreferCustomGalleryPicker();
        perf.log(
          'picker_route_decision_end',
          detail: preferCustomPicker ? 'custom' : 'system',
        );

        if (PlatformUtils().isMobile && !preferCustomPicker) {
          perf.log('system_picker_open');
          final systemFiles =
              await ChatGalleryPickUtils.pickSystemGalleryMedia(perf: perf);
          perf.log(
            'system_picker_returned',
            count: systemFiles?.length ?? 0,
            detail: systemFiles == null ? 'unavailable' : 'available',
          );
          if (systemFiles != null) {
            // 空列表代表用户主动取消，不应再弹出第二个相册。
            if (systemFiles.isEmpty) {
              perf.log('system_picker_cancelled');
              return;
            }
            // Android returns after its picker activity has handed the files
            // back. One Flutter frame is enough before showing chat rows.
            await dismissPicker(transitionSettled: Platform.isAndroid);
            await _dispatchSystemPickedMedia(
              files: systemFiles,
              model: model,
              convID: convID,
              convType: convType,
              perf: perf,
            );
            return;
          }
        }

        if (PlatformUtils().isMobile) {
          perf.log('custom_picker_open');
          final pickedAssets = await EditableAssetPicker.pickAssets(
            context,
            pickerConfig: const AssetPickerConfig(
              requestType: RequestType.common,
              maxAssets: ChatGalleryPickUtils.maxSelectedAssets,
            ),
            perf: perf,
          );
          perf.log(
            'custom_picker_returned',
            count: pickedAssets?.length ?? 0,
            detail: pickedAssets == null ? 'cancelled' : 'selected',
          );

          await dismissPicker(transitionSettled: true);
          if (pickedAssets != null && pickedAssets.isNotEmpty) {
            await _dispatchCustomPickedGalleryMedia(
              pickedAssets: pickedAssets,
              model: model,
              convID: convID,
              convType: convType,
              perf: perf,
            );
            return;
          }
        } else {
          perf.log('desktop_file_picker_open');
          FilePickerResult? result =
              await FilePicker.platform.pickFiles(type: FileType.media);
          perf.log(
            'desktop_file_picker_returned',
            detail: result == null || result.files.isEmpty
                ? 'cancelled'
                : 'selected',
          );
          if (result != null && result.files.isNotEmpty) {
            File file = File(result.files.single.path!);
            final String savePath = file.path;
            final String type = TencentUtils.getFileType(
                    savePath.split(".")[savePath.split(".").length - 1])
                .split("/")[0];

            if (type == "image") {
              final size = await file.length();
              if (size > MorePanelConfig.IMAGE_MAX_SIZE) {
                onTIMCallback(TIMCallback(
                    type: TIMCallbackType.INFO,
                    infoRecommendText: TIM_t("文件大小超出了限制")));
                return;
              }
              perf.log('desktop_image_send_begin', bytes: size);
              _dispatchImageSendWithoutAwait(
                model: model,
                convID: convID,
                convType: convType,
                filePath: savePath,
              );
              perf.log('desktop_image_send_queued');
              return;
            } else if (type == "video") {
              final size = await file.length();
              if (size > MorePanelConfig.VIDEO_MAX_SIZE) {
                onTIMCallback(TIMCallback(
                    type: TIMCallbackType.INFO,
                    infoRecommendText: TIM_t("文件大小超出当前限制")));
                return;
              }
              perf.log('desktop_video_send_begin', bytes: size);
              _dispatchVideoSendWithoutAwait(
                model: model,
                convID: convID,
                convType: convType,
                videoPath: savePath,
              );
              perf.log('desktop_video_send_queued');
              return;
            }
          } else {
            throw TypeError();
          }
        }
      } catch (err) {
        outputLogger.i("err: $err");
        perf.log(
          'media_task_failed',
          detail: 'type=${err.runtimeType}',
        );
        _setMediaState(_MediaWorkState.failed);
        await dismissPicker();
        if (mounted &&
            _isCapturedConversationCurrent(
              _capturedConversationId(model),
              _capturedConversationType(model),
            )) {
          _showPanelNotice(TIM_t('图片或视频未能发送，请重试'));
        }
      }
    });
    perf.log('media_task_returned');
    perf.markTaskReturned();
  }

  _sendImageFromCamera(TUIChatSeparateViewModel model, TUITheme theme) async {
    model = model.captureMediaSender(
      convID: _capturedConversationId(model),
      convType: _capturedConversationType(model),
    );
    final perf = GallerySendPerfTrace(mode: 'more_panel_camera')
      ..log('tap_send_camera');
    final prepared =
        await _runMediaTask<_CameraMediaPrepared?>('camera_media', (_) async {
      perf.log('camera_task_enter');
      if (!PlatformUtils().isMobile) {
        return null;
      }
      if (!_hasUsableConversation()) {
        return null;
      }
      String? capturedConvID;
      String? optimisticId;
      try {
        FocusManager.instance.primaryFocus?.unfocus();
        final convID = _capturedConversationId(model);
        final convType = _capturedConversationType(model);
        capturedConvID = convID;
        final rootNavigator = _captureRootNavigator();
        if (!_hasUsableConversation(convID)) {
          return null;
        }

        while (_hasUsableConversation(convID)) {
          if (!await _ensureSystemPermissionFast(Permission.camera)) {
            _showPanelNotice(TIM_t('未获得相机权限'));
            return null;
          }
          await _ensureSystemPermissionFast(Permission.microphone);

          _setMediaState(_MediaWorkState.picking);
          perf.log('camera_capture_page_open');
          final captured =
              await rootNavigator?.push<ChatCamerAwesomeCaptureResult>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const ChatCamerAwesomeCapturePage(),
            ),
          );
          final imagePath = captured?.imagePath?.trim() ?? '';
          final videoPath = captured?.videoPath?.trim() ?? '';
          perf.log(
            'camera_capture_page_returned',
            detail: imagePath.isNotEmpty
                ? 'photo'
                : videoPath.isNotEmpty
                    ? 'video'
                    : 'cancelled',
          );
          if (captured == null || (imagePath.isEmpty && videoPath.isEmpty)) {
            return null;
          }

          if (imagePath.isNotEmpty) {
            final originFile = File(imagePath);
            final size = await originFile.length();
            if (size > MorePanelConfig.IMAGE_MAX_SIZE) {
              onTIMCallback(
                TIMCallback(
                  type: TIMCallbackType.INFO,
                  infoRecommendText: TIM_t("文件大小超出了限制"),
                ),
              );
              return null;
            }

            perf.log('camera_preview_begin', bytes: size);
            final action = await _previewImageBeforeSend(
              filePath: imagePath,
              sizeBytes: size,
              canRetake: true,
              navigator: rootNavigator,
            );
            perf.log('camera_preview_end', detail: action.name);
            if (action == _MediaPreviewResult.retake) {
              continue;
            }
            if (action != _MediaPreviewResult.send) {
              return null;
            }

            // The sending pipeline owns file preparation after local UI insert.
            final stablePath = imagePath;

            return _CameraMediaPrepared(
              convID: convID,
              convType: convType,
              imagePath: stablePath,
              imageWidth: null,
              imageHeight: null,
            );
          }

          perf.log('camera_video_pick_returned', detail: 'captured');
          final originFile = File(videoPath);
          final size = await originFile.length();
          if (size > MorePanelConfig.VIDEO_MAX_SIZE) {
            onTIMCallback(
              TIMCallback(
                type: TIMCallbackType.INFO,
                infoRecommendText: TIM_t("文件大小超出当前限制"),
              ),
            );
            return null;
          }

          const durationSeconds = 0;
          perf.log('camera_video_preview_begin', bytes: size);
          final action = await _previewVideoBeforeSend(
            filePath: videoPath,
            sizeBytes: size,
            durationSeconds: captured.durationSeconds ?? durationSeconds,
            canRetake: true,
            navigator: rootNavigator,
          );
          perf.log('camera_video_preview_end', detail: action.action.name);
          if (action.action == _MediaPreviewResult.retake) {
            continue;
          }
          if (action.action != _MediaPreviewResult.send) {
            return null;
          }

          optimisticId = model.beginOptimisticVideoPlaceholder(
            convID: convID,
            videoPath: videoPath,
            duration: math.max(action.durationSeconds, durationSeconds),
          );
          final snapshotPath = await buildVideoSnapshotForSend(
            videoPath: videoPath,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          return _CameraMediaPrepared(
            convID: convID,
            convType: convType,
            video: _PreparedVideoSend(
              videoPath: videoPath,
              duration: math.max(action.durationSeconds, durationSeconds),
              snapshotPath: snapshotPath,
              optimisticId: optimisticId,
            ),
          );
        }
      } catch (error) {
        if (capturedConvID != null && optimisticId != null) {
          model.cancelOptimisticMediaPlaceholder(
            convID: capturedConvID!,
            clientId: optimisticId!,
          );
        }
        outputLogger.i("err: $error");
        perf.log('camera_task_failed', detail: 'type=${error.runtimeType}');
      }
      return null;
    });
    perf.log(
      'camera_task_returned',
      detail: prepared == null ? 'cancelled' : 'ready',
    );
    if (prepared == null) {
      perf.markTaskReturned();
      return;
    }
    // Overlay end is owned by _runMediaTask.finally (includes dismiss settle).
    perf.log('camera_dispatch_begin');
    _dispatchPreparedCameraMedia(model, prepared);
    perf.log('camera_dispatch_queued');
    perf.markTaskReturned();
  }

  _sendImageFileOnWeb(TUIChatSeparateViewModel model) async {
    model = model.captureMediaSender(
      convID: _capturedConversationId(model),
      convType: _capturedConversationType(model),
    );
    final perf = GallerySendPerfTrace(mode: 'more_panel_web_image')
      ..log('tap_send_web_image');
    try {
      final convID = _capturedConversationId(model);
      final convType = _capturedConversationType(model);
      if (!_hasUsableConversation(convID)) {
        return;
      }
      perf.log('web_picker_open');
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      perf.log(
        'web_picker_returned',
        detail: pickedFile == null ? 'cancelled' : 'selected',
      );
      if (pickedFile == null ||
          !_isCapturedConversationCurrent(convID, convType)) {
        return;
      }
      final imageContent = await pickedFile!.readAsBytes();
      fileName = pickedFile.name;
      tempFile = File(pickedFile.path);
      fileContent = imageContent;

      html.Node? inputElem;
      inputElem = html.document
          .getElementById("__image_picker_web-file-input")
          ?.querySelector("input");
      perf.log('web_send_begin', bytes: imageContent.length);
      _observeMediaSend(model.sendImageMessage(
              inputElement: inputElem,
              imagePath: tempFile?.path,
              convID: convID,
              convType: convType));
      perf.log('web_send_queued');
    } catch (e) {
      outputLogger.i("_sendFileErr: ${e.toString()}");
      perf.log('web_send_failed', detail: 'type=${e.runtimeType}');
    }
    perf.markTaskReturned();
  }

  _sendVideoFileOnWeb(TUIChatSeparateViewModel model) async {
    model = model.captureMediaSender(
      convID: _capturedConversationId(model),
      convType: _capturedConversationType(model),
    );
    final perf = GallerySendPerfTrace(mode: 'more_panel_web_video')
      ..log('tap_send_web_video');
    try {
      final convID = _capturedConversationId(model);
      final convType = _capturedConversationType(model);
      if (!_hasUsableConversation(convID)) {
        return;
      }
      perf.log('web_picker_open');
      final pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
      perf.log(
        'web_picker_returned',
        detail: pickedFile == null ? 'cancelled' : 'selected',
      );
      if (pickedFile == null ||
          !_isCapturedConversationCurrent(convID, convType)) {
        return;
      }
      final videoContent = await pickedFile!.readAsBytes();
      fileName = pickedFile.name;
      tempFile = File(pickedFile.path);
      fileContent = videoContent;

      if (fileName!.split(".")[fileName!.split(".").length - 1] != "mp4") {
        onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t("视频消息仅限 mp4 格式"),
            infoCode: 6660412));
        return;
      }

      html.Node? inputElem;
      inputElem = html.document
          .getElementById("__image_picker_web-file-input")
          ?.querySelector("input");
      _observeMediaSend(model.sendVideoMessage(
              inputElement: inputElem,
              videoPath: tempFile?.path,
              convID: convID,
              convType: convType));
      perf.log('web_send_queued', bytes: videoContent.length);
    } catch (e) {
      outputLogger.i("_sendFileErr: ${e.toString()}");
      perf.log('web_send_failed', detail: 'type=${e.runtimeType}');
    }
    perf.markTaskReturned();
  }

  void _observeMediaSend(Future<dynamic> future) {
    // The task owns its lifetime; observing completion must not read a disposed context.
    unawaited(future.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      outputLogger.i('media send failed: ${error.runtimeType}');
    }));
  }

  _sendFile(
    TUIChatSeparateViewModel model,
    TUITheme theme,
  ) async {
    model = model.captureMediaSender(
      convID: _capturedConversationId(model),
      convType: _capturedConversationType(model),
    );
    if (!_hasUsableConversation()) {
      return;
    }
    try {
      final convID = _capturedConversationId(model);
      final convType = _capturedConversationType(model);
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        if (PlatformUtils().isWeb) {
          html.Node? inputElem;
          inputElem = html.document
              .getElementById("__file_picker_web-file-input")
              ?.querySelector("input");
          fileName = result.files.single.name;

          if (!_isCapturedConversationCurrent(convID, convType)) {
            return;
          }

          _observeMediaSend(model.sendFileMessage(
                  inputElement: inputElem,
                  fileName: fileName,
                  convID: convID,
                  convType: convType));
          return;
        }

        String? option2 = result.files.single.path ?? "";
        outputLogger
            .i(TIM_t_para("选择成功{{option2}}", "选择成功$option2")(option2: option2));

        final pickedPath = result.files.single.path;
        if (pickedPath == null || pickedPath.isEmpty) {
          return;
        }
        if (!_isCapturedConversationCurrent(convID, convType)) {
          return;
        }
        File file = File(pickedPath);
        final int size = await file.length();
        if (!_isCapturedConversationCurrent(convID, convType)) {
          return;
        }
        if (size > MorePanelConfig.FILE_MAX_SIZE) {
          onTIMCallback(TIMCallback(
              type: TIMCallbackType.INFO,
              infoRecommendText: TIM_t("文件大小超出当前限制")));
          return;
        }

        final String savePath = file.path;

        _observeMediaSend(model.sendFileMessage(
                filePath: savePath,
                size: size,
                convID: convID,
                convType: convType));
      } else {
        throw TypeError();
      }
    } catch (e) {
      outputLogger.i("_sendFileErr: ${e.toString()}");
    }
  }

  _onFeatureTap(
    String id,
    BuildContext context,
    TUIChatSeparateViewModel model,
    TUITheme theme,
  ) async {
    // Do not set _featureBusy here. Media actions use _runMediaTask(),
    // otherwise the outer lock blocks its own camera/gallery task and shows
    // "正在处理上一项操作" before the picker opens.
    switch (id) {
      case "photo":
        await _sendImageMessage(model, theme);
        break;
      case "take_photo":
        await _sendImageFromCamera(model, theme);
        break;
      case "file":
        await _runMediaTask<void>('pick_file', (_) async {
          await _sendFile(model, theme);
          return null;
        });
        break;
      case "image":
        // only for web
        await _sendImageFileOnWeb(model);
        break;
      case "video":
        // only for web
        await _sendVideoFileOnWeb(model);
        break;
      case "avCall":
        if (widget.conversationType != ConvType.group) {
          await _showAvCallTypePicker(theme);
        }
        break;
      case "voiceCall":
        if (widget.conversationType != ConvType.group) {
          await _goToVideoUI(TYPE_AUDIO);
        }
        break;
      case "videoCall":
        if (widget.conversationType != ConvType.group) {
          await _goToVideoUI(TYPE_VIDEO);
        }
        break;
    }
  }

  Future<void> _showAvCallTypePicker(TUITheme theme) async {
    final config = widget.morePanelConfig ?? MorePanelConfig();
    final showVideo = config.showVideoCall;
    final showVoice = config.showVoiceCall;
    if (!showVideo && !showVoice) {
      return;
    }

    final actionColor = theme.primaryColor ?? const Color(0xFF007AFF);
    final actions = <CupertinoActionSheetAction>[];
    if (showVideo) {
      actions.add(
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, TYPE_VIDEO),
          child: Text(
            TIM_t("视频通话"),
            style: TextStyle(color: actionColor, fontSize: 20),
          ),
        ),
      );
    }
    if (showVoice) {
      actions.add(
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, TYPE_AUDIO),
          child: Text(
            TIM_t("语音通话"),
            style: TextStyle(color: actionColor, fontSize: 20),
          ),
        ),
      );
    }

    final callType = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: actions,
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(
              TIM_t("取消"),
              style: TextStyle(color: actionColor, fontSize: 20),
            ),
          ),
        );
      },
    );

    if (callType != null && mounted) {
      await _goToVideoUI(callType);
    }
  }

  Future<bool> _ensureSystemPermissionFast(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }
    final requested = await permission.request();
    return requested.isGranted || requested.isLimited;
  }

  _goToVideoUI(String type) async {
    if (!_hasUsableConversation()) {
      return;
    }
    final isVideo = type == TYPE_VIDEO;
    if (widget.conversationType == ConvType.group) {
      return;
    }
    final peerId = CallLauncher.normalizeC2CUserId(widget.conversationID);
    await CallLauncher.startC2C(
      context,
      userId: peerId,
      video: isVideo,
      conversationId: CallLauncher.c2cConversationId(peerId),
    );
  }

  static const int _itemsPerPage = 8;

  List<List<MorePanelItem>> _chunkItems(List<MorePanelItem> items) {
    final pages = <List<MorePanelItem>>[];
    for (var i = 0; i < items.length; i += _itemsPerPage) {
      final end = i + _itemsPerPage;
      pages.add(items.sublist(i, end > items.length ? items.length : end));
    }
    return pages;
  }

  double _itemSpacing(double screenWidth) {
    return (screenWidth - (23 * 2) - 64 * 4) / 3;
  }

  Widget _buildMorePanelItem(MorePanelItem item, TUITheme theme) {
    return InkWell(
      onTap: () {
        if (item.onTap != null) {
          item.onTap!(context);
        }
      },
      child: widget.morePanelConfig?.actionBuilder != null
          ? widget.morePanelConfig!.actionBuilder!(item)
          : SizedBox(
              height: 94,
              width: 64,
              child: Column(
                children: [
                  SizedBox(
                    height: 64,
                    width: 64,
                    child: item.icon,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: MorePanelStyles.labelColor(theme),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemGrid(
    List<MorePanelItem> items,
    TUITheme theme,
    double screenWidth, {
    double? layoutWidth,
  }) {
    final grid = Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: _itemSpacing(screenWidth),
      runSpacing: 20,
      children: items.map((item) => _buildMorePanelItem(item, theme)).toList(),
    );
    if (layoutWidth == null) {
      return grid;
    }
    return SizedBox(
      width: layoutWidth,
      child: grid,
    );
  }

  Widget _buildPageIndicator(int pageCount, TUITheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(pageCount, (index) {
          final selected = index == _currentPage;
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? (theme.primaryColor ?? Colors.blue)
                  : (theme.weakTextColor ?? Colors.grey).withOpacity(0.45),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;
    final TUIChatSeparateViewModel model =
        Provider.of<TUIChatSeparateViewModel>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final items = itemList(context, model, theme);
    final pages = _chunkItems(items);
    final useHorizontalPaging = pages.length > 1;

    Widget panelBody;
    if (!useHorizontalPaging) {
      panelBody = _buildItemGrid(items, theme, screenWidth);
    } else {
      panelBody = Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const PageScrollPhysics(),
              itemCount: pages.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, pageIndex) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: _buildItemGrid(
                        pages[pageIndex],
                        theme,
                        screenWidth,
                        layoutWidth: constraints.maxWidth,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildPageIndicator(pages.length, theme),
        ],
      );
    }

    return Container(
      // Keep the media panel at 70% of the former 248px height.
      height: 174,
      decoration: BoxDecoration(
        color: MorePanelStyles.panelBackground(theme),
        border: Border(
          top: BorderSide(
            width: 1,
            color: MorePanelStyles.dividerColor(theme),
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
      width: screenWidth,
      child: panelBody,
    );
  }
}

class _ImageMediaPreviewPage extends StatelessWidget {
  final String filePath;
  final String sizeText;
  final bool canRetake;

  const _ImageMediaPreviewPage({
    required this.filePath,
    required this.sizeText,
    required this.canRetake,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.file(
                  File(filePath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_outlined,
                              color: Colors.white70, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            TIM_t('图片文件不可用，请重试'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context)
                            .pop(_MediaPreviewResult.cancel),
                      ),
                      Expanded(
                        child: Text(
                          TIM_t('预览'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 18 + bottomPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          sizeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                              onPressed: () => Navigator.of(context).pop(
                                canRetake
                                    ? _MediaPreviewResult.retake
                                    : _MediaPreviewResult.cancel,
                              ),
                              child:
                                  Text(canRetake ? TIM_t('重拍') : TIM_t('删除')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                              onPressed: () => Navigator.of(context)
                                  .pop(_MediaPreviewResult.send),
                              child: Text(TIM_t('发送')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMediaPreviewPage extends StatefulWidget {
  final String filePath;
  final String sizeText;
  final int durationSeconds;
  final bool canRetake;

  const _VideoMediaPreviewPage({
    required this.filePath,
    required this.sizeText,
    required this.durationSeconds,
    required this.canRetake,
  });

  @override
  State<_VideoMediaPreviewPage> createState() => _VideoMediaPreviewPageState();
}

class _VideoMediaPreviewPageState extends State<_VideoMediaPreviewPage> {
  @override
  Widget build(BuildContext context) => ChatVideoDraftPreview(
    filePath: widget.filePath,
    sizeText: widget.sizeText,
    durationSeconds: widget.durationSeconds,
    canRetake: widget.canRetake,
    onCancel: () => Navigator.of(context).pop<_VideoPreviewResult>(
      _VideoPreviewResult(_MediaPreviewResult.cancel, widget.durationSeconds)),
    onRetake: () => Navigator.of(context).pop<_VideoPreviewResult>(
      _VideoPreviewResult(_MediaPreviewResult.retake, widget.durationSeconds)),
    onSend: (seconds) => Navigator.of(context).pop<_VideoPreviewResult>(
      _VideoPreviewResult(_MediaPreviewResult.send, seconds)),
  );
}
