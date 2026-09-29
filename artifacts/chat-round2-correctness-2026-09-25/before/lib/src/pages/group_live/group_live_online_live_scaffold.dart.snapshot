import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/adaptive_modal.dart';
import 'package:tencent_cloud_chat_demo/src/ui/widgets/app_cupertino_datetime_sheet.dart';
import 'package:tencent_cloud_chat_demo/src/utils/immersive_app_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';

/// Shared visual shell for group live schedule / OBS push pages.
/// Shared hero / icon asset for group live flows.
const String groupLiveHeroAsset = 'assets/live/group_live_hero.webp';

/// Theme colors shared by live setup, push information and their sheets.
class GroupLivePageColors {
  const GroupLivePageColors._(this.dark);

  final bool dark;

  factory GroupLivePageColors.of(BuildContext context) {
    var dark = Theme.of(context).brightness == Brightness.dark;
    try {
      dark = Provider.of<DefaultThemeData>(context).currentThemeType ==
          ThemeType.dark;
    } on ProviderNotFoundException {
      // Standalone previews can use the surrounding Material theme.
    }
    return GroupLivePageColors._(dark);
  }

  Color get bg =>
      dark ? AppTokens.backgroundDark : GroupLiveOnlineLiveScaffold.pageBg;
  Color get card => AppTokens.appSurface(dark);
  Color get field => dark ? AppTokens.surfaceAltDark : const Color(0xFFF1F2F4);
  Color get text => AppTokens.appTextPrimary(dark);
  Color get subText => AppTokens.appTextSecondary(dark);
  Color get hint => dark ? AppTokens.textSecondaryDark : AppTokens.ink400;
  Color get icon => dark ? AppTokens.textSecondaryDark : AppTokens.ink400;
  Color get disabledIcon => dark ? AppTokens.ink500 : AppTokens.ink300;
  Color get shadow =>
      dark ? AppTokens.shadowDark : Colors.black.withValues(alpha: 0.04);
}

class GroupLiveOnlineLiveScaffold extends StatelessWidget {
  const GroupLiveOnlineLiveScaffold({
    super.key,
    required this.body,
    this.bottomButton,
    this.onBack,
    this.actions,
    this.backgroundDecoration,
    this.backgroundColor,
    this.appBarForegroundColor,
    this.bodyPadding,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final Widget? bottomButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Decoration? backgroundDecoration;
  final Color? backgroundColor;
  final Color? appBarForegroundColor;
  final EdgeInsetsGeometry? bodyPadding;
  final bool extendBodyBehindAppBar;

  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color primaryBlue = Color(0xFF2D8CFF);

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final pageColor = backgroundColor ?? cs.bg;
    final overlayBg = backgroundDecoration == null ? pageColor : cs.bg;
    final overlay = immersiveOverlayForColors(
      statusBarBackground: overlayBg,
      navigationBarBackground: overlayBg,
    );
    final barIcon = appBarForegroundColor ?? AppTokens.accent;
    final barColor = extendBodyBehindAppBar
        ? Colors.transparent
        : (backgroundDecoration == null ? pageColor : Colors.transparent);
    final resolvedPadding =
        bodyPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 24);
    final scrollPadding = extendBodyBehindAppBar
        ? resolvedPadding.add(
            EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight,
            ),
          )
        : resolvedPadding;
    final content = Column(
      children: [
        Expanded(
          child: TapRegion(
            onTapOutside: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: scrollPadding,
              child: body,
            ),
          ),
        ),
        if (bottomButton != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: bottomButton!,
            ),
          ),
      ],
    );
    final scaffold = Scaffold(
      backgroundColor:
          backgroundDecoration == null ? pageColor : Colors.transparent,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: AppBar(
        backgroundColor: barColor,
        systemOverlayStyle: overlay,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: extendBodyBehindAppBar,
        iconTheme: IconThemeData(color: barIcon),
        leading: AppBackButton(
          color: barIcon,
          onPressed: onBack,
        ),
        actions: actions,
      ),
      body: content,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: backgroundDecoration == null
          ? scaffold
          : SizedBox.expand(
              child: DecoratedBox(
                decoration: backgroundDecoration!,
                child: scaffold,
              ),
            ),
    );
  }
}

class GroupLiveOnlineLiveHeader extends StatelessWidget {
  const GroupLiveOnlineLiveHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.18,
      alignment: Alignment.topCenter,
      child: Image.asset(
        'assets/live/live99.webp',
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.live_tv_rounded,
          size: 96,
          color: GroupLiveOnlineLiveScaffold.primaryBlue,
        ),
      ),
    );
  }
}

