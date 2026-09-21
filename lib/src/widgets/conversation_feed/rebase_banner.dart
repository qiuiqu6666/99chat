import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_rebase_policy.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

/// E3：列表顶部 Rebase banner。
///
/// "本端离线期间出现 X 条消息已跳过，点击可前往聊天查看"。
///
/// 30s TTL 后自动消失，避免长期打扰。
/// 点 banner 暂时只 dismiss；后续可扩展为"跳转到聊天页"。
class RebaseBanner extends StatelessWidget {
  const RebaseBanner({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDismiss,
  });

  final RebaseBannerEntry entry;
  final VoidCallback onTap;

  /// 用户主动关闭（点 ×）；banner 立刻消失，本会话本轮不再重复出现。
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppColors.primaryBlue.withValues(alpha: dark ? 0.18 : 0.10);
    final fg = AppColors.primaryBlue;
    final i18n = AppI18n.of(context);
    final skipped = entry.skipped;
    final text = i18n.t(
      zhHans: '本端离线期间累计 $skipped 条消息已跳过，点击可前往查看',
      zhHant: '本端離線期間累計 $skipped 條訊息已跳過，點擊可前往查看',
      en:
          '$skipped messages were skipped while offline. Tap to view the conversation.',
      ja: 'オフライン中 $skipped 件のメッセージをスキップしました。会話を表示するにはタップしてください。',
      ko: '오프라인 중 $skipped개의 메시지를 건너뛰었습니다. 대화를 보려면 탭하세요.',
    );

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        bottom: false,
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: fg.withValues(alpha: 0.25),
                width: 0.6,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.history_toggle_off_rounded, size: 18, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, size: 18, color: fg),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// E3：聚合展示 — 监听 [ConversationRebasePolicy] 暴露的 banner 版本号，
/// 任意 banner 集合变化时重 build。
class RebaseBannersList extends StatelessWidget {
  const RebaseBannersList({
    super.key,
    required this.onTapConversation,
  });

  /// 用户点 banner 时回调，传 conversationId 让上层导航进 chat 页。
  final void Function(String conversationId) onTapConversation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ConversationRebasePolicy.instance.bannersVersion,
      builder: (context, _, __) {
        final banners = ConversationRebasePolicy.instance.activeBanners();
        if (banners.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in banners)
              RebaseBanner(
                key: ValueKey(entry.conversationId),
                entry: entry,
                onTap: () => onTapConversation(entry.conversationId),
                onDismiss: () => ConversationRebasePolicy.instance
                    .dismissBanner(entry.conversationId),
              ),
          ],
        );
      },
    );
  }
}
