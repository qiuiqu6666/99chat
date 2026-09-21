import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';

const _red = Color(0xFFF02F4B);
const _blue = Color(0xFF1677FF);
const _green = Color(0xFF00B96B);

enum _WaveColor {
  red('红波', _red),
  blue('蓝波', _blue),
  green('绿波', _green);

  const _WaveColor(this.label, this.color);

  final String label;
  final Color color;
}

class _MarkSixResult {
  const _MarkSixResult({
    required this.issue,
    required this.specialNumber,
    required this.zodiac,
    required this.waveColor,
    required this.fiveElement,
  });

  final String issue;
  final int specialNumber;
  final String zodiac;
  final _WaveColor waveColor;
  final String fiveElement;

  String get numberText => specialNumber.toString().padLeft(2, '0');
  String get parity => specialNumber.isOdd ? '单' : '双';
  String get size => specialNumber >= 25 ? '大' : '小';
  String get head => '${specialNumber ~/ 10}头';
  String get tail => '${specialNumber % 10}尾';
  String get sumParity {
    final digitSum = specialNumber ~/ 10 + specialNumber % 10;
    return digitSum.isOdd ? '合单' : '合双';
  }
}

const _results = [
  _MarkSixResult(
      issue: '2026/102',
      specialNumber: 21,
      zodiac: '狗',
      waveColor: _WaveColor.green,
      fiveElement: '金'),
  _MarkSixResult(
      issue: '2026/101',
      specialNumber: 8,
      zodiac: '猪',
      waveColor: _WaveColor.red,
      fiveElement: '木'),
  _MarkSixResult(
      issue: '2026/100',
      specialNumber: 19,
      zodiac: '鼠',
      waveColor: _WaveColor.red,
      fiveElement: '水'),
  _MarkSixResult(
      issue: '2026/099',
      specialNumber: 11,
      zodiac: '猴',
      waveColor: _WaveColor.green,
      fiveElement: '火'),
  _MarkSixResult(
      issue: '2026/098',
      specialNumber: 31,
      zodiac: '鼠',
      waveColor: _WaveColor.blue,
      fiveElement: '土'),
];

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final latest = _results.first;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: AppTokens.accent,
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        titleSpacing: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _Brand(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _LatestResult(result: latest),
                const SizedBox(height: 12),
                const _ResultHistory(results: _results),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB78316), width: 1.5),
          ),
          child: const Icon(Icons.spa_rounded, color: Color(0xFFD3A033)),
        ),
        const SizedBox(width: 9),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('西湖娱乐城',
                style: TextStyle(
                    color: Color(0xFFB47A0A),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            Text('WEST LAKE ENTERTAINMENT CITY',
                style: TextStyle(
                    color: Color(0xFF966D1B), fontSize: 7, letterSpacing: .4)),
          ],
        ),
      ]);
}

class _LatestResult extends StatelessWidget {
  const _LatestResult({required this.result});

  final _MarkSixResult result;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('最新开奖第${result.issue}期',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          Center(child: _SpecialNumber(result: result)),
          const SizedBox(height: 24),
          _AttributeGrid(result: result),
        ]),
      );
}

class _SpecialNumber extends StatelessWidget {
  const _SpecialNumber({required this.result});

  final _MarkSixResult result;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('特码',
            style: TextStyle(color: Color(0xFF7B8493), fontSize: 14)),
        const SizedBox(height: 9),
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: result.waveColor.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: result.waveColor.color.withValues(alpha: .25),
                  blurRadius: 12,
                  offset: const Offset(0, 5)),
            ],
          ),
          child: Text(result.numberText,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w700)),
        ),
      ]);
}

class _AttributeGrid extends StatelessWidget {
  const _AttributeGrid({required this.result});

  final _MarkSixResult result;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('生肖', result.zodiac, const Color(0xFF8B5CF6)),
      ('单双', result.parity, const Color(0xFF2563EB)),
      ('大小', result.size, const Color(0xFFF59E0B)),
      ('头数', result.head, const Color(0xFF0EA5E9)),
      ('尾数', result.tail, const Color(0xFF14B8A6)),
      ('合单双', result.sumParity, const Color(0xFFEC4899)),
      ('五行', result.fiveElement, const Color(0xFFD18C16)),
      ('波色', result.waveColor.label, result.waveColor.color),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 430 ? 4 : 3;
      const spacing = 10.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: items
            .map((item) => SizedBox(
                  width: width,
                  child: _AttributeTile(
                      label: item.$1, value: item.$2, color: item.$3),
                ))
            .toList(),
      );
    });
  }
}

class _AttributeTile extends StatelessWidget {
  const _AttributeTile(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF7B8493), fontSize: 12)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _ResultHistory extends StatelessWidget {
  const _ResultHistory({required this.results});

  final List<_MarkSixResult> results;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('开奖记录',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ...results.map((result) => _HistoryItem(result: result)),
        ]),
      );
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.result});

  final _MarkSixResult result;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E9EE)),
        ),
        child: Column(children: [
          Row(children: [
            Text('第${result.issue}期',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: result.waveColor.color, shape: BoxShape.circle),
              child: Text(result.numberText,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _HistoryTag('生肖', result.zodiac),
            _HistoryTag('单双', result.parity),
            _HistoryTag('大小', result.size),
            _HistoryTag('头数', result.head),
            _HistoryTag('尾数', result.tail),
            _HistoryTag('合单双', result.sumParity),
            _HistoryTag('五行', result.fiveElement),
            _HistoryTag('波色', result.waveColor.label,
                color: result.waveColor.color),
          ]),
        ]),
      );
}

class _HistoryTag extends StatelessWidget {
  const _HistoryTag(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? const Color(0xFF3C4658);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: foreground.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label $value',
          style: TextStyle(color: foreground, fontSize: 12)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: child,
      );
}
