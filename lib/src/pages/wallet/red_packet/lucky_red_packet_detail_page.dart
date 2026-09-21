import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_amount.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/wallet_page_colors.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';

import 'widgets/red_packet_detail_app_bar.dart';

const Color _kRedPacketAmountGold = Color(0xFFB08A4A);

class LuckyRedPacketClaimPreviewData {
  const LuckyRedPacketClaimPreviewData({
    required this.avatarUrl,
    required this.name,
    required this.time,
    required this.amountText,
    this.bestLuck = false,
  });

  final String avatarUrl;
  final String name;
  final String time;
  final String amountText;
  final bool bestLuck;
}

class LuckyRedPacketDetailData {
  const LuckyRedPacketDetailData({
    required this.orderId,
    required this.packetType,
    required this.senderName,
    required this.senderAvatar,
    required this.greeting,
    required this.amountText,
    required this.claimedCount,
    required this.totalCount,
    required this.claimedAmountText,
    required this.totalAmountText,
    required this.claims,
    this.currency = '99',
    this.allClaimed = true,
    this.statusHint = '',
    this.claimsLoaded = true,
  });

  static const empty = LuckyRedPacketDetailData(
    orderId: '',
    packetType: 'LUCKY_GROUP',
    senderName: '',
    senderAvatar: '',
    greeting: '',
    amountText: '',
    claimedCount: 0,
    totalCount: 0,
    claimedAmountText: '0.00',
    totalAmountText: '0.00',
    currency: '99',
    allClaimed: false,
    claims: [],
    statusHint: '',
    claimsLoaded: true,
  );

  final String orderId;
  final String packetType;
  final String senderName;
  final String senderAvatar;
  final String greeting;
  final String amountText;
  final int claimedCount;
  final int totalCount;
  final String claimedAmountText;
  final String totalAmountText;
  final List<LuckyRedPacketClaimPreviewData> claims;

  /// 红包币种代码（如 `99` / `USDT`）。
  final String currency;
  final bool allClaimed;
  final String statusHint;
  final bool claimsLoaded;

  String get displaySenderName {
    return senderName.trim();
  }

  String get displayGreeting {
    return greeting.trim();
  }

  String get displayAmount {
    return amountText.trim();
  }

  /// 展示用币种单位：平台币为「元」，USDT 为 `USDT`。
  String get coinUnit => walletDisplayCoin(currency);

  String get progressText {
    return '已领取 $claimedCount/$totalCount 个，共 $claimedAmountText/$totalAmountText $coinUnit';
  }
}

/// Presentation shared by the open result and historical packet details.
class LuckyRedPacketDetailPage extends StatelessWidget {
  const LuckyRedPacketDetailPage({super.key, required this.data, this.onBack});
  final LuckyRedPacketDetailData data;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final surface = cs.dark ? const Color(0xFF191919) : Colors.white;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: redPacketImmersiveOverlayStyle(context),
      child: Scaffold(
        backgroundColor: surface,
        extendBodyBehindAppBar: true,
        appBar: buildRedPacketDetailAppBar(context,
            immersive: true, onBack: onBack),
        body: Column(children: [
          SizedBox(
            height: redPacketDetailNavHeight(context) + 64,
            width: double.infinity,
            child: const CustomPaint(painter: _LuckyHeaderPainter()),
          ),
          Expanded(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _LuckyDetailBody(data: data),
          ))),
          buildRedPacketDetailFooter(context),
        ]),
      ),
    );
  }
}

