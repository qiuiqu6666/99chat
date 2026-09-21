import 'dart:async';
import 'package:flutter/material.dart';

/// Current round is independent of the last drawn result shown on the card.
class LotteryRoundStatus extends StatefulWidget {
  const LotteryRoundStatus(
      {super.key,
      required this.round,
      required this.now,
      required this.formatTime,
      this.stale = false});
  final Map<String, dynamic> round;
  final DateTime Function() now;
  final String Function(int) formatTime;
  final bool stale;
  @override
  State<LotteryRoundStatus> createState() => _LotteryRoundStatusState();
}

class _LotteryRoundStatusState extends State<LotteryRoundStatus> {
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.round;
    final now = widget.now().millisecondsSinceEpoch;
    final close = row['closeAt'] as int?;
    final open = row['openAt'] as int?;
    final closed = row['closedAt'] as int?;
    final status = row['status'];
    String countdown(int target) {
      final seconds = ((target - now) / 1000).ceil().clamp(0, 999999999);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
    }

    // Reaching the scheduled time is not proof of a server-side transition.
    final label = switch (status) {
      'drawn' => '已开奖',
      'closed' => '已封盘 · 等待开奖',
      'open' when open != null && now < open => '待开盘 · 距开盘 ${countdown(open)}',
      'open' when close != null && now < close =>
        '开盘中 · 距封盘 ${countdown(close)}',
      'open' when close != null => '封盘时间已到 · 等待确认',
      'open' => '开盘中 · 封盘时间未提供',
      _ => '状态待更新',
    };
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('第 ${row['issueLabel'] ?? row['issue']} 期 · $label',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status == 'open'
                      ? const Color(0xFF1677FF)
                      : const Color(0xFFF02F4B))),
          const SizedBox(height: 3),
          Wrap(spacing: 10, runSpacing: 2, children: [
            if (open != null)
              Text('开盘 ${widget.formatTime(open)}', style: _timeStyle),
            if (closed != null || close != null)
              Text(
                  '${closed != null ? '已封盘' : '封盘'} ${widget.formatTime(closed ?? close!)}',
                  style: _timeStyle),
            if (widget.stale) const Text('连接中断 · 状态待同步', style: _timeStyle),
          ]),
        ]);
  }

  static const _timeStyle = TextStyle(fontSize: 10, color: Color(0xFF7D8797));
}
