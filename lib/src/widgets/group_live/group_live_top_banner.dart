import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/overflow_text_marquee.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';

bool _isDarkTheme(BuildContext context) {
  final appTheme = Provider.of<DefaultThemeData?>(context);
  return appTheme == null
      ? Theme.of(context).brightness == Brightness.dark
      : appTheme.materialThemeMode == ThemeMode.dark;
}

/// Compact banner above the message list when a group has an active live slot.
class GroupLiveTopBanner extends StatelessWidget {
  const GroupLiveTopBanner({
    super.key,
    required this.session,
    required this.onTap,
    this.isDesignatedAnchor = false,
    this.anchorFaceUrl = '',
  });

  final GroupLiveSession session;
  final VoidCallback onTap;
  final bool isDesignatedAnchor;
  final String anchorFaceUrl;

  static const Color _cardBg = Colors.white;
  static const Color _titleInk = Color(0xFF1F2329);
  static const Color _subtitleInk = Color(0xFF8A8F99);
  static const double _cardHeight = 56;
  static const double _ipSize = 72;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final dark = _isDarkTheme(context);
    final title = session.roomName.trim().isNotEmpty
        ? session.roomName.trim()
        : i18n.t(
            zhHans: '群直播',
            zhHant: '群直播',
            en: 'Group Live',
            ja: 'グループ配信',
            ko: '그룹 라이브',
          );
    final subtitle = session.description.trim();
    final action = i18n.t(
      zhHans: '进入直播间',
      zhHant: '進入直播間',
      en: 'Enter room',
      ja: '配信室へ',
      ko: '라이브 입장',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Material(
        color: dark ? AppColors.surfaceAlt(dark: true) : _cardBg,
        elevation: 0,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.none,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: _cardHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: _ipSize,
                    height: _cardHeight,
                    child: OverflowBox(
                      maxWidth: _ipSize,
                      maxHeight: _ipSize,
                      child: Image.asset(
                        'assets/live/liveee.webp',
                        width: _ipSize,
                        height: _ipSize,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dark ? AppColors.darkText : _titleInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          OverflowTextMarquee(
                            text: subtitle,
                            height: 15,
                            style: TextStyle(
                              color: dark ? AppColors.darkSubText : _subtitleInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AnchorLiveAvatar(
                    userId: session.anchorUserId,
                    groupId: session.groupId,
                    initialFaceUrl: anchorFaceUrl,
                  ),
                  const SizedBox(width: 8),
                  _EnterLiveButton(label: action),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchorLiveAvatar extends StatefulWidget {
  const _AnchorLiveAvatar({
    required this.userId,
    required this.groupId,
    this.initialFaceUrl = '',
  });

  final String userId;
  final String groupId;
  final String initialFaceUrl;

  @override
  State<_AnchorLiveAvatar> createState() => _AnchorLiveAvatarState();
}

class _AnchorLiveAvatarState extends State<_AnchorLiveAvatar> {
  static const double _avatarSize = 40;
  static const double _liveDotSize = 10;

  late String _faceUrl;
  late String _normalizedUserId;
  late String _normalizedGroupId;

  @override
  void initState() {
    super.initState();
    _normalizedUserId = ChatIdFormat.rawUserUid(widget.userId);
    _normalizedGroupId = ChatIdFormat.normalizeGroupId(widget.groupId);
    _faceUrl = _resolveFaceFromLocalHints();
    GroupMemberStore.instance.addListener(_onMemberStoreChanged);
    if (_needsNetworkResolve(_faceUrl)) {
      unawaited(_resolveFaceUrl());
    }
  }

  @override
  void didUpdateWidget(covariant _AnchorLiveAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUserId = ChatIdFormat.rawUserUid(widget.userId);
    final nextGroupId = ChatIdFormat.normalizeGroupId(widget.groupId);
    final userChanged = nextUserId != _normalizedUserId;
    final groupChanged = nextGroupId != _normalizedGroupId;
    final hintChanged = oldWidget.initialFaceUrl != widget.initialFaceUrl;
    if (!userChanged && !groupChanged && !hintChanged) {
      return;
    }
    _normalizedUserId = nextUserId;
    _normalizedGroupId = nextGroupId;
    final nextFace = _resolveFaceFromLocalHints();
    if (nextFace != _faceUrl) {
      setState(() => _faceUrl = nextFace);
    }
    if (_needsNetworkResolve(_faceUrl)) {
      unawaited(_resolveFaceUrl());
    }
  }

  @override
  void dispose() {
    GroupMemberStore.instance.removeListener(_onMemberStoreChanged);
    super.dispose();
  }

  String _resolveFaceFromLocalHints() {
    final fromHint =
        UserAvatarHelper.usableAvatarOrEmpty(widget.initialFaceUrl);
    if (fromHint.isNotEmpty) {
      return fromHint;
    }
    return UserAvatarHelper.groupMemberFaceUrl(
      _normalizedGroupId,
      _normalizedUserId,
    );
  }

  bool _needsNetworkResolve(String faceUrl) {
    return UserAvatarHelper.usableAvatarOrEmpty(faceUrl).isEmpty &&
        _normalizedUserId.isNotEmpty;
  }

  void _onMemberStoreChanged() {
    final memberFace = UserAvatarHelper.groupMemberFaceUrl(
      _normalizedGroupId,
      _normalizedUserId,
    );
    if (memberFace.isEmpty || memberFace == _faceUrl) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _faceUrl = memberFace);
  }

  Future<void> _resolveFaceUrl() async {
    final id = _normalizedUserId;
    if (id.isEmpty) {
      return;
    }
    final resolved = await UserAvatarHelper.resolveChatPeerFaceUrl(
      peerUserId: id,
      messageFaceUrl: widget.initialFaceUrl,
      groupId: _normalizedGroupId,
    );
    final usable = UserAvatarHelper.usableAvatarOrEmpty(resolved);
    if (usable.isEmpty || !mounted || _normalizedUserId != id) {
      return;
    }
    if (usable == _faceUrl) {
      return;
    }
    setState(() => _faceUrl = usable);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatarSize,
      height: _avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFD6E4),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: AppUserAvatar(
                faceUrl: _faceUrl,
                showName: _normalizedUserId,
                size: _avatarSize - 3,
                type: 1,
                preferRasterPlaceholder: true,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 2,
            child: Container(
              width: _liveDotSize,
              height: _liveDotSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF6B9D), Color(0xFFFFB35C)],
                ),
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnterLiveButton extends StatelessWidget {
  const _EnterLiveButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFFF9A2F),
            Color(0xFFFF6358),
            Color(0xFFFF3F78),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40FF6358),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.05,
            ),
          ),
          const SizedBox(width: 3),
          const CustomPaint(
            size: Size(7, 11),
            painter: _EnterChevronPainter(),
          ),
        ],
      ),
    );
  }
}

class _EnterChevronPainter extends CustomPainter {
  const _EnterChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1.2, 1.2)
      ..lineTo(size.width - 1.2, size.height / 2)
      ..lineTo(1.2, size.height - 1.2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