class _LuckyDetailBody extends StatelessWidget {
  const _LuckyDetailBody({required this.data});
  final LuckyRedPacketDetailData data;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final gold = cs.dark ? const Color(0xFFE6C58B) : _kRedPacketAmountGold;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AppUserAvatar(
                faceUrl: data.senderAvatar,
                showName: data.displaySenderName,
                size: 28,
                borderRadius: BorderRadius.circular(5)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(
                    i18n.t(
                        zhHans: '${data.displaySenderName}的红包',
                        zhHant: '${data.displaySenderName}的紅包',
                        en: 'Red packet from ${data.displaySenderName}',
                        ja: '${data.displaySenderName}の紅包',
                        ko: '${data.displaySenderName}님의 홍바오'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: cs.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w500))),
          ]),
          if (data.displayGreeting.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(data.displayGreeting,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.text, fontSize: 20, height: 1.4)),
          ],
          const SizedBox(height: 30),
          if (data.displayAmount.isNotEmpty)
            Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: data.displayAmount,
                      style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w500,
                          height: 1.15)),
                  TextSpan(
                      text: ' ${data.coinUnit}',
                      style: const TextStyle(fontSize: 16)),
                ]),
                textAlign: TextAlign.center,
                style: TextStyle(color: gold))
          else if (data.statusHint.isNotEmpty)
            Text(data.statusHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.subText, fontSize: 17, height: 1.5)),
        ]),
      )),
      SliverToBoxAdapter(
          child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
            color: cs.dark ? const Color(0xFF202020) : const Color(0xFFF7F7F7),
            border: Border(bottom: BorderSide(color: cs.line, width: .5))),
        child: Text(data.progressText,
            style: TextStyle(color: cs.subText, fontSize: 13, height: 1.5)),
      )),
      if (data.claims.isEmpty)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Text(
              !data.claimsLoaded
                  ? i18n.t(
                      zhHans: '领取记录暂时加载失败',
                      zhHant: '領取記錄暫時載入失敗',
                      en: 'Failed to load claim records.',
                      ja: '受取記録の読み込みに失敗しました。',
                      ko: '수령 기록을 불러오지 못했습니다.')
                  : i18n.t(
                      zhHans: '还没有人领取这个红包',
                      zhHant: '還沒有人領取這個紅包',
                      en: 'No one has claimed this red packet yet.',
                      ja: 'まだ誰もこの紅包を受け取っていません。',
                      ko: '아직 이 홍바오를 받은 사람이 없습니다.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.subText, fontSize: 14)),
        ))
      else
        SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
          final claim = data.claims[index];
          return Column(children: [
            _ClaimRow(
                avatarUrl: claim.avatarUrl,
                name: claim.name,
                time: claim.time,
                amount: claim.amountText,
                bestLuck: claim.bestLuck,
                bestLuckLabel: i18n.t(
                    zhHans: '手气最佳',
                    zhHant: '手氣最佳',
                    en: 'Best luck',
                    ja: '運試し王',
                    ko: '최고 행운')),
            if (index < data.claims.length - 1)
              Divider(
                  height: .5,
                  thickness: .5,
                  indent: 76,
                  endIndent: 20,
                  color: cs.line),
          ]);
        }, childCount: data.claims.length)),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow(
      {required this.avatarUrl,
      required this.name,
      required this.time,
      required this.amount,
      required this.bestLuckLabel,
      this.bestLuck = false});
  final String avatarUrl, name, time, amount, bestLuckLabel;
  final bool bestLuck;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final amountView =
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(amount,
          style: TextStyle(
              color: cs.text, fontSize: 17, fontWeight: FontWeight.w500)),
      if (bestLuck) ...[
        const SizedBox(height: 5),
        Text('♛ $bestLuckLabel',
            style: TextStyle(color: cs.tagTextColor, fontSize: 12)),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: LayoutBuilder(builder: (context, constraints) {
        final stackAmount = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppUserAvatar(
              faceUrl: avatarUrl,
              showName: name,
              size: 44,
              borderRadius: BorderRadius.circular(6)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: cs.text, fontSize: 16, height: 1.3)),
                const SizedBox(height: 5),
                Text(time, style: TextStyle(color: cs.subText, fontSize: 12)),
                if (stackAmount) ...[const SizedBox(height: 8), amountView],
              ])),
          if (!stackAmount) ...[
            const SizedBox(width: 12),
            Flexible(
              fit: FlexFit.tight,
              child: Align(alignment: Alignment.topRight, child: amountView),
            )
          ],
        ]);
      }),
    );
  }
}

class _LuckyHeaderPainter extends CustomPainter {
  const _LuckyHeaderPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const arcDepth = 24.0;
    final path = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - arcDepth)
      ..quadraticBezierTo(
          size.width / 2, size.height + arcDepth, 0, size.height - arcDepth)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFD9584D));
    // Trace only the lower curve, leaving the top and side edges unbordered.
    final goldEdge = Path()
      ..moveTo(size.width, size.height - arcDepth)
      ..quadraticBezierTo(
          size.width / 2, size.height + arcDepth, 0, size.height - arcDepth);
    canvas.drawPath(
      goldEdge,
      Paint()
        ..color = const Color(0xFFE8C58B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
