import 'package:tencent_cloud_chat_demo/src/widgets/app_qr_icon.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_share_service.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/qr_share_file_access.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_scanner_launcher.dart';
import 'package:tencent_cloud_chat_demo/src/services/share_app_service.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_share_picker_page.dart';

enum QRCodePageType { user, group }

class QRCodePage extends StatefulWidget {
  final QRCodePageType type;
  final bool isChannel;
  final String title;
  final String displayName;
  final String aliasLabel;
  final String aliasValue;

  /// Full group ID written into QR JSON; [aliasValue] is display-only.
  final String? qrPayloadId;
  final String faceUrl;
  final String shareText;

  /// Web / 桌面弹窗内嵌：去掉全屏 AppBar，由外层弹窗标题栏负责关闭。
  final bool embedded;

  const QRCodePage({
    Key? key,
    required this.type,
    this.isChannel = false,
    required this.title,
    required this.displayName,
    required this.aliasLabel,
    required this.aliasValue,
    this.qrPayloadId,
    required this.faceUrl,
    required this.shareText,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<QRCodePage> createState() => _QRCodePageState();
}

class _QRCodePageState extends State<QRCodePage> {
  final V2TIMManager _sdkInstance = TIMUIKitCore.getSDKInstance();
  final GlobalKey _captureKey = GlobalKey();
  static const String _brandLogoAsset = 'assets/img/99chat_logo.png';
  String? _localDisplayName;
  String? _localUserId;
  int? _localGender;
  int? _groupMemberCount;
  bool _joinOptionsLoaded = false;
  bool _allowJoinByQrCode = true;
  bool _landingUrlResolved = false;
  String _landingUrl = '';

  bool get _isGroupQr => widget.type == QRCodePageType.group;

  bool get _canShowGroupQr =>
      !_isGroupQr || (_joinOptionsLoaded && _allowJoinByQrCode);

  bool get _qrPayloadReady =>
      _landingUrlResolved && (!_isGroupQr || _joinOptionsLoaded);

  @override
  void initState() {
    super.initState();
    unawaited(_loadQrLandingUrl());
    if (widget.type == QRCodePageType.user) {
      final passed = ChatIdFormat.rawUserUid(widget.aliasValue);
      final self = ChatIdFormat.rawUserUid(
        ContactSocialCacheStore.safeLoginUserId(),
      );
      if (passed.isEmpty || passed == self) {
        unawaited(_loadLocalUserIdentity());
      }
    } else {
      unawaited(_loadGroupJoinOptions());
      unawaited(_loadGroupMemberCount());
    }
  }

  Future<void> _loadGroupMemberCount() async {
    final groupId = _resolveQrPayloadId();
    if (groupId.isEmpty) return;
    try {
      final response = await _sdkInstance
          .getGroupManager()
          .getGroupsInfo(groupIDList: [groupId]);
      if (!mounted || response.code != 0) return;
      for (final item in response.data ?? []) {
        final info = item.groupInfo;
        if ((item.resultCode ?? 0) == 0 &&
            info != null &&
            ChatIdFormat.groupIdsEquivalent(info.groupID, groupId)) {
          final count = info.memberCount;
          if (count != null && count >= 0) {
            setState(() => _groupMemberCount = count);
          }
          return;
        }
      }
    } catch (_) {
      // Keep unknown counts hidden rather than showing a misleading zero.
    }
  }

  Future<void> _loadQrLandingUrl() async {
    final url = await ShareAppService.instance.resolveQrLandingUrl();
    if (!mounted) {
      return;
    }
    setState(() {
      _landingUrl = url;
      _landingUrlResolved = true;
    });
  }

  Future<void> _loadGroupJoinOptions() async {
    final groupId = widget.qrPayloadId?.trim() ?? '';
    if (groupId.isEmpty) {
      if (!mounted) return;
      setState(() => _joinOptionsLoaded = true);
      return;
    }
    try {
      final options = await GroupJoinApi.instance.fetchJoinOptions(groupId);
      if (!mounted) return;
      setState(() {
        _allowJoinByQrCode = options.allowJoinByQrCode;
        _joinOptionsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allowJoinByQrCode = true;
        _joinOptionsLoaded = true;
      });
    }
  }

  Future<void> _loadLocalUserIdentity() async {
    final lookupId = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    final fallbackId = lookupId.isNotEmpty
        ? lookupId
        : ChatIdFormat.rawUserUid(widget.aliasValue);
    if (fallbackId.isEmpty) {
      return;
    }
    final record = await UserProfileLocalService.instance.read(fallbackId);
    if (!mounted) {
      return;
    }
    if (record != null) {
      final nickname = record.nickname.trim();
      final userId = record.userId.trim();
      if (nickname.isNotEmpty || userId.isNotEmpty || record.gender != null) {
        setState(() {
          if (nickname.isNotEmpty) {
            _localDisplayName = nickname;
          }
          if (userId.isNotEmpty) {
            _localUserId = ChatIdFormat.display(userId);
          }
          _localGender = record.gender;
        });
      }
    }
    if (_localGender == null || _localGender == 0) {
      await _loadGenderFromSdk(fallbackId);
    }
  }

  /// 本地档案没有性别时向 SDK 兜底查一次（性别图标用）。
  Future<void> _loadGenderFromSdk(String userId) async {
    try {
      final res = await _sdkInstance.getUsersInfo(userIDList: [userId]);
      final gender = res.data?.firstOrNull?.gender;
      if (!mounted || gender == null) {
        return;
      }
      setState(() => _localGender = gender);
    } catch (_) {}
  }

  String get _effectiveDisplayName {
    if (widget.type != QRCodePageType.user) {
      return widget.displayName;
    }
    final local = _localDisplayName?.trim();
    if (local != null && local.isNotEmpty) {
      return local;
    }
    return widget.displayName;
  }

  String get _effectiveAliasValue {
    if (widget.type != QRCodePageType.user) {
      return widget.aliasValue;
    }
    final local = _localUserId?.trim();
    if (local != null && local.isNotEmpty) {
      return local;
    }
    return widget.aliasValue;
  }

  String _resolveQrPayloadId() {
    if (widget.type == QRCodePageType.group) {
      final full = widget.qrPayloadId?.trim() ?? '';
      if (full.isNotEmpty) {
        return full;
      }
      return ChatIdFormat.normalizeGroupId(widget.aliasValue);
    }
    return ChatIdFormat.rawUserUid(_effectiveAliasValue);
  }

  String _buildQrData() {
    return QrAppPayload.encode(
      baseUrl: _landingUrl,
      type: widget.type == QRCodePageType.user
          ? QrAppPayloadType.user
          : QrAppPayloadType.group,
      id: _resolveQrPayloadId(),
      name: _effectiveDisplayName,
    );
  }

  Future<Uint8List?> _captureQrImageBytes() async {
    try {
      final renderObject = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (renderObject == null) {
        return null;
      }
      final image = await renderObject.toImage(pixelRatio: 3);
      try {
        // Gallery encoders may discard alpha; flatten rounded corners first.
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        canvas.drawImage(image, Offset.zero, Paint());
        final picture = recorder.endRecording();
        try {
          final opaqueImage = await picture.toImage(image.width, image.height);
          try {
            final byteData =
                await opaqueImage.toByteData(format: ui.ImageByteFormat.png);
            return byteData?.buffer.asUint8List();
          } finally {
            opaqueImage.dispose();
          }
        } finally {
          picture.dispose();
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveImage() async {
    if (kIsWeb) {
      ToastUtils.toast(TIM_t(
          "\u5f53\u524d\u6682\u4e0d\u652f\u6301\u4fdd\u5b58\u56fe\u7247"));
      return;
    }
    final bytes = await _captureQrImageBytes();
    if (bytes == null) {
      ToastUtils.toast(TIM_t("\u4fdd\u5b58\u5931\u8d25"));
      return;
    }
    final fileName = widget.type == QRCodePageType.user
        ? "user_qr_${_effectiveAliasValue}"
        : "group_qr_${widget.aliasValue}";
    final result = await ImageGallerySaverPlus.saveImage(
      bytes,
      quality: 100,
      name: fileName,
    );
    if (!mounted) {
      return;
    }
    if (result != null) {
      ToastUtils.toast(TIM_t("\u56fe\u7247\u5df2\u4fdd\u5b58"));
      return;
    }
    ToastUtils.toast(TIM_t("\u4fdd\u5b58\u5931\u8d25"));
  }

  Future<_ShareTarget?> _showShareTargetPicker(TUITheme theme) async {
    final target = await ConversationSharePickerPage.open(
      context,
      theme: theme,
    );
    if (target == null) {
      return null;
    }
    return _ShareTarget(userID: target.userID, groupID: target.groupID);
  }

  Future<void> _shareToFriend(TUITheme theme) async {
    final target = await _showShareTargetPicker(theme);
    if (!mounted || target == null) {
      return;
    }
    if (!kIsWeb) {
      final imagePath = await _createShareImageFile();
      if (imagePath != null) {
        final createImageRes =
            await _sdkInstance.getMessageManager().createImageMessage(
                  imagePath: imagePath,
                  imageName: widget.type == QRCodePageType.user
                      ? 'my_qr_code.png'
                      : 'group_qr_code.png',
                );
        final imageMessageId = createImageRes.data?.id;
        if (createImageRes.code == 0 &&
            imageMessageId != null &&
            imageMessageId.isNotEmpty) {
          final sent = await ChatExternalMessageSender.sendCreatedMessage(
            messageInfo: createImageRes.data?.messageInfo,
            receiverUserId: target.userID,
            groupId: target.groupID,
            reason: 'qr_code_share_image_sent',
          );
          if (sent) {
            ToastUtils.toast(TIM_t("\u5df2\u5206\u4eab"));
            return;
          }
        }
      }
    }

    final createMessageRes = await _sdkInstance
        .getMessageManager()
        .createTextMessage(text: widget.shareText);
    final messageID = createMessageRes.data?.id;
    if (createMessageRes.code == 0 &&
        messageID != null &&
        messageID.isNotEmpty) {
      final sent = await ChatExternalMessageSender.sendCreatedMessage(
        messageInfo: createMessageRes.data?.messageInfo,
        receiverUserId: target.userID,
        groupId: target.groupID,
        reason: 'qr_code_share_text_fallback_sent',
      );
      if (sent) {
        ToastUtils.toast(TIM_t("\u5df2\u5206\u4eab"));
        return;
      }
    }
    ToastUtils.toast(TIM_t("\u5206\u4eab\u5931\u8d25"));
  }

  Future<String?> _createShareImageFile() async {
    final bytes = await _captureQrImageBytes();
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = widget.type == QRCodePageType.user
          ? 'my_qr_${_effectiveAliasValue}'
          : 'group_qr_${widget.aliasValue}';
      return writeQrShareImageFile(
        dirPath: tempDir.path,
        fileName: '$safeName.png',
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openScanner() async {
    await QRScannerLauncher.open(context);
  }

  Widget _buildIdentityAvatar(double size, _QrPagePalette palette) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: widget.type == QRCodePageType.group
            ? Avatar(
                faceUrl: widget.faceUrl,
                showName: _effectiveDisplayName,
                type: 2,
                borderRadius: BorderRadius.zero,
              )
            : AppUserAvatar(
                faceUrl: widget.faceUrl,
                showName: _effectiveDisplayName,
                size: size,
                borderRadius: BorderRadius.zero,
              ),
      ),
    );
  }

  Widget _buildQrCenterLogo(double size) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: Image.asset(
          _brandLogoAsset,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildSimpleQr({
    required String qrData,
    required double size,
  }) {
    return QrImageView(
      data: qrData,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }

  Widget _buildQrFrame({
    required String qrData,
    required double qrSize,
    required double qrLogoSize,
    required _QrPagePalette palette,
  }) {
    const framePadding = 14.0;
    final frameSize = qrSize + framePadding * 2;
    return SizedBox(
      width: frameSize,
      height: frameSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.qrFrameBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.primary
                      .withValues(alpha: palette.isDark ? 0.35 : 0.22),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary
                        .withValues(alpha: palette.isDark ? 0.2 : 0.12),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _QrCornerFramePainter(color: palette.primary),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              _buildSimpleQr(qrData: qrData, size: qrSize),
              _buildQrCenterLogo(qrLogoSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrandMark(double logoSize, _QrPagePalette palette) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(logoSize * 0.24),
          child: Image.asset(
            _brandLogoAsset,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '99Chat',
          maxLines: 1,
          style: TextStyle(
            color: palette.brandText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildDotGrid({
    required double width,
    required double height,
    required Color color,
    Alignment alignment = Alignment.center,
  }) {
    return Align(
      alignment: alignment,
      child: CustomPaint(
        size: Size(width, height),
        painter: _DotGridPainter(color: color),
      ),
    );
  }

  Future<void> _showQrActionSheet(TUITheme theme) async {
    final action = await AppDialog.actionSheet<String>(
      title: TIM_t("\u4e8c\u7ef4\u7801"),
      cancelText: TIM_t("\u53d6\u6d88"),
      actionContentWidth: 132,
      actions: [
        AppActionSheetItem<String>(
          text: TIM_t("\u4fdd\u5b58\u56fe\u7247"),
          value: 'save',
        ),
        if (!kIsWeb)
          AppActionSheetItem<String>(
            text: TIM_t("\u626b\u4e00\u626b"),
            value: 'scan',
          ),
        AppActionSheetItem<String>(
          text: TIM_t("\u5206\u4eab\u597d\u53cb"),
          value: 'share',
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    _handleSheetAction(action, theme);
  }

  void _handleSheetAction(String value, TUITheme theme) {
    switch (value) {
      case 'save':
        _saveImage();
        break;
      case 'scan':
        _openScanner();
        break;
      case 'share':
        _shareToFriend(theme);
        break;
    }
  }

  Widget _buildQrDisabledPlaceholder({
    required double qrSize,
    required _QrPagePalette palette,
  }) {
    final i18n = AppI18n.of(context);
    const framePadding = 14.0;
    final frameSize = qrSize + framePadding * 2;
    return SizedBox(
      width: frameSize,
      height: frameSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.disabledBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppQrIcon(
                size: 48,
                color: palette.disabledIcon,
              ),
              const SizedBox(height: 14),
              Text(
                i18n.t(
                  zhHans: widget.isChannel ? '管理员已关闭频道二维码订阅方式' : '管理员已关闭群二维码加入方式',
                  zhHant: widget.isChannel ? '管理員已關閉頻道 QR 碼訂閱方式' : '管理員已關閉群 QR 碼加入方式',
                  en: widget.isChannel ? 'Channel admins have disabled subscribing via QR code' : 'Group admins have disabled joining via QR code',
                  ja: widget.isChannel ? '管理者がQRコードによるチャンネル登録を無効にしています' : '管理者がQRコードによる参加を無効にしています',
                  ko: widget.isChannel ? '관리자가 QR 코드 채널 구독을 비활성화했습니다' : '관리자가 QR 코드 가입을 비활성화했습니다',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareCard({
    required String qrData,
    required double maxWidth,
    required bool showQrCode,
    required bool loadingQrOptions,
    required _QrPagePalette palette,
  }) {
    final compact = widget.embedded;
    final cardWidth = maxWidth
        .clamp(compact ? 240.0 : 280.0, compact ? 300.0 : 360.0)
        .toDouble();
    final avatarSize = compact ? 48.0 : 62.0;
    final qrSize = (cardWidth * (compact ? 0.52 : 0.56))
        .clamp(compact ? 148.0 : 188.0, compact ? 172.0 : 216.0)
        .toDouble();
    final qrLogoSize = (qrSize * 0.18)
        .clamp(compact ? 28.0 : 34.0, compact ? 36.0 : 44.0)
        .toDouble();
    final brandLogoSize = compact ? 22.0 : 28.0;
    // 个人码的身份图标按性别显示：男蓝、女粉、未知不显示（与资料页一致）。
    final Widget? identityIcon = widget.type == QRCodePageType.group
        ? null
        : switch (_localGender) {
            1 => const Icon(
                Icons.male_rounded,
                color: Color(0xFF4DA3FF),
                size: 20,
              ),
            2 => const Icon(
                Icons.female_rounded,
                color: Color(0xFFFF6B9D),
                size: 20,
              ),
            _ => null,
          };
    final hintText = widget.isChannel
        ? AppI18n.of(context).t(
            zhHans: '扫描二维码订阅频道',
            zhHant: '掃描 QR 碼訂閱頻道',
            en: 'Scan to subscribe to the channel',
            ja: 'QRコードをスキャンしてチャンネルを登録',
            ko: 'QR 코드를 스캔하여 채널 구독',
          )
        : widget.type == QRCodePageType.group
        ? TIM_t('扫描二维码加入群聊')
        : TIM_t('扫描二维码添加我为联系人');

    return Center(
      child: SizedBox(
        width: cardWidth,
        child: Container(
          decoration: BoxDecoration(
            color: palette.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.cardBg, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: palette.cardShadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: 18,
                right: 18,
                child: _buildDotGrid(
                  width: 56,
                  height: 40,
                  color: palette.dotGrid,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: compact ? 48 : 60,
                child: CustomPaint(
                  painter: _CardWavePainter(color: palette.primary),
                ),
              ),
              Positioned(
                left: compact ? 14 : 18,
                bottom: compact ? 14 : 18,
                child: _buildDotGrid(
                  width: compact ? 32 : 40,
                  height: compact ? 22 : 28,
                  color: palette.dotGrid,
                ),
              ),
              Positioned(
                right: compact ? 14 : 18,
                bottom: compact ? 14 : 18,
                child: _buildDotGrid(
                  width: compact ? 32 : 40,
                  height: compact ? 22 : 28,
                  color: palette.dotGrid,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 22,
                  compact ? 12 : 16,
                  compact ? 16 : 22,
                  compact ? 10 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildIdentityAvatar(avatarSize, palette),
                        SizedBox(width: compact ? 10 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _effectiveDisplayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.name,
                                        fontSize: compact ? 16 : 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (identityIcon != null) ...[
                                    const SizedBox(width: 6),
                                    identityIcon,
                                  ],
                                ],
                              ),
                              SizedBox(height: compact ? 4 : 6),
                              Text(
                                '${widget.aliasLabel}: ${_effectiveAliasValue}',
                                maxLines: compact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.secondary,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if (_isGroupQr && _groupMemberCount != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: palette.isDark
                                        ? const Color(0xFF29313C)
                                        : const Color(0xFFF4F5F7),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.people_outline_rounded,
                                            size: 17, color: palette.secondary),
                                        const SizedBox(width: 6),
                                        Flexible(
                                            child: Text(
                                                AppI18n.of(context).t(
                                                    zhHans: widget.isChannel ? '$_groupMemberCount 位订阅者' : '$_groupMemberCount 人',
                                                    zhHant: widget.isChannel ? '$_groupMemberCount 位訂閱者' : '$_groupMemberCount 人',
                                                    en: widget.isChannel ? '$_groupMemberCount subscribers' : '$_groupMemberCount members',
                                                    ja: widget.isChannel ? '登録者 $_groupMemberCount 人' : '$_groupMemberCount 人',
                                                    ko: widget.isChannel ? '구독자 $_groupMemberCount명' : '$_groupMemberCount명'),
                                                style: TextStyle(
                                                    color: palette.secondary,
                                                    fontSize:
                                                        compact ? 12 : 13))),
                                      ]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    if (loadingQrOptions)
                      SizedBox(
                        width: qrSize + 28,
                        height: qrSize + 28,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: palette.primary,
                          ),
                        ),
                      )
                    else if (showQrCode)
                      _buildQrFrame(
                        qrData: qrData,
                        qrSize: qrSize,
                        qrLogoSize: qrLogoSize,
                        palette: palette,
                      )
                    else
                      _buildQrDisabledPlaceholder(
                        qrSize: qrSize,
                        palette: palette,
                      ),
                    if (showQrCode) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              hintText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.secondary,
                                fontSize: compact ? 12 : 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(TIM_t('分享二维码，连接更多朋友'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: palette.secondary,
                              fontSize: 12,
                              height: 1.5)),
                      const SizedBox(height: 8),
                      Divider(
                          color: palette.cardBorder, height: 12, thickness: .5),
                      _buildBrandMark(brandLogoSize, palette),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required bool filled,
    required _QrPagePalette palette,
    required VoidCallback onTap,
  }) {
    final radius = BorderRadius.circular(28);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            height: widget.embedded ? 44 : 52,
            decoration: BoxDecoration(
              color: filled ? palette.primary : palette.outlineButtonBg,
              borderRadius: radius,
              border: filled
                  ? null
                  : Border.all(color: palette.primary, width: 1.4),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: filled ? Colors.white : palette.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: filled ? Colors.white : palette.primary,
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(_QrPagePalette palette) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 16 : 24,
        widget.embedded ? 4 : 8,
        widget.embedded ? 16 : 24,
        widget.embedded ? 12 : 16,
      ),
      child: Row(
        children: [
          _buildBottomActionItem(
            icon: Icons.download_rounded,
            label: TIM_t('保存图片'),
            filled: false,
            palette: palette,
            onTap: _saveImage,
          ),
          if (!kIsWeb) ...[
            const SizedBox(width: 14),
            _buildBottomActionItem(
              icon: Icons.qr_code_scanner_rounded,
              label: TIM_t("\u626b\u4e00\u626b"),
              filled: true,
              palette: palette,
              onTap: _openScanner,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _shareInvitation(String target) async {
    final payload = _buildQrData();
    final uri = Uri.tryParse(payload);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      ToastUtils.toast(TIM_t('邀请链接暂不可用，请保存二维码分享'));
      return;
    }
    final i18n = AppI18n.of(context);
    final name = _effectiveDisplayName.trim();
    final invitation = widget.isChannel
        ? i18n.t(
            zhHans: '邀请你订阅频道「$name」\n在 99Chat 查看最新内容：',
            zhHant: '邀請你訂閱頻道「$name」\n在 99Chat 查看最新內容：',
            en: 'Subscribe to "$name" on 99Chat for the latest updates:',
            ja: '99Chatでチャンネル「$name」を登録して最新情報をご覧ください：',
            ko: '99Chat에서 "$name" 채널을 구독하고 최신 소식을 확인하세요:',
          )
        : _isGroupQr
        ? i18n.t(
            zhHans: '邀请你加入「$name」\n一起交流，分享精彩。\n在 99Chat 与我们相聚：',
            zhHant: '邀請你加入「$name」\n一起交流，分享精彩。\n在 99Chat 與我們相聚：',
            en: 'You’re invited to "$name"!\nShare ideas and moments with us on 99Chat:',
            ja: '「$name」に招待します！\n99Chatで一緒に交流しましょう：',
            ko: '「$name」에 초대합니다!\n99Chat에서 함께 이야기해요:',
          )
        : i18n.t(
            zhHans: '你好，我是$name\n邀请你在 99Chat 添加我为好友，随时聊聊、分享日常。\n我的好友邀请：',
            zhHant: '你好，我是$name\n邀請你在 99Chat 加我為好友，隨時聊聊、分享日常。\n我的好友邀請：',
            en: 'Hi, I’m $name!\nAdd me on 99Chat to stay in touch and share everyday moments.\nMy friend invitation:',
            ja: 'こんにちは、$nameです！\n99Chatで友だちになって、日々の出来事を共有しましょう。\n友だちへの招待：',
            ko: '안녕하세요, $name입니다!\n99Chat에서 친구가 되어 일상을 나눠요.\n친구 초대:',
          );
    final shareText = '$invitation\n$payload';
    final service = WalletShareService();
    if (target == 'more') {
      final result = await service.shareSystemText(shareText);
      if (!mounted) return;
      if (result != WalletSystemShareResult.success) {
        ToastUtils.toast(TIM_t('系统分享暂不可用，请复制链接或保存图片'));
      }
      return;
    }
    final copied = await service.copyAddr(shareText);
    if (!mounted) return;
    if (copied != WalletCopyResult.success) {
      ToastUtils.toast(TIM_t('复制失败，请重试'));
      return;
    }
    if (target == 'copy') {
      ToastUtils.toast(TIM_t('邀请链接已复制'));
      return;
    }
    final result = target == 'wechat'
        ? await service.launchWechat()
        : await service.launchQQ();
    if (!mounted) return;
    ToastUtils.toast(result == WalletLaunchAppResult.success
        ? TIM_t('邀请链接已复制，请粘贴发送给好友')
        : TIM_t('邀请链接已复制，未能打开应用，请手动粘贴分享'));
  }

  Widget _buildShareActions(_QrPagePalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: palette.cardBg.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(20)),
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(14) > 20 ? 2 : 4;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final targets = [
          (
            'wechat',
            '分享微信',
            'assets/images/vx .png',
            Icons.chat_bubble_outline
          ),
          ('qq', '分享QQ', 'assets/images/qq.png', Icons.chat_bubble_outline),
          ('copy', '复制链接', '', Icons.link_rounded),
          ('more', '更多分享', '', Icons.more_horiz_rounded),
        ];
        return Wrap(
            spacing: spacing,
            runSpacing: 8,
            children: targets
                .map((item) => SizedBox(
                      width: width,
                      child: Material(
                          color: palette.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _shareInvitation(item.$1),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 9),
                                child: Column(children: [
                                  if (item.$3.isNotEmpty)
                                    Image.asset(item.$3,
                                        width: 28,
                                        height: 28,
                                        excludeFromSemantics: true)
                                  else
                                    Icon(item.$4,
                                        color: palette.primary, size: 28),
                                  const SizedBox(height: 9),
                                  Text(TIM_t(item.$2),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: palette.title, fontSize: 12)),
                                ])),
                          )),
                    ))
                .toList());
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeModel = Provider.of<DefaultThemeData>(context);
    final theme = themeModel.theme;
    final palette = _QrPagePalette.resolve(themeModel);
    final qrData = _buildQrData();
    final loadingQrOptions = !_qrPayloadReady;
    final showQrCode = _canShowGroupQr && _landingUrlResolved;

    Widget buildScaffold() => Scaffold(
          extendBodyBehindAppBar: !widget.embedded,
          backgroundColor: palette.pageBgTop,
          appBar: widget.embedded
              ? null
              : AppBar(
                  centerTitle: true,
                  leading: Navigator.of(context).canPop()
                      ? AppBackButton(color: palette.primary)
                      : null,
                  title: Text(
                    widget.title,
                    style: TextStyle(
                      color: palette.title,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: IconThemeData(color: palette.primary),
                  actions: [
                    if (showQrCode)
                      SizedBox(
                        width: kToolbarHeight,
                        height: kToolbarHeight,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _showQrActionSheet(theme),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: palette.primary,
                            size: 26,
                          ),
                        ),
                      ),
                  ],
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/ivnbg.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  excludeFromSemantics: true,
                  color: themeModel.currentThemeType == ThemeType.dark
                      ? const Color(0x99000000)
                      : null,
                  colorBlendMode: BlendMode.darken,
                ),
              ),
              Column(
                children: [
                  if (!widget.embedded)
                    SizedBox(
                        height:
                            MediaQuery.paddingOf(context).top + kToolbarHeight),
                  Expanded(
                    child: SafeArea(
                      top: widget.embedded,
                      bottom: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final card = RepaintBoundary(
                            key: _captureKey,
                            child: LayoutBuilder(
                              builder: (context, innerConstraints) {
                                final fallbackWidth =
                                    MediaQuery.sizeOf(context).width - 64;
                                final maxWidth =
                                    innerConstraints.maxWidth.isFinite
                                        ? innerConstraints.maxWidth
                                        : fallbackWidth;
                                return _buildShareCard(
                                  qrData: qrData,
                                  maxWidth: maxWidth,
                                  showQrCode: showQrCode,
                                  loadingQrOptions: loadingQrOptions,
                                  palette: palette,
                                );
                              },
                            ),
                          );
                          final padding = EdgeInsets.fromLTRB(
                            widget.embedded ? 16 : 20,
                            widget.embedded ? 8 : 12,
                            widget.embedded ? 16 : 20,
                            widget.embedded ? 4 : 12,
                          );
                          // Fit the complete composition into the available viewport.
                          // A fixed child width lets text wrap before height scaling.
                          final contentWidth =
                              (constraints.maxWidth - padding.horizontal)
                                  .clamp(1.0, 420.0)
                                  .toDouble();
                          if (widget.embedded) {
                            return Padding(
                              padding: padding,
                              child: Center(
                                  child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child:
                                    SizedBox(width: contentWidth, child: card),
                              )),
                            );
                          }
                          return Padding(
                            padding: padding.copyWith(
                                bottom:
                                    MediaQuery.paddingOf(context).bottom + 8),
                            child: Center(
                                child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: contentWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          4, 10, 4, 20),
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  widget.isChannel
                                                      ? AppI18n.of(context).t(
                                                          zhHans: '邀请好友订阅频道',
                                                          zhHant: '邀請好友訂閱頻道',
                                                          en: 'Invite friends to subscribe',
                                                          ja: '友だちをチャンネルに招待',
                                                          ko: '친구를 채널 구독에 초대',
                                                        )
                                                      : TIM_t(_isGroupQr
                                                          ? '邀请好友加入群聊'
                                                          : '扫一扫，添加我为好友'),
                                                  style: TextStyle(
                                                      color: palette.title,
                                                      fontSize: 23,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              const SizedBox(height: 7),
                                              Text(
                                                  TIM_t('一起交流 · 分享精彩 · 连接更多朋友'),
                                                  style: TextStyle(
                                                      color: palette.secondary,
                                                      fontSize: 14,
                                                      height: 1.5)),
                                            ],
                                          )),
                                    ),
                                    card,
                                    if (showQrCode && !widget.embedded) ...[
                                      const SizedBox(height: 14),
                                      _buildShareActions(palette),
                                      const SizedBox(height: 12),
                                      _buildBottomActions(palette),
                                    ],
                                  ],
                                ),
                              ),
                            )),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    if (!widget.embedded) {
      return buildScaffold();
    }
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => buildScaffold(),
        );
      },
    );
  }
}

class _QrPagePalette {
  const _QrPagePalette({
    required this.isDark,
    required this.primary,
    required this.pageBgTop,
    required this.pageBgBottom,
    required this.cardBg,
    required this.cardBorder,
    required this.cardShadow,
    required this.title,
    required this.name,
    required this.secondary,
    required this.brandText,
    required this.dotGrid,
    required this.outlineButtonBg,
    required this.disabledBg,
    required this.disabledIcon,
    required this.qrFrameBg,
    required this.badgeBorder,
  });

  final bool isDark;
  final Color primary;
  final Color pageBgTop;
  final Color pageBgBottom;
  final Color cardBg;
  final Color cardBorder;
  final Color cardShadow;
  final Color title;
  final Color name;
  final Color secondary;
  final Color brandText;
  final Color dotGrid;
  final Color outlineButtonBg;
  final Color disabledBg;
  final Color disabledIcon;
  final Color qrFrameBg;
  final Color badgeBorder;

  factory _QrPagePalette.resolve(DefaultThemeData themeModel) {
    final isDark = themeModel.currentThemeType == ThemeType.dark;
    final primary = themeModel.theme.primaryColor ?? AppColors.primaryBlue;

    if (isDark) {
      return _QrPagePalette(
        isDark: true,
        primary: primary,
        pageBgTop: const Color(0xFF122033),
        pageBgBottom: AppColors.background(dark: true),
        cardBg: AppColors.card(dark: true),
        cardBorder: primary.withValues(alpha: 0.32),
        cardShadow: Colors.black.withValues(alpha: 0.35),
        title: AppColors.text(dark: true),
        name: AppColors.text(dark: true),
        secondary: AppColors.subText(dark: true),
        brandText: AppColors.text(dark: true),
        dotGrid: const Color(0xFF4A5568),
        outlineButtonBg: AppColors.card(dark: true),
        disabledBg: AppColors.surfaceAlt(dark: true),
        disabledIcon: AppColors.subText(dark: true),
        qrFrameBg: Colors.white,
        badgeBorder: AppColors.card(dark: true),
      );
    }

    return _QrPagePalette(
      isDark: false,
      primary: primary,
      pageBgTop: const Color(0xFFD6EBFF),
      pageBgBottom: const Color(0xFFEEF6FF),
      cardBg: Colors.white,
      cardBorder: const Color(0xFFB5D8FF),
      cardShadow: primary.withValues(alpha: 0.12),
      title: const Color(0xFF1A2332),
      name: const Color(0xFF24272B),
      secondary: const Color(0xFF9AA0A8),
      brandText: const Color(0xFF303236),
      dotGrid: const Color(0xFFD0D5DC),
      outlineButtonBg: Colors.white,
      disabledBg: const Color(0xFFF5F8FC),
      disabledIcon: const Color(0xFFBCC0C8),
      qrFrameBg: Colors.white,
      badgeBorder: Colors.white,
    );
  }
}

class _ShareTarget {
  final String userID;
  final String groupID;

  const _ShareTarget({
    this.userID = "",
    this.groupID = "",
  });
}

class _QrCornerFramePainter extends CustomPainter {
  const _QrCornerFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const inset = 6.0;
    final length = size.shortestSide * 0.16;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;

    final radius = (length * .4).clamp(0.0, 12.0);
    final corners = Path()
      ..moveTo(left, top + length)
      ..lineTo(left, top + radius)
      ..arcToPoint(Offset(left + radius, top), radius: Radius.circular(radius))
      ..lineTo(left + length, top)
      ..moveTo(right - length, top)
      ..lineTo(right - radius, top)
      ..arcToPoint(Offset(right, top + radius), radius: Radius.circular(radius))
      ..lineTo(right, top + length)
      ..moveTo(right, bottom - length)
      ..lineTo(right, bottom - radius)
      ..arcToPoint(Offset(right - radius, bottom),
          radius: Radius.circular(radius))
      ..lineTo(right - length, bottom)
      ..moveTo(left + length, bottom)
      ..lineTo(left + radius, bottom)
      ..arcToPoint(Offset(left, bottom - radius),
          radius: Radius.circular(radius))
      ..lineTo(left, bottom - length);
    canvas.drawPath(corners, paint);
  }

  @override
  bool shouldRepaint(covariant _QrCornerFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.55);
    const spacing = 7.0;
    const radius = 1.1;
    for (var y = radius; y < size.height; y += spacing) {
      for (var x = radius; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CardWavePainter extends CustomPainter {
  const _CardWavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.09),
        ],
      ).createShader(Offset.zero & size);

    final path = Path()
      ..moveTo(0, size.height * 0.42)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.12,
        size.width * 0.42,
        size.height * 0.72,
        size.width * 0.62,
        size.height * 0.38,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.12,
        size.width * 0.9,
        size.height * 0.55,
        size.width,
        size.height * 0.28,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CardWavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
