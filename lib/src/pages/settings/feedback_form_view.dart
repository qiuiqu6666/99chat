import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tencent_cloud_chat_demo/src/customer_service_icon.dart';
import 'package:tencent_cloud_chat_demo/src/api/feedback_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/utils/customer_service_nav.dart';
import 'settings_widgets.dart';

/// Shared feedback/report presentation; callers own submission and attachments.
class FeedbackFormView extends StatelessWidget {
  const FeedbackFormView(
      {super.key,
      required this.controller,
      required this.attachments,
      required this.maxScreenshots,
      required this.submitting,
      required this.canSubmit,
      required this.embedded,
      required this.onSubmit,
      required this.onAddImage,
      required this.onRemoveImage,
      this.selectedType,
      this.onTypeChanged,
      this.typeLabel,
      this.target,
      this.reason});
  final TextEditingController controller;
  final List<Uint8List> attachments;
  final int maxScreenshots;
  final bool submitting, canSubmit, embedded;
  final VoidCallback onSubmit, onAddImage;
  final ValueChanged<int> onRemoveImage;
  final FeedbackType? selectedType;
  final ValueChanged<FeedbackType>? onTypeChanged;
  final String Function(FeedbackType)? typeLabel;
  final String? target, reason;
  bool get isComplaint => target != null;
  String get keyPrefix => isComplaint ? 'complaint' : 'feedback';
  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final i18n = AppI18n.of(context);
    final textColor = AppColors.text(dark: dark);
    final muted = dark ? const Color(0xFFADB8CB) : const Color(0xFF748198);
    final fill = dark ? const Color(0xFF242D3C) : const Color(0xFFF4F6F9);
    final card = dark ? const Color(0xFF192331) : Colors.white;
    const blue = Color(0xFF218CFF);
    final titleStyle =
        TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600);
    final helperStyle = TextStyle(color: muted, fontSize: 13, height: 1.5);
    String tr(String cn, String tw, String en, String ja, String ko) =>
        i18n.t(zhHans: cn, zhHant: tw, en: en, ja: ja, ko: ko);

    Widget heading(String title, String trailing) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(title, style: titleStyle),
              Text(trailing, style: helperStyle),
            ],
          ),
        );

    final heroCopy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: tr(
                      '您的意见', '您的意見', 'Your feedback ', 'あなたの声を', '여러분의 의견은 ')),
              TextSpan(
                  text: tr('很重要', '很重要', 'matters', '大切に', '소중합니다'),
                  style: const TextStyle(color: blue)),
            ]),
            style: TextStyle(
                color: textColor,
                fontSize: 25,
                height: 1.3,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
            tr(
                '每一条反馈，都能帮助我们做得更好',
                '每一條回饋，都能幫助我們做得更好',
                'Every piece of feedback helps us improve.',
                '皆さまの声がサービスの改善につながります。',
                '모든 의견은 더 나은 서비스를 만드는 데 도움이 됩니다.'),
            style: helperStyle),
      ],
    );
    final illustration = Image.asset('assets/images/feedback_hero.png',
        key: const ValueKey('feedback-hero'),
        width: 180,
        height: 180,
        cacheWidth: 480,
        excludeFromSemantics: true);

    Widget badge(IconData icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 19,
              height: 22,
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 22, color: blue),
                Icon(
                  icon == Icons.shield_rounded
                      ? Icons.check_rounded
                      : icon == Icons.bolt_rounded
                          ? Icons.bolt_rounded
                          : Icons.favorite_rounded,
                  size: icon == Icons.bolt_rounded ? 11 : 12,
                  color: Colors.white,
                ),
              ]),
            ),
            const SizedBox(width: 4),
            Flexible(
                child:
                    Text(label, style: helperStyle.copyWith(fontSize: 10.5))),
          ],
        );

    final types = LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = scale > 1.4 || constraints.maxWidth < 250 ? 2 : 3;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: FeedbackType.values.map((type) {
            final selected = selectedType == type;
            final icon = switch (type) {
              FeedbackType.suggestion => Icons.lightbulb_outline_rounded,
              FeedbackType.bug => Icons.bug_report_outlined,
              FeedbackType.other => Icons.more_horiz_rounded,
            };
            return SizedBox(
                width: width,
                child: Semantics(
                  key: ValueKey('feedback-type-${type.name}'),
                  selected: selected,
                  button: true,
                  child: Material(
                    color: selected
                        ? (dark
                            ? const Color(0xFF173E65)
                            : const Color(0xFFE8F4FF))
                        : fill,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: submitting ? null : () => onTypeChanged!(type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: selected ? blue : Colors.transparent,
                              width: 1.5),
                        ),
                        child: Column(children: [
                          Icon(icon, color: selected ? blue : muted, size: 27),
                          const SizedBox(height: 8),
                          Text(typeLabel!(type),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: selected ? blue : textColor,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ]),
                      ),
                    ),
                  ),
                ));
          }).toList());
    });

    final screenshots = Wrap(spacing: 12, runSpacing: 12, children: [
      ...attachments.asMap().entries.map((entry) => SizedBox(
            width: 100,
            height: 100,
            child: Stack(children: [
              Positioned.fill(
                  child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(entry.value,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => ColoredBox(
                        color: fill,
                        child:
                            Icon(Icons.broken_image_outlined, color: muted))),
              )),
              Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip:
                        tr('删除图片', '刪除圖片', 'Remove image', '画像を削除', '이미지 삭제'),
                    onPressed:
                        submitting ? null : () => onRemoveImage(entry.key),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        minimumSize: const Size(48, 48),
                        foregroundColor: Colors.white),
                    iconSize: 22,
                    padding: const EdgeInsets.fromLTRB(22, 4, 4, 22),
                    icon: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: Icon(Icons.close_rounded, size: 14),
                      ),
                    ),
                  )),
            ]),
          )),
      if (attachments.length < maxScreenshots)
        SizedBox(
            width: 100,
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: submitting ? null : onAddImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints.tightFor(height: 100),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: dark
                              ? const Color(0xFF46546A)
                              : const Color(0xFFD7DFEB))),
                  child: Center(
                    child: Icon(Icons.add_rounded,
                        color: muted,
                        size: 36,
                        semanticLabel:
                            tr('添加图片', '新增圖片', 'Add image', '画像を追加', '이미지 추가')),
                  ),
                ),
              ),
            )),
    ]);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF101A28) : const Color(0xFFF3F9FF),
      appBar: embedded
          ? null
          : AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              backgroundColor:
                  dark ? const Color(0xFF101A28) : const Color(0xFFF5FAFF),
              surfaceTintColor: Colors.transparent,
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: blue, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: Text(
                  isComplaint
                      ? tr('投诉', '投訴', 'Complaint', '通報', '신고')
                      : tr('意见反馈', '意見回饋', 'Feedback', 'フィードバック', '의견 보내기'),
                  style: titleStyle),
              actions: [
                IconButton(
                  key: ValueKey('$keyPrefix-customer-service'),
                  tooltip: tr(
                      '在线客服', '線上客服', 'Customer service', 'オンラインサポート', '고객센터'),
                  icon: SvgPicture.string(customerServiceIconSvg,
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                      colorFilter: const ColorFilter.mode(
                          AppColors.primaryBlue, BlendMode.srcIn)),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    CustomerServiceNav.open(context);
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF122B45), const Color(0xFF101A28)]
              : [
                  const Color(0xFFF5FAFF),
                  const Color(0xFFF7FBFF),
                  const Color(0xFFEDF6FF)
                ],
        )),
        child: SafeArea(
          top: embedded,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.zero,
                      child: CustomPaint(
                        painter: _FeedbackHeroBackdrop(dark: dark),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 22, 8, 2),
                          child: LayoutBuilder(builder: (context, constraints) {
                            final expandedText =
                                MediaQuery.textScalerOf(context).scale(13) > 17;
                            final badges = [
                              badge(
                                  Icons.shield_rounded,
                                  tr('认真倾听', '認真傾聽', 'We listen', '声を聴く',
                                      '경청')),
                              badge(
                                  Icons.bolt_rounded,
                                  tr('欢迎建议', '歡迎建議', 'Ideas welcome', '提案歓迎',
                                      '제안 환영')),
                              badge(
                                  Icons.circle,
                                  tr('持续优化', '持續優化', 'Keep improving', '継続的に改善',
                                      '지속적인 개선')),
                            ];
                            final badgeRow = expandedText
                                ? Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: badges)
                                : Row(children: [
                                    for (var i = 0; i < badges.length; i++) ...[
                                      if (i > 0)
                                        Container(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 5),
                                            width: 1,
                                            height: 16,
                                            color: dark
                                                ? const Color(0xFF3A4B60)
                                                : const Color(0xFFD0DEED)),
                                      Expanded(child: badges[i]),
                                    ],
                                  ]);
                            final copy = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                heroCopy,
                                const SizedBox(height: 20),
                                badgeRow
                              ],
                            );
                            if (expandedText ||
                                constraints.maxWidth < 310 ||
                                Localizations.localeOf(context).languageCode !=
                                    'zh') {
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: SizedBox(
                                            width: 150,
                                            height: 150,
                                            child: illustration)),
                                    copy,
                                  ]);
                            }
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                    right: -18,
                                    top: -20,
                                    bottom: -18,
                                    width: constraints.maxWidth * .42,
                                    child: illustration),
                                ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 140),
                                    child: SizedBox(
                                        width: constraints.maxWidth * .69,
                                        child: copy)),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: card, borderRadius: BorderRadius.circular(22)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isComplaint) ...[
                              heading(
                                  tr('投诉对象', '投訴對象', 'Reported user', '通報対象',
                                      '신고 대상'),
                                  ''),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: fill,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text(target!,
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        height: 1.5)),
                              ),
                              const SizedBox(height: 26),
                              heading(
                                  tr('投诉原因', '投訴原因', 'Reason', '通報理由', '신고 사유'),
                                  ''),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                        color: dark
                                            ? const Color(0xFF173E65)
                                            : const Color(0xFFE8F4FF),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text(reason!,
                                        style: const TextStyle(
                                            color: blue,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                  )),
                            ] else ...[
                              heading(
                                  tr('反馈类型', '回饋類型', 'Feedback type', '種別',
                                      '의견 유형'),
                                  tr(
                                      '请选择问题的类型',
                                      '請選擇問題的類型',
                                      'Choose a category',
                                      '種別を選択',
                                      '유형을 선택하세요')),
                              types,
                            ],
                            const SizedBox(height: 26),
                            heading(
                                isComplaint
                                    ? tr(
                                        '补充说明（选填）',
                                        '補充說明（選填）',
                                        'Details (optional)',
                                        '補足説明（任意）',
                                        '추가 설명 (선택)')
                                    : tr('反馈内容', '回饋內容', 'Your feedback', '内容',
                                        '의견 내용'),
                                '${controller.text.characters.length}/2000'),
                            TextField(
                              controller: controller,
                              enabled: !submitting,
                              minLines: 5,
                              maxLines: 10,
                              maxLength: 2000,
                              style: TextStyle(
                                  color: textColor, fontSize: 15, height: 1.6),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: fill,
                                counterText: '',
                                hintText: isComplaint
                                    ? tr(
                                        '请描述违规行为，帮助我们核实情况',
                                        '請描述違規行為，幫助我們核實情況',
                                        'Describe the violation to help us review it.',
                                        '違反行為を詳しく記入してください。',
                                        '위반 행위를 자세히 작성해 주세요.')
                                    : tr(
                                        '请详细描述您的问题或建议（必填）',
                                        '請詳細描述您的問題或建議（必填）',
                                        'Describe your issue or suggestion (required)',
                                        '問題や提案を詳しく記入してください（必須）',
                                        '문제나 제안을 자세히 작성해 주세요 (필수)'),
                                hintStyle: TextStyle(
                                    color: muted, fontSize: 15, height: 1.6),
                                contentPadding: const EdgeInsets.all(16),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: blue, width: 1.5)),
                              ),
                            ),
                            const SizedBox(height: 26),
                            heading(
                                tr(
                                    '相关截图（选填）',
                                    '相關截圖（選填）',
                                    'Screenshots (optional)',
                                    '画像（任意）',
                                    '스크린샷 (선택)'),
                                '${attachments.length}/$maxScreenshots'),
                            LayoutBuilder(builder: (context, constraints) {
                              final help = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      tr(
                                          '上传相关截图，帮助我们更快定位问题',
                                          '上傳相關截圖，幫助我們更快定位問題',
                                          'Add screenshots to help us understand the issue.',
                                          '状況がわかるスクリーンショットを追加してください。',
                                          '문제 파악에 도움이 되는 스크린샷을 추가해 주세요.'),
                                      style: helperStyle),
                                  const SizedBox(height: 4),
                                  Text(
                                      tr(
                                          '支持 JPG、PNG、WEBP，单张不超过 10MB',
                                          '支援 JPG、PNG、WEBP，單張不超過 10MB',
                                          'JPG, PNG or WEBP · Up to 10 MB each',
                                          'JPG・PNG・WEBP、1枚につき10MBまで',
                                          'JPG, PNG, WEBP · 장당 최대 10MB'),
                                      style: helperStyle),
                                ],
                              );
                              if (attachments.isNotEmpty) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    screenshots,
                                    const SizedBox(height: 12),
                                    help
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(width: 100, child: screenshots),
                                  const SizedBox(width: 14),
                                  Expanded(child: help),
                                ],
                              );
                            }),
                          ]),
                    ),
                    const SizedBox(height: 18),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: canSubmit
                            ? const LinearGradient(
                                colors: [Color(0xFF40B2FF), blue])
                            : null,
                        color: canSubmit
                            ? null
                            : (dark
                                ? const Color(0xFF2A3A4F)
                                : const Color(0xFFDDE7F2)),
                      ),
                      child: ElevatedButton(
                        key: ValueKey('$keyPrefix-submit'),
                        onPressed: canSubmit ? onSubmit : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: muted,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(52),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 20),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(tr('提交', '提交', 'Submit', '送信', '제출'),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.shield_outlined, color: muted, size: 17),
                      const SizedBox(width: 7),
                      Flexible(
                          child: Text(
                              tr(
                                  '我们会严格保护您的隐私信息。',
                                  '我們會嚴格保護您的隱私資訊。',
                                  'We will strictly protect your private information.',
                                  'お客様の個人情報を厳重に保護します。',
                                  '고객님의 개인정보를 철저히 보호하겠습니다.'),
                              style: helperStyle,
                              textAlign: TextAlign.center)),
                    ]),
                  ]),
            )),
          ),
        ),
      ),
    );
  }
}