/// Header for the schedule / room configuration step.
class GroupLiveScheduleHeader extends StatelessWidget {
  const GroupLiveScheduleHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final i18n = AppI18n.of(context);
    return Column(
      children: [
        Image.asset(
          groupLiveHeroAsset,
          height: 168,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.live_tv_rounded,
            size: 96,
            color: GroupLiveOnlineLiveScaffold.primaryBlue,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          i18n.t(
            zhHans: '直播间配置',
            zhHant: '直播間配置',
            en: 'Live room setup',
            ja: '配信ルーム設定',
            ko: '라이브룸 설정',
          ),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: cs.text,
          ),
        ),
      ],
    );
  }
}

class GroupLiveFormSection extends StatelessWidget {
  const GroupLiveFormSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.text,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 10),
        GroupLiveFormCard(children: children),
      ],
    );
  }
}

class GroupLiveFormCard extends StatelessWidget {
  const GroupLiveFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class GroupLiveSettingsCard extends StatelessWidget {
  const GroupLiveSettingsCard({
    super.key,
    required this.title,
    this.trailing,
    required this.children,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.text,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class GroupLiveCopyField extends StatelessWidget {
  const GroupLiveCopyField({
    super.key,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.subText,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: cs.field,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      value,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: cs.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: value.trim().isEmpty ? null : onCopy,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: value.trim().isEmpty ? cs.disabledIcon : cs.icon,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GroupLivePushQrField extends StatelessWidget {
  const GroupLivePushQrField({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final i18n = AppI18n.of(context);
    final data = value.trim();
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.field,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(10),
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i18n.t(
              zhHans: '可用芯象扫描二维码填入推流地址',
              zhHant: '可用芯象掃描二維碼填入推流地址',
              en: 'Scan this QR code in Xinxian to fill the streaming URL.',
              ja: '芯象でこのQRを読み取ると配信URLを入力できます。',
              ko: '芯象에서 이 QR을 스캔하면 推流 주소를 입력할 수 있습니다.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.subText,
            ),
          ),
        ],
      ),
    );
  }
}

class GroupLivePointsUsageSection extends StatelessWidget {
  const GroupLivePointsUsageSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final i18n = AppI18n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.t(
            zhHans: '积分使用',
            zhHant: '積分使用',
            en: 'Points usage',
            ja: 'ポイント使用',
            ko: '포인트 사용',
          ),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: cs.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          i18n.t(
            zhHans:
                '1. 开启直播后\n   a. 1GB 直播流量消耗 300 积分\n   b. 流量按向上取整的 GB 数计算，比如不满 1GB 按 1GB 收取积分',
            zhHant:
                '1. 開啟直播後\n   a. 1GB 直播流量消耗 300 積分\n   b. 流量按向上取整的 GB 數計算，比如不滿 1GB 按 1GB 收取積分',
            en: '1. After going live\n   a. 1GB traffic costs 300 points\n   b. Traffic is billed in whole GB (rounded up)',
            ja: '1. 配信開始後\n   a. 1GB あたり 300 ポイント\n   b. 流量は GB 単位で切り上げ課金',
            ko: '1. 방송 시작 후\n   a. 1GB 流量당 300 포인트\n   b. 流量은 GB 단위 올림 과금',
          ),
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: cs.subText,
          ),
        ),
      ],
    );
  }
}

