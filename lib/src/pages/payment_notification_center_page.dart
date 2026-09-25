import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_pending_filters.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_pending_list_screen.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_pending_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_screen.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

class PaymentNotificationCenterPage extends StatefulWidget {
  const PaymentNotificationCenterPage({super.key});

  @override
  State<PaymentNotificationCenterPage> createState() =>
      _PaymentNotificationCenterPageState();
}

class _PaymentNotificationCenterPageState
    extends State<PaymentNotificationCenterPage> {
  final WalletRecordController _records = WalletRecordController();
  String? _latestAssetText;
  String? _latestAssetTime;
  String? _latestTransferText;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _records.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _records.load();
    final pending = await WalletPendingStore().load();
    if (!mounted) return;
    final latest = _records.list.isEmpty ? null : _records.list.first;
    final transferRecords = _records.list.where((record) =>
        record.type == WalletRecordType.transfer ||
        record.type == WalletRecordType.redPacket);
    final latestTransfer =
        transferRecords.isEmpty ? null : transferRecords.first;
    setState(() {
      _latestAssetText = latest == null
          ? null
          : latest.subTitle.trim().isNotEmpty
              ? latest.subTitle.trim()
              : latest.title.trim();
      final date = DateTime.tryParse(latest?.createdAt ?? '');
      _latestAssetTime = date == null
          ? null
          : '${date.toLocal().year}-${date.toLocal().month.toString().padLeft(2, '0')}-${date.toLocal().day.toString().padLeft(2, '0')} '
              '${date.toLocal().hour.toString().padLeft(2, '0')}:${date.toLocal().minute.toString().padLeft(2, '0')}';
      _pendingCount = pending.where(walletPendingItemNeedsAttention).length;
      _latestTransferText = latestTransfer == null
          ? null
          : latestTransfer.subTitle.trim().isNotEmpty
              ? latestTransfer.subTitle.trim()
              : latestTransfer.title.trim();
    });
  }

  void _open(Widget page) {
    Navigator.push(context, AppMaterialPageRoute(builder: (_) => page));
  }

  void _openPaymentAssistant() {
    final accountId = PlatformOfficialAccountService.walletNoticeAccountId;
    if (accountId.isEmpty) return;
    unawaited(openOrReuseAppChat(
      context,
      PlatformOfficialAccountService.buildConversation(userId: accountId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = AppColors.text(dark: dark);
    final muted = AppColors.subText(dark: dark);
    final background = AppColors.background(dark: dark);
    final noData = i18n.t(
        zhHans: '暂无数据',
        zhHant: '暫無資料',
        en: 'No data',
        ja: 'データなし',
        ko: '데이터 없음');

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const AppBackButton(),
        centerTitle: true,
        title: Text(
          i18n.t(
              zhHans: '支付通知',
              zhHant: '支付通知',
              en: 'Payment notifications',
              ja: '支払い通知',
              ko: '결제 알림'),
          style: TextStyle(
              color: foreground, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 8),
            _PaymentNoticeRow(
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF4E72E5),
              title: i18n.t(
                  zhHans: '支付助手消息',
                  zhHant: '支付助手訊息',
                  en: 'Payment Assistant',
                  ja: '支払いアシスタント',
                  ko: '결제 도우미'),
              subtitle: i18n.t(
                  zhHans: '查看支付通知',
                  zhHant: '查看支付通知',
                  en: 'View payment messages',
                  ja: '支払い通知を見る',
                  ko: '결제 알림 보기'),
              foreground: foreground,
              muted: muted,
              onTap: _openPaymentAssistant,
            ),
            _PaymentNoticeRow(
              icon: Icons.receipt_long_outlined,
              color: const Color(0xFF48AE88),
              title: i18n.t(
                  zhHans: '资产变动通知',
                  zhHant: '資產變動通知',
                  en: 'Asset changes',
                  ja: '資産変動通知',
                  ko: '자산 변동 알림'),
              subtitle: _latestAssetText?.isNotEmpty == true
                  ? _latestAssetText!
                  : noData,
              time: _latestAssetTime,
              foreground: foreground,
              muted: muted,
              onTap: () => _open(const WalletRecordScreen()),
            ),
            _PaymentNoticeRow(
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF1595AE),
              title: i18n.t(
                  zhHans: '转账与红包',
                  zhHant: '轉帳與紅包',
                  en: 'Transfers and red packets',
                  ja: '送金とレッドパケット',
                  ko: '이체 및 홍바오'),
              subtitle: _latestTransferText?.isNotEmpty == true
                  ? _latestTransferText!
                  : noData,
              foreground: foreground,
              muted: muted,
              onTap: () => _open(const WalletRecordScreen()),
            ),
            if (_pendingCount > 0)
              _PaymentNoticeRow(
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFFFF5A24),
                title: i18n.t(
                    zhHans: '待领取列表',
                    zhHant: '待領取列表',
                    en: 'Pending claims',
                    ja: '受取待ち一覧',
                    ko: '수령 대기 목록'),
                subtitle: _pendingCount == 0
                    ? noData
                    : i18n.format(
                        zhHans: '{count}项待处理',
                        zhHant: '{count}項待處理',
                        en: '{count} pending',
                        ja: '{count} 件保留中',
                        ko: '{count}건 대기 중',
                        vars: {'count': '$_pendingCount'}),
                foreground: foreground,
                muted: muted,
                onTap: () => _open(const WalletPendingListScreen()),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentNoticeRow extends StatelessWidget {
  const _PaymentNoticeRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.foreground,
    required this.muted,
    required this.onTap,
    this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? time;
  final Color foreground;
  final Color muted;
  final VoidCallback onTap;

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
                bottom: BorderSide(color: muted.withValues(alpha: 0.13))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: foreground,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))),
                        if (time != null)
                          Text(time!,
                              style: TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
