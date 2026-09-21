import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/chat_cards/chat_wallet_card_metrics.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/official_account_name_label.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/contact_card_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// 个人名片卡片配色：结构与转账/红包卡片一致，使用蓝色系区分。
abstract final class _ContactCardColors {
  static const Color body = Color(0xFF5B8DEF);
  static const Color footer = Color(0xFF4A7AD4);
  static const Color title = Color(0xFFF7FAFF);
  static const Color subtitle = Color(0xFFDCE8FF);
  static const Color footerText = Color(0xFFC8DAFF);
}

class ContactCardMessageItem extends StatelessWidget {
  final ContactCardMessage message;
  final TUITheme theme;
  final bool isSelf;
  final String timeText;
  final String? groupId;

  const ContactCardMessageItem({
    super.key,
    required this.message,
    required this.theme,
    required this.isSelf,
    this.timeText = '--:--',
    this.groupId,
  });

  String get _displayName {
    final nickName = message.nickName.trim();
    if (nickName.isNotEmpty) {
      return nickName;
    }
    return message.userID;
  }

  String get _subtitle {
    final signature = message.selfSignature.trim();
    if (signature.isNotEmpty) {
      return signature;
    }
    final userId = message.userID.trim();
    if (userId.isNotEmpty && userId != _displayName) {
      return userId;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final scale = TUIKitScreenUtils.compactChatCardScale(context);
    double w(num value) => ChatWalletCardMetrics.w(value);
    double h(num value) => ChatWalletCardMetrics.h(value) * scale;
    double r(num value) => ChatWalletCardMetrics.r(value);
    final bodyPad = ChatWalletCardMetrics.bodyPadding;
    final footerPad = ChatWalletCardMetrics.footerPadding;
    final compactBodyPad = EdgeInsets.fromLTRB(
      bodyPad.left,
      bodyPad.top * scale,
      bodyPad.right,
      bodyPad.bottom * scale,
    );
    final compactFooterPad = EdgeInsets.fromLTRB(
      footerPad.left,
      footerPad.top * scale,
      footerPad.right,
      footerPad.bottom * scale,
    );
    final borderRadius = BorderRadius.circular(r(14));
    final canTap = message.userID.isNotEmpty;
    final footerLabel = i18n.t(
      zhHans: '个人名片',
      zhHant: '個人名片',
      en: 'Contact card',
      ja: '名刺',
      ko: '명함',
    );
    final subtitle = _subtitle;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = ChatWalletCardMetrics.clampCardWidth(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ChatWalletCardMetrics.maxWidth,
        );
        final tailOverhang = w(9);
        return SizedBox(
          width: cardWidth,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (!isSelf)
                Positioned(
                  left: 0,
                  top: h(22),
                  child: Transform.flip(
                    flipX: true,
                    child: CustomPaint(
                      size: Size(w(14), h(24)),
                      painter: _ContactCardTailPainter(),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  left: isSelf ? 0 : tailOverhang,
                  right: isSelf ? tailOverhang : 0,
                ),
                child: InkWell(
                  onTap: canTap
                      ? () {
                          if (serviceLocator<TUIChatGlobalModel>()
                              .isMessageContextMenuOverlayOpen) {
                            return;
                          }
                          openContactCardUserPage(
                            context,
                            message,
                            groupId: groupId,
                          );
                        }
                      : null,
                  borderRadius: borderRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _ContactCardColors.body,
                      borderRadius: borderRadius,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                ChatWalletCardMetrics.minBodyHeight * scale,
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: compactBodyPad,
                              child: Row(
                                crossAxisAlignment:
                                    ChatWalletCardMetrics.useDesktopChatCard
                                        ? CrossAxisAlignment.center
                                        : CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: ChatWalletCardMetrics
                                            .useDesktopChatCard
                                        ? EdgeInsets.zero
                                        : EdgeInsets.only(top: h(2)),
                                    child: AppUserAvatar(
                                      faceUrl: message.faceUrl,
                                      showName: _displayName,
                                      size: ChatWalletCardMetrics.iconSize() *
                                          scale,
                                    ),
                                  ),
                                  SizedBox(
                                    width: ChatWalletCardMetrics.leadingTextGap,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OfficialAccountNameLabelForUser(
                                          userId: message.userID,
                                          name: _displayName,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: _ContactCardColors.title,
                                            fontSize: ChatWalletCardMetrics
                                                    .titleFontSize(mobile: 15) *
                                                scale,
                                            fontWeight: FontWeight.w500,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          SizedBox(
                                            height: ChatWalletCardMetrics
                                                    .lineGap(
                                              mobile: ChatWalletCardMetrics.h(10),
                                            ) *
                                                scale,
                                          ),
                                          Text(
                                            subtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _ContactCardColors.subtitle,
                                              fontSize: ChatWalletCardMetrics
                                                      .subtitleFontSize(
                                                    mobile: ChatWalletCardMetrics
                                                        .sp(22),
                                                  ) *
                                                  scale,
                                              fontWeight: FontWeight.w500,
                                              height: 1.25,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: compactFooterPad,
                          decoration: BoxDecoration(
                            color: _ContactCardColors.footer,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(r(14)),
                              bottomRight: Radius.circular(r(14)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  footerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _ContactCardColors.footerText,
                                    fontSize:
                                        ChatWalletCardMetrics.footerSp(18) *
                                            scale,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                timeText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _ContactCardColors.footerText,
                                  fontSize:
                                      ChatWalletCardMetrics.footerSp(18) *
                                          scale,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isSelf)
                Positioned(
                  right: 0,
                  top: h(22),
                  child: CustomPaint(
                    size: Size(w(14), h(24)),
                    painter: _ContactCardTailPainter(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ContactCardTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _ContactCardColors.body;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.14,
        size.width * 0.92,
        size.height * 0.46,
      )
      ..quadraticBezierTo(
        size.width * 0.96,
        size.height * 0.78,
        0,
        size.height,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
