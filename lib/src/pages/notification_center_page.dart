import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/all_group_application_list.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/newContact.dart';
import 'package:tencent_cloud_chat_demo/src/pages/moments/moments_notifications_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/payment_notification_center_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/notification_settings_page.dart';
import 'package:tencent_cloud_chat_demo/src/models/moments/moment_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  int _momentsUnread = 0;
  String? _momentsPreview;
  String? _paymentPreview;
  int _paymentUnread = 0;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final moments = await MomentsStore.loadNotificationsPage();
      if (!mounted) return;
      setState(() {
        _momentsUnread = moments.unreadCount;
        final item = moments.items.isEmpty ? null : moments.items.first;
        _momentsPreview = item == null
            ? null
            : '${item.actor.name} · ${AppI18n.of(context).t(zhHans: item.type == MomentNotificationType.like ? '赞了你的动态' : '与你互动了', zhHant: item.type == MomentNotificationType.like ? '讚了你的動態' : '與你互動了', en: item.type == MomentNotificationType.like ? 'liked your post' : 'interacted with you', ja: item.type == MomentNotificationType.like ? 'いいねしました' : '交流しました', ko: item.type == MomentNotificationType.like ? '좋아요를 눌렀습니다' : '소통했습니다')}';
      });
    } catch (_) {}
    final paymentId = PlatformOfficialAccountService.walletNoticeAccountId;
    final identity = SessionIdentityService.instance.capture();
    final payment = paymentId.isEmpty
        ? null
        : await TencentConversationReadService.conversationSnapshot(
            conversationID: 'c2c_$paymentId',
            capturedIdentity: identity,
          );
    if (!mounted) return;
    setState(() {
      _paymentUnread = payment?.unreadCount ?? 0;
      final last = payment?.lastMessage;
      final text = last?.textElem?.text?.trim();
      _paymentPreview = text?.isNotEmpty == true
          ? text
          : last == null
              ? null
              : AppI18n.of(context).t(
                  zhHans: '收到支付助手消息',
                  zhHant: '收到支付助手訊息',
                  en: 'New Payment Assistant message',
                  ja: '支払いアシスタントからのメッセージ',
                  ko: '결제 도우미 메시지',
                );
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, AppMaterialPageRoute(builder: (_) => page));
    if (mounted) unawaited(_refresh());
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    try {
      await Future.wait([
        FriendRequestNoticeService.instance.commitObservedAsRead(),
        GroupNoticeUnreadService.instance.markRead(),
        MomentsStore.markNotificationsRead(readAll: true),
      ]);
      final paymentId = PlatformOfficialAccountService.walletNoticeAccountId;
      if (paymentId.isNotEmpty) {
        final result = await TencentConversationReadService.markRead(
          messageService: serviceLocator<MessageService>(),
          conversationID: 'c2c_$paymentId',
          isGroup: false,
          capturedIdentity: SessionIdentityService.instance.capture(),
          explicitFullConversationClear: true,
        );
        if (result.code != 0) {
          throw StateError('payment_notification_mark_read_failed');
        }
      }
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppI18n.of(context).t(
            zhHans: '部分通知未能标记已读，请重试',
            zhHant: '部分通知未能標記已讀，請重試',
            en: 'Some notifications could not be marked as read',
            ja: '一部の通知を既読にできませんでした',
            ko: '일부 알림을 읽음 처리하지 못했습니다',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.subText(dark: dark);
    final foreground = AppColors.text(dark: dark);
    final background = AppColors.background(dark: dark);
    final noNotice = i18n.t(
        zhHans: '暂无通知',
        zhHant: '暫無通知',
        en: 'No notifications',
        ja: '通知はありません',
        ko: '알림 없음');
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: const AppBackButton(),
        centerTitle: true,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          i18n.t(
              zhHans: '通知中心',
              zhHant: '通知中心',
              en: 'Notification Center',
              ja: '通知センター',
              ko: '알림 센터'),
          style: TextStyle(
              color: foreground, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _markingAllRead ? null : _markAllRead,
            child: Text(
              i18n.t(
                  zhHans: '全部已读',
                  zhHant: '全部已讀',
                  en: 'Mark all read',
                  ja: 'すべて既読',
                  ko: '모두 읽음'),
              style: const TextStyle(color: AppTokens.accent, fontSize: 14),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable:
                  FriendRequestNoticeService.instance.pendingApplicationCount,
              builder: (context, count, _) => _CenterRow(
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFFFFA337),
                title: i18n.t(
                    zhHans: '好友通知',
                    zhHant: '好友通知',
                    en: 'Friend notifications',
                    ja: '友達通知',
                    ko: '친구 알림'),
                subtitle: count > 0
                    ? i18n.format(
                        zhHans: '{count}条新申请',
                        zhHant: '{count}則新申請',
                        en: '{count} new requests',
                        ja: '新しい申請 {count} 件',
                        ko: '새 요청 {count}건',
                        vars: {'count': '$count'})
                    : noNotice,
                count: count,
                foreground: foreground,
                muted: muted,
                onTap: () async {
                  await FriendRequestNoticeService.instance
                      .commitObservedAsRead();
                  if (context.mounted) await _open(const NewContact());
                },
              ),
            ),
            AnimatedBuilder(
              animation: GroupNoticeUnreadService.instance,
              builder: (context, _) {
                final count = GroupNoticeUnreadService.instance.unreadCount;
                return _CenterRow(
                  icon: Icons.campaign_rounded,
                  color: const Color(0xFF2389F5),
                  title: i18n.t(
                      zhHans: '群通知',
                      zhHant: '群組通知',
                      en: 'Group notifications',
                      ja: 'グループ通知',
                      ko: '그룹 알림'),
                  subtitle: count > 0
                      ? i18n.format(
                          zhHans: '{count}条未读通知',
                          zhHant: '{count}則未讀通知',
                          en: '{count} unread',
                          ja: '未読 {count} 件',
                          ko: '읽지 않은 알림 {count}건',
                          vars: {'count': '$count'})
                      : noNotice,
                  count: count,
                  foreground: foreground,
                  muted: muted,
                  onTap: () => _open(const AllGroupApplicationListPage()),
                );
              },
            ),
            _CenterRow(
              icon: Icons.notifications_active_outlined,
              color: const Color(0xFF8271E8),
              title: i18n.t(
                  zhHans: '动态通知',
                  zhHant: '動態通知',
                  en: 'Moments',
                  ja: 'モーメント通知',
                  ko: '모멘트 알림'),
              subtitle: _momentsPreview ?? noNotice,
              count: _momentsUnread,
              foreground: foreground,
              muted: muted,
              onTap: () => _open(const MomentsNotificationsPage()),
            ),
            _CenterRow(
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF27B997),
              title: i18n.t(
                  zhHans: '支付通知',
                  zhHant: '支付通知',
                  en: 'Payment notifications',
                  ja: '支払い通知',
                  ko: '결제 알림'),
              subtitle: _paymentPreview?.isNotEmpty == true
                  ? _paymentPreview!
                  : noNotice,
              count: _paymentUnread,
              foreground: foreground,
              muted: muted,
              onTap: () => _open(const PaymentNotificationCenterPage()),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: TextButton.icon(
                onPressed: () => _open(const NotificationSettingsPage()),
                icon: const Icon(Icons.settings_outlined),
                label: Text(i18n.t(
                    zhHans: '通知设置',
                    zhHant: '通知設定',
                    en: 'Notification settings',
                    ja: '通知設定',
                    ko: '알림 설정')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterRow extends StatelessWidget {
  const _CenterRow(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle,
      required this.foreground,
      required this.muted,
      required this.onTap,
      this.count = 0});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Color foreground;
  final Color muted;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          AppColors.card(dark: Theme.of(context).brightness == Brightness.dark),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: muted.withValues(alpha: 0.13)))),
          child: Row(
            children: [
              Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(
                    radius: 25,
                    backgroundColor: color,
                    child: Icon(icon, color: Colors.white, size: 25)),
                if (count > 0)
                  Positioned(
                      right: -6,
                      top: -5,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFF4D5D),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10)))),
              ]),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13)),
                  ])),
              Icon(Icons.chevron_right_rounded, color: muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