class _FeedbackHeroBackdrop extends CustomPainter {
  const _FeedbackHeroBackdrop({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final wave = Path()
      ..moveTo(-16, size.height * .12)
      ..cubicTo(size.width * .15, -20, size.width * .43, size.height * .17,
          size.width * .62, size.height * .04)
      ..cubicTo(size.width * .83, -size.height * .25, size.width * .9,
          size.height * .05, size.width + 16, size.height * .04)
      // Extend beneath the next card so its rounded corners overlap the hero.
      // The lower edge stays horizontal; only the top edge has a wave.
      ..lineTo(size.width + 16, size.height + 22)
      ..lineTo(-16, size.height + 22)
      ..close();
    canvas.drawPath(
        wave,
        Paint()
          ..shader = LinearGradient(
            colors: dark
                ? [const Color(0xFF173550), const Color(0xFF1A3D64)]
                : [const Color(0xFFEAF5FF), const Color(0xFFDDEEFF)],
          ).createShader(rect));
    final orb = Offset(size.width * .93, size.height * .86);
    canvas.drawCircle(
        orb,
        13,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.5, -.5),
            colors: dark
                ? [const Color(0xFF547C86), const Color(0x00173550)]
                : [const Color(0xFFE5FFF4), const Color(0x0052CCF2)],
          ).createShader(Rect.fromCircle(center: orb, radius: 13)));
  }

  @override
  bool shouldRepaint(_FeedbackHeroBackdrop oldDelegate) =>
      oldDelegate.dark != dark;
}