class GroupLivePrimaryButton extends StatelessWidget {
  const GroupLivePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: GroupLiveOnlineLiveScaffold.primaryBlue,
          disabledForegroundColor: Colors.white70,
          disabledBackgroundColor:
              GroupLiveOnlineLiveScaffold.primaryBlue.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

Future<void> groupLiveCopyToClipboard(
  BuildContext context, {
  required String label,
  required String value,
}) async {
  if (value.trim().isEmpty) return;
  await Clipboard.setData(ClipboardData(text: value.trim()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppI18n.of(context).t(
          zhHans: '已复制$label',
          zhHant: '已複製$label',
          en: 'Copied $label',
          ja: '$label をコピーしました',
          ko: '$label 복사됨',
        ),
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Earliest allowed scheduled start: now + 1 minute.
const Duration kGroupLiveScheduleMinLead = Duration(minutes: 1);

DateTime groupLiveScheduleMinimumDate([DateTime? now]) {
  return (now ?? DateTime.now()).add(kGroupLiveScheduleMinLead);
}

DateTime _clampGroupLiveScheduleTime(
  DateTime value, {
  required DateTime minimumDate,
  required DateTime maximumDate,
}) {
  if (value.isBefore(minimumDate)) return minimumDate;
  if (value.isAfter(maximumDate)) return maximumDate;
  return value;
}

DateTime _alignGroupLiveScheduleMinute(DateTime value, {int interval = 1}) {
  final safeInterval = interval <= 0 ? 1 : interval;
  final minute = (value.minute ~/ safeInterval) * safeInterval;
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    minute,
  );
}

/// Reuses the shared Cupertino sheet chrome (same as chat-history date picker).
Future<DateTime?> showGroupLiveScheduleTimePicker(
  BuildContext context, {
  required DateTime initialDateTime,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) async {
  final minDate = minimumDate ?? groupLiveScheduleMinimumDate();
  final maxDate = maximumDate ?? DateTime.now().add(const Duration(days: 7));
  final initial = _alignGroupLiveScheduleMinute(
    _clampGroupLiveScheduleTime(
      initialDateTime,
      minimumDate: minDate,
      maximumDate: maxDate,
    ),
  );
  return showAppCupertinoDateTimeSheet(
    context,
    title: AppI18n.of(context).t(
      zhHans: '预计开播时间',
      zhHant: '預計開播時間',
      en: 'Scheduled start',
      ja: '開始予定',
      ko: '예상 시작 시간',
    ),
    initialDateTime: initial,
    minimumDate: minDate,
    maximumDate: maxDate,
    mode: CupertinoDatePickerMode.dateAndTime,
    use24hFormat: true,
    minuteInterval: 1,
  );
}

void showGroupLiveObsGuideSheet(BuildContext context, {String? hint}) {
  final i18n = AppI18n.of(context);
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    desktopMaxWidth: 420,
    builder: (sheetContext) {
      final cs = GroupLivePageColors.of(sheetContext);
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.85;
      return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          image: DecorationImage(
            image: AssetImage('assets/livebg.webp'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.disabledIcon,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Image.asset(
                    'assets/live3.webp',
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  GroupLivePrimaryButton(
                    label: i18n.t(
                      zhHans: '我知道了',
                      zhHant: '我知道了',
                      en: 'Got it',
                      ja: '了解',
                      ko: '확인',
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class GroupLiveScheduleField extends StatelessWidget {
  const GroupLiveScheduleField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder,
    this.trailing = GroupLiveFieldTrailing.chevron,
  });

  final String label;
  final String value;
  final String? placeholder;
  final VoidCallback? onTap;
  final GroupLiveFieldTrailing trailing;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final display = value.trim().isNotEmpty ? value : (placeholder ?? '');
    final isPlaceholder = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.subText,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: cs.field,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        display,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: isPlaceholder ? cs.hint : cs.text,
                        ),
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 8),
                      _TrailingIcon(trailing: trailing),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum GroupLiveFieldTrailing { chevron, calendar, none }

class _TrailingIcon extends StatelessWidget {
  const _TrailingIcon({required this.trailing});

  final GroupLiveFieldTrailing trailing;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    switch (trailing) {
      case GroupLiveFieldTrailing.calendar:
        return Icon(
          Icons.calendar_today_outlined,
          color: cs.icon,
          size: 18,
        );
      case GroupLiveFieldTrailing.chevron:
        return Icon(
          Icons.chevron_right,
          color: cs.icon,
          size: 22,
        );
      case GroupLiveFieldTrailing.none:
        return const SizedBox.shrink();
    }
  }
}

class GroupLiveRoomNameField extends StatelessWidget {
  const GroupLiveRoomNameField({
    super.key,
    required this.controller,
    required this.enabled,
    this.hintText,
  });

  static const int maxLength = 10;

  final TextEditingController controller;
  final bool enabled;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final i18n = AppI18n.of(context);
    final hint = hintText ??
        i18n.t(
          zhHans: '请输入直播间名称',
          zhHant: '請輸入直播間名稱',
          en: 'Enter live room name',
          ja: '配信ルーム名を入力',
          ko: '라이브룸 이름 입력',
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t(
              zhHans: '直播间名称',
              zhHant: '直播間名稱',
              en: 'Live room name',
              ja: '配信ルーム名',
              ko: '라이브룸 이름',
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.subText,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled,
            cursorColor: GroupLiveOnlineLiveScaffold.primaryBlue,
            maxLength: maxLength,
            style: TextStyle(fontSize: 15, color: cs.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 15,
                color: cs.hint,
              ),
              filled: true,
              fillColor: cs.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class GroupLiveDescriptionField extends StatelessWidget {
  const GroupLiveDescriptionField({
    super.key,
    required this.controller,
    required this.enabled,
    this.hintText,
  });

  static const int maxLength = 30;

  final TextEditingController controller;
  final bool enabled;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final cs = GroupLivePageColors.of(context);
    final i18n = AppI18n.of(context);
    final hint = hintText ??
        i18n.t(
          zhHans: '选填，最多 30 字',
          zhHant: '選填，最多 30 字',
          en: 'Optional, up to 30 characters',
          ja: '任意、30文字以内',
          ko: '선택, 최대 30자',
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t(
              zhHans: '描述',
              zhHant: '描述',
              en: 'Description',
              ja: '説明',
              ko: '설명',
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.subText,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled,
            cursorColor: GroupLiveOnlineLiveScaffold.primaryBlue,
            maxLength: maxLength,
            style: TextStyle(fontSize: 15, color: cs.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 15,
                color: cs.hint,
              ),
              filled: true,
              fillColor: cs.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
