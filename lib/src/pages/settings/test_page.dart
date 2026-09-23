import 'dart:async';
import '../../api/lottery_number_mappings.dart';
import '../../api/lottery_live_api.dart';
import 'lottery_reveal_state.dart';
import 'lottery_back_gesture.dart';
import 'lottery_scratch_cover.dart';

import 'package:flutter/material.dart';
import 'lottery_theme.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_settings_tile.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';

part 'lottery_dashboard.dart';
part 'lottery_card_countdown.dart';

const _red = Color(0xFFEF2F4E);
const _blue = Color(0xFF007AFF);
const _green = Color(0xFF00B25E);

enum _WaveColor {
  red('红', _red),
  blue('蓝', _blue),
  green('绿', _green);

  const _WaveColor(this.label, this.color);
  final String label;
  final Color color;
}

// Demo candidate mapping; replace with the configured rule table on API hookup.
_WaveColor _numberWave(String number) {
  final n = int.parse(number);
  const red = {1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46};
  const blue = {3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48};
  return red.contains(n)
      ? _WaveColor.red
      : blue.contains(n)
          ? _WaveColor.blue
          : _WaveColor.green;
}

class _NumberBall extends StatelessWidget {
  const _NumberBall(this.number, {this.wave, this.size = 32});
  final String number;
  final _WaveColor? wave;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(switch (wave ?? _numberWave(number)) {
              _WaveColor.red => 'assets/lhc/hong.png',
              _WaveColor.blue => 'assets/lhc/lan.png',
              _WaveColor.green => 'assets/lhc/lv.png',
            }),
            fit: BoxFit.contain,
          ),
        ),
        child: Text(number,
            style: TextStyle(
                color: Colors.black,
                fontSize: size * .44,
                fontWeight: FontWeight.w800)),
      );
}

class _MarkSixResult {
  const _MarkSixResult({
    required this.time,
    required this.issue,
    required this.specialNumber,
    required this.zodiac,
    required this.fiveElement,
    required this.waveColor,
    this.attributes,
    this.fullIssue,
  });

  final String time;
  final String issue;
  final int specialNumber;
  final String zodiac;
  final String fiveElement;
  final _WaveColor waveColor;
  final Map<String, dynamic>? attributes;
  final String? fullIssue;

  String get numberText => specialNumber.toString().padLeft(2, '0');
  String get parity =>
      attributes?['parity'] as String? ?? (specialNumber.isOdd ? '单' : '双');
  String get size =>
      attributes?['size'] as String? ?? (specialNumber >= 25 ? '大' : '小');
  String get head => attributes?['head'] as String? ?? '${specialNumber ~/ 10}';
  String get tail => attributes?['tail'] as String? ?? '${specialNumber % 10}';
  String get sumParity =>
      attributes?['sumParity'] as String? ??
      ((specialNumber ~/ 10 + specialNumber % 10).isOdd ? '单' : '双');
}

const _results = [
  _MarkSixResult(
      time: '09-21 17:04',
      issue: '203',
      specialNumber: 48,
      zodiac: '羊',
      fiveElement: '火',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 17:01',
      issue: '202',
      specialNumber: 42,
      zodiac: '牛',
      fiveElement: '金',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 16:59',
      issue: '201',
      specialNumber: 49,
      zodiac: '马',
      fiveElement: '火',
      waveColor: _WaveColor.green),
  _MarkSixResult(
      time: '09-21 16:57',
      issue: '200',
      specialNumber: 27,
      zodiac: '兔',
      fiveElement: '金',
      waveColor: _WaveColor.green),
  _MarkSixResult(
      time: '09-21 16:54',
      issue: '199',
      specialNumber: 9,
      zodiac: '鸡',
      fiveElement: '木',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 16:52',
      issue: '198',
      specialNumber: 49,
      zodiac: '马',
      fiveElement: '火',
      waveColor: _WaveColor.green),
  _MarkSixResult(
      time: '09-21 16:50',
      issue: '197',
      specialNumber: 9,
      zodiac: '鸡',
      fiveElement: '木',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 16:48',
      issue: '196',
      specialNumber: 24,
      zodiac: '鼠',
      fiveElement: '木',
      waveColor: _WaveColor.red),
  _MarkSixResult(
      time: '09-21 16:46',
      issue: '195',
      specialNumber: 48,
      zodiac: '羊',
      fiveElement: '火',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 16:43',
      issue: '194',
      specialNumber: 13,
      zodiac: '龙',
      fiveElement: '金',
      waveColor: _WaveColor.red),
  _MarkSixResult(
      time: '09-21 16:41',
      issue: '193',
      specialNumber: 20,
      zodiac: '猪',
      fiveElement: '土',
      waveColor: _WaveColor.blue),
  _MarkSixResult(
      time: '09-21 16:38',
      issue: '192',
      specialNumber: 10,
      zodiac: '狗',
      fiveElement: '火',
      waveColor: _WaveColor.blue),
];

