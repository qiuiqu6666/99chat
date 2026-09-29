import 'package:flutter/material.dart';
import '../pages/wallet/widgets/pay_password_prompt.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_create_limit_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'group_role_crown_icon.dart';
import '../pages/wallet/widgets/platform_coin_icon.dart';

/// Reviews the quoted fee before collecting a PIN. Charging remains with the
/// create-group endpoint, which checks the quote and balance again.
class CommunityCreatePaymentDialog extends StatefulWidget {
  const CommunityCreatePaymentDialog({
    super.key,
    required this.price,
    required this.loadBalance,
  });

  final CommunityCreatePrice price;
  final Future<int> Function() loadBalance;

  @override
  State<CommunityCreatePaymentDialog> createState() =>
      _CommunityCreatePaymentDialogState();
}

class _CommunityCreatePaymentDialogState
    extends State<CommunityCreatePaymentDialog> {
  static const _blue = Color(0xFF087AFF);
  static const _ink = Color(0xFF10172C);
  static const _muted = Color(0xFF76839C);
  int? _balance;
  bool _loading = true;
  bool _openingPassword = false;

  String t(String zh, String hant, String en, String ja, String ko) =>
      AppI18n.of(context).t(zhHans: zh, zhHant: hant, en: en, ja: ja, ko: ko);

  String get _coin => widget.price.currency == '99'
      ? t('个 99 币', '個 99 幣', '99 coins', '99コイン', '99 코인')
      : widget.price.currency;

  String amount(int minor) =>
      CommunityCreatePrice(currency: widget.price.currency, amountMinor: minor)
          .displayAmount;

  bool get _sufficient =>
      _balance != null && _balance! >= widget.price.amountMinor;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() => _loading = true);
    int? balance;
    try {
      balance = await widget.loadBalance();
    } catch (_) {
      // Unknown balances must never appear as a zero balance or enable payment.
    }
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _loading = false;
    });
  }

  Future<void> _promptPassword() async {
    if (_openingPassword || _loading || !_sufficient) return;
    setState(() => _openingPassword = true);
    String? pin;
    try {
      final confirmed = await PayPasswordPrompt.show(
        context,
        title: t('创建超级大群', '建立超級大群', 'Create super group', 'スーパーグループを作成',
            '슈퍼 그룹 생성'),
        amountText: widget.price.displayAmount,
        amountCoin: widget.price.currency,
        payText: t('钱包余额', '錢包餘額', 'Wallet balance', 'ウォレット残高', '지갑 잔액'),
        payCoinCode: widget.price.currency,
        onSubmit: (value) async {
          pin = value;
          return null;
        },
      );
      if (!mounted) return;
      if (confirmed == true && pin != null) Navigator.pop(context, pin);
    } finally {
      if (mounted) setState(() => _openingPassword = false);
    }
  }

  Widget _panel(Widget child, {bool warm = false}) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: warm ? 6 : 8),
        decoration: BoxDecoration(
          color: warm ? null : const Color(0xFFF5F7FB),
          gradient: warm
              ? const LinearGradient(colors: [
                  Color(0xFFFFF0DB),
                  Color(0xFFFFF7ED),
                ])
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  Widget _balanceRow(String label, int? minor) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: _muted))),
        const SizedBox(width: 12),
        Flexible(
            child: Align(
          alignment: Alignment.centerRight,
          child: _balanceAmount(minor),
        )),
      ]);

  Widget _balanceAmount(int? minor, {Color color = _ink}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
              child: Text(minor == null ? '—' : amount(minor),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color))),
          if (minor != null) ...[
            const SizedBox(width: 5),
            if (widget.price.currency == '99')
              Semantics(label: _coin, child: const PlatformCoinIcon(size: 17))
            else
              Text(widget.price.currency,
                  style: TextStyle(fontSize: 12, color: color)),
          ],
        ],
      );

  Widget _benefit(String label) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          const Icon(Icons.check_circle, color: _blue, size: 18),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: _muted))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final canContinue = !_loading && _sufficient && !_openingPassword;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(children: [
              SizedBox(
                width: double.infinity,
                height: 70,
                child: Center(
                  child: SizedBox(
                    width: 164,
                    height: 70,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(
                        width: 66,
                        height: 66,
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFF7EE),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFE7CF), Color(0xFFFFF2E5)],
                            ),
                          ),
                          child: const Center(
                              child: GroupRoleCrownIcon(
                            color: Color(0xFFFF710A),
                            highlightColor: Color(0xFFFF710A),
                            size: 34,
                          )),
                        ),
                      ),
                      for (final dot in const [
                        [26.0, 23.0, 8.0],
                        [19.0, 44.0, 4.0],
                        [130.0, 25.0, 8.0],
                        [125.0, 49.0, 4.0],
                      ])
                        Positioned(
                          left: dot[0],
                          top: dot[1],
                          child: Container(
                            width: dot[2],
                            height: dot[2],
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFFE7CC)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  key: const ValueKey('community-payment-close'),
                  tooltip: t('关闭', '關閉', 'Close', '閉じる', '닫기'),
                  onPressed: () => Navigator.pop(context),
                  alignment: Alignment.topRight,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF1F5FA),
                    ),
                    child: const Icon(Icons.close, color: _muted, size: 18),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(
              t('创建超级大群', '建立超級大群', 'Create super group', 'スーパーグループを作成',
                  '슈퍼 그룹 생성'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(height: 3),
            Text(
              t(
                  '确认支付后即可创建超级大群，最多可容纳 10 万成员',
                  '確認支付後即可建立超級大群，最多可容納 10 萬成員',
                  'Confirm payment to create a group for up to 100,000 members.',
                  'お支払い後、最大10万人のグループを作成します。',
                  '결제 후 최대 10만 명의 그룹이 생성됩니다.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: _muted),
            ),
            const SizedBox(height: 7),
            _panel(
                Row(children: [
                  Image.asset(
                    'assets/img/community_creation_coins.png',
                    width: 42,
                    height: 42,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            t('支付金额', '支付金額', 'Payment amount', '支払金額',
                                '결제 금액'),
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF714124))),
                        const SizedBox(height: 2),
                        FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(children: [
                              Text(widget.price.displayAmount,
                                  style: const TextStyle(
                                      color: Color(0xFFFF5809),
                                      fontSize: 28,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(width: 8),
                              if (widget.price.currency == '99')
                                Semantics(
                                    label: _coin,
                                    child: const PlatformCoinIcon(size: 24))
                              else
                                Text(widget.price.currency,
                                    style: const TextStyle(
                                        color: Color(0xFFFF5809),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                            ])),
                      ])),
                ]),
                warm: true),
            const SizedBox(height: 6),
            _panel(Column(children: [
              _balanceRow(
                  t('当前余额', '目前餘額', 'Current balance', '現在の残高', '현재 잔액'),
                  _balance),
              const Divider(height: 12, color: Color(0xFFDDE6F3)),
              _balanceRow(
                  t('支付后余额', '支付後餘額', 'Balance after payment', '支払い後の残高',
                      '결제 후 잔액'),
                  _sufficient ? _balance! - widget.price.amountMinor : null),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator()),
              if (!_loading && _balance == null)
                TextButton(
                    onPressed: _loadBalance,
                    child: Text(t(
                        '余额加载失败，点击重试',
                        '餘額載入失敗，點擊重試',
                        'Could not load balance. Retry',
                        '残高を再読み込み',
                        '잔액 다시 불러오기'))),
              if (!_loading && _balance != null && !_sufficient)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 16, color: Color(0xFFD35B26)),
                        const SizedBox(width: 7),
                        Expanded(
                            child: Wrap(spacing: 5, runSpacing: 4, children: [
                          Text(
                              t(
                                  '余额不足，还差',
                                  '餘額不足，還差',
                                  'Insufficient balance. Short by',
                                  '残高不足。不足額',
                                  '잔액 부족. 부족 금액'),
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFD35B26))),
                          _balanceAmount(widget.price.amountMinor - _balance!,
                              color: const Color(0xFFD35B26)),
                        ])),
                      ]),
                ),
            ])),
            const SizedBox(height: 6),
            _panel(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  t('超级大群尊享权益', '超級大群專享權益', 'Super group benefits',
                      'スーパーグループの特典', '슈퍼 그룹 혜택'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
              _benefit(t('成员上限 10 万', '成員上限 10 萬', 'Up to 100,000 members',
                  '最大10万人', '최대 10만 명')),
              _benefit(t('更强的群管理能力', '更強的群管理能力', 'Advanced group management',
                  '充実した管理機能', '강력한 그룹 관리')),
              _benefit(t(
                  '适合大型社区/组织运营',
                  '適合大型社區/組織營運',
                  'For large communities and organizations',
                  '大規模コミュニティの運営に',
                  '대규모 커뮤니티 및 조직용')),
            ])),
            const SizedBox(height: 6),
            Text(
                t(
                    '支付成功后立即创建，支付后不支持退款',
                    '支付成功後立即建立，支付後不支援退款',
                    'Created after payment. Payments are non-refundable.',
                    '支払い後に作成され、返金はできません。',
                    '결제 후 생성되며 환불되지 않습니다.'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, color: _muted, height: 1.4)),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                  flex: 3,
                  child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFEEF3FB),
                          foregroundColor: _ink,
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13))),
                      child: Text(t('取消', '取消', 'Cancel', 'キャンセル', '취소')))),
              const SizedBox(width: 10),
              Expanded(
                  flex: 5,
                  child: FilledButton(
                    key: const ValueKey('community-payment-confirm'),
                    onPressed: canContinue ? _promptPassword : null,
                    style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _blue,
                        disabledForegroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    child: Text(
                        t('确认支付并创建', '確認支付並建立', 'Pay and create', '支払って作成',
                            '결제하고 생성'),
                        textAlign: TextAlign.center),
                  )),
            ]),
          ]),
        ),
      ),
    );
  }
}
