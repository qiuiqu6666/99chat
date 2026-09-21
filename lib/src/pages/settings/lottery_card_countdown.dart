part of 'test_page.dart';

class _LotteryCardCountdown extends StatefulWidget {
  const _LotteryCardCountdown({required this.round, required this.now});
  final Map<String, dynamic> round;
  final DateTime Function() now;
  @override
  State<_LotteryCardCountdown> createState() => _LotteryCardCountdownState();
}

class _LotteryCardCountdownState extends State<_LotteryCardCountdown> {
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
    final status = widget.round['status'];
    final closeAt = widget.round['closeAt'];
    String label = switch (status) {
      'open' => '开盘中',
      'closed' => '已封盘',
      'drawn' => '已开奖',
      _ => '状态待更新',
    };
    if (status == 'open' && closeAt is int) {
      final remaining = closeAt - widget.now().millisecondsSinceEpoch;
      if (remaining <= 0) {
        label = '封盘待确认';
      } else {
        final seconds = (remaining / 1000).ceil();
        String two(int n) => n.toString().padLeft(2, '0');
        final time = '${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
        label = '距封盘 ${seconds >= 3600 ? '${two(seconds ~/ 3600)}:' : ''}$time';
      }
    }
    return Text(label,
        key: const ValueKey('lottery-current-status'),
        style: TextStyle(fontSize: 11, color: status == 'open' ? _blue : _red));
  }
}