/// Compact chat preview using the same card and mappings as the full page.
class LotteryLatestPreview extends StatelessWidget {
  const LotteryLatestPreview({super.key, this.gameId});
  final String? gameId;

  @override
  Widget build(BuildContext context) => gameId == null || gameId!.trim().isEmpty
      ? const _LotteryDashboard(previewOnly: true)
      : _ConfiguredLottery(
          key: ValueKey(gameId), machineCode: gameId!, previewOnly: true);
}

class TestPage extends StatelessWidget {
  const TestPage({super.key, this.groupUid, this.gameId});

  final String? groupUid;
  final String? gameId;

  @override
  Widget build(BuildContext context) => LotteryBackGesture(
          child: Scaffold(
        backgroundColor: lotteryThemeColor(
            context, const Color(0xFFF3F8FF), AppTokens.backgroundDark),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 52,
          backgroundColor: lotteryThemeColor(
              context, const Color(0xFFF4F9FF), AppTokens.surfaceDark),
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lotteryThemeColor(
                      context, const Color(0xFFF7FAFF), AppTokens.surfaceDark),
                  lotteryThemeColor(
                      context, const Color(0xFFEAF3FF), AppTokens.surfaceDark),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: lotteryThemeColor(
                      context, const Color(0xFFE8F0FC), AppTokens.borderDark),
                ),
              ),
            ),
          ),
          automaticallyImplyLeading: false,
          leadingWidth: 64,
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),
                  color: const Color(0xFF1976F3),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          titleSpacing: 0,
          centerTitle: true,
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: _Brand(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: gameId == null || gameId!.trim().isEmpty
              ? const _LotteryDashboard()
              : _ConfiguredLottery(key: ValueKey(gameId), machineCode: gameId!),
        ),
      ));
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('京东微信红包',
              style: TextStyle(
                  color: lotteryThemeColor(context, const Color(0xFF17243D),
                      AppTokens.textPrimaryDark),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Text('极速六合彩',
              style: TextStyle(
                  color: lotteryThemeColor(context, const Color(0xFF74839B),
                      AppTokens.textSecondaryDark),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
        ],
      );
}

class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.results});
  final List<_MarkSixResult> results;

  static const _widths = [
    100.0,
    44.0,
    62.0,
    38.0,
    38.0,
    30.0,
    30.0,
    30.0,
    38.0,
    38.0
  ];

  @override
  Widget build(BuildContext context) => Column(children: [
        const _TableRow(
          header: true,
          values: ['时间', '期号', '特', '单双', '大小', '头', '尾', '合', '五行', '波色'],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length > 100 ? 100 : results.length,
            itemBuilder: (context, index) => _ResultRow(result: results[index]),
          ),
        ),
      ]);
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.values, this.header = false});
  final List<String> values;
  final bool header;

  @override
  Widget build(BuildContext context) => Container(
        height: header ? 34 : 36,
        decoration: BoxDecoration(
          color: header
              ? lotteryThemeColor(
                  context, const Color(0xFFEAF3FF), AppTokens.surfaceAltDark)
              : lotteryThemeColor(context, Colors.white, AppTokens.surfaceDark),
          border: Border(
              bottom: BorderSide(
                  color: lotteryThemeColor(
                      context, const Color(0xFFE7EDF6), AppTokens.borderDark),
                  width: .8)),
        ),
        child: Row(
          children: List.generate(
            values.length,
            (index) => Expanded(
              flex: _ResultTable._widths[index].toInt(),
              child: _TableCell(
                width: _ResultTable._widths[index],
                text: values[index],
                header: header,
              ),
            ),
          ),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});
  final _MarkSixResult result;

  Color? _attributeColor(BuildContext context, int index, String value) {
    switch (index) {
      case 3: // 单双
        return switch (value) { '单' => _blue, '双' => _red, _ => null };
      case 4: // 大小
        return switch (value) { '小' => _blue, '大' => _red, _ => null };
      case 8: // 五行
        return switch (value) {
          '金' => lotteryThemeColor(
              context, const Color(0xFF9A6700), const Color(0xFFFFC857)),
          '木' => lotteryThemeColor(
              context, const Color(0xFF008A4A), const Color(0xFF55D99A)),
          '水' => lotteryThemeColor(
              context, const Color(0xFF0066CC), const Color(0xFF76B6FF)),
          '火' => lotteryThemeColor(
              context, const Color(0xFFD72C48), const Color(0xFFFF788A)),
          '土' => lotteryThemeColor(
              context, const Color(0xFF8C5A36), const Color(0xFFD5A678)),
          _ => null,
        };
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = [
      result.time,
      result.issue,
      '${result.numberText}  ${result.zodiac}',
      result.parity,
      result.size,
      result.head,
      result.tail,
      result.sumParity,
      result.fiveElement,
      result.waveColor.label,
    ];
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: lotteryThemeColor(context, Colors.white, AppTokens.surfaceDark),
        border: Border(
            bottom: BorderSide(
                color: lotteryThemeColor(
                    context, const Color(0xFFE7EDF6), AppTokens.borderDark),
                width: .8)),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final colored = index == 2 || index == 9;
          return Expanded(
            flex: _ResultTable._widths[index].toInt(),
            child: index == 2
                ? Container(
                    height: double.infinity,
                    decoration: BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: lotteryThemeColor(
                                    context,
                                    const Color(0xFFE7EDF6),
                                    AppTokens.borderDark),
                                width: .8))),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _NumberBall(result.numberText,
                            wave: result.waveColor, size: 28),
                        const SizedBox(width: 2),
                        Text(result.zodiac,
                            style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  )
                : _TableCell(
                    width: _ResultTable._widths[index],
                    text: values[index],
                    background: colored ? result.waveColor.color : null,
                    textColor: _attributeColor(context, index, values[index]),
                    bold: colored || index == 3 || index == 4 || index == 8,
                  ),
          );
        }),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.width,
    required this.text,
    this.header = false,
    this.background,
    this.textColor,
    this.bold = false,
  });

  final double width;
  final String text;
  final bool header;
  final Color? background;
  final Color? textColor;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
              right: BorderSide(
                  color: lotteryThemeColor(
                      context, const Color(0xFFE7EDF6), AppTokens.borderDark),
                  width: .7)),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: EdgeInsets.symmetric(
                horizontal: background != null || textColor != null ? 5 : 1,
                vertical: background != null || textColor != null ? 4 : 1),
            decoration: header || (background == null && textColor == null)
                ? null
                : BoxDecoration(
                    color: background ?? textColor!.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(6),
                  ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: header
                      ? lotteryThemeColor(context, const Color(0xFF30415D),
                          AppTokens.textPrimaryDark)
                      : background != null
                          ? Colors.white
                          : textColor ??
                              lotteryThemeColor(
                                  context,
                                  const Color(0xFF20242A),
                                  AppTokens.textPrimaryDark),
                  fontSize: 12,
                  fontWeight:
                      header || bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
}
