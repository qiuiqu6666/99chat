import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/contact_card_message.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// Displays the shared confirmation card used before sending a contact card.
Future<bool> showContactCardSendConfirm({
  required BuildContext context,
  required TUITheme theme,
  required ContactCardMessage card,
  required String conversationName,
  required String conversationFaceUrl,
}) async {
  final i18n = AppI18n.of(context);
  final targetName =
      card.nickName.trim().isNotEmpty ? card.nickName.trim() : card.userID;
  final convName = conversationName.trim().isNotEmpty
      ? conversationName.trim()
      : (i18n.t(
          zhHans: '该会话',
          zhHant: '該會話',
          en: 'this chat',
          ja: 'このチャット',
          ko: '이 대화',
        ));
  final cardFaceUrl = UserAvatarHelper.pickBest(imFaceUrl: card.faceUrl);
  final isDark =
      (theme.weakBackgroundColor ?? Colors.white).computeLuminance() < 0.5;
  final titleColor = isDark ? Colors.white : const Color(0xFF111111);
  final subColor = isDark ? Colors.white60 : const Color(0xFF999999);
  final cardColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
  final cancelBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F1F5);
  final primary = theme.primaryColor ?? const Color(0xFF2196F3);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final mq = MediaQuery.of(dialogContext);
      final screenWidth = mq.size.width;
      final screenHeight = mq.size.height;
      final horizontalInset = (screenWidth * 0.1).clamp(20.0, 48.0);
      final maxWidth = (screenWidth - horizontalInset * 2).clamp(
        260.0,
        300.0,
      );
      const contentPadding = EdgeInsets.fromLTRB(16, 16, 16, 14);
      final avatarSize = ((maxWidth - 56) / 2).clamp(36.0, 46.0);
      final arrowSize = (avatarSize * 0.5).clamp(18.0, 24.0);
      final avatarGap = (maxWidth * 0.04).clamp(6.0, 12.0);
      const buttonHeight = 38.0;
      const buttonGap = 10.0;

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: screenHeight * 0.85,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Container(
                padding: contentPadding,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      i18n.t(
                        zhHans: '发送名片',
                        zhHant: '傳送名片',
                        en: 'Send Contact Card',
                        ja: '名刺を送信',
                        ko: '명함 보내기',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      i18n.t(
                        zhHans: '推荐$targetName给$convName',
                        zhHant: '推薦$targetName給$convName',
                        en: 'Recommend $targetName to $convName',
                        ja: '$targetNameを$convNameにおすすめします',
                        ko: '$targetName님을 $convName에게 추천',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppUserAvatar(
                            faceUrl: cardFaceUrl,
                            showName: targetName,
                            size: avatarSize,
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: avatarGap,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: arrowSize,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          AppUserAvatar(
                            faceUrl: conversationFaceUrl,
                            showName: convName,
                            size: avatarSize,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: buttonHeight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: cancelBg,
                                foregroundColor: titleColor,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: Text(
                                i18n.t(
                                  zhHans: '取消',
                                  zhHant: '取消',
                                  en: 'Cancel',
                                  ja: 'キャンセル',
                                  ko: '취소',
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: buttonGap),
                        Expanded(
                          child: SizedBox(
                            height: buttonHeight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(
                                i18n.t(
                                  zhHans: '确定',
                                  zhHant: '確定',
                                  en: 'OK',
                                  ja: '確認',
                                  ko: '확인',
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}
