import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_round_status.dart';

void main() {
  testWidgets('countdown ticks and waits for authoritative closed status',
      (tester) async {
    var now = 100000;
    var round = <String, dynamic>{
      'issueLabel': '004',
      'status': 'open',
      'openAt': 90000,
      'closeAt': 102000
    };
    Future<void> show() => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LotteryRoundStatus(
                round: round,
                now: () => DateTime.fromMillisecondsSinceEpoch(now),
                formatTime: (value) => '$value'))));
    await show();
    expect(find.text('第 004 期 · 开盘中 · 距封盘 00:00:02'), findsOneWidget);
    expect(find.text('开盘 90000'), findsOneWidget);
    expect(find.text('封盘 102000'), findsOneWidget);
    now = 101000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('00:00:01'), findsOneWidget);
    now = 102000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('封盘时间已到 · 等待确认'), findsOneWidget);
    round = {...round, 'status': 'closed', 'closedAt': 102050};
    await show();
    expect(find.text('第 004 期 · 已封盘 · 等待开奖'), findsOneWidget);
    expect(find.text('已封盘 102050'), findsOneWidget);
    round = {...round, 'status': 'drawn'};
    await show();
    expect(find.text('第 004 期 · 已开奖'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing close time is not replaced with a fake countdown',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: LotteryRoundStatus(
            round: const {'issueLabel': '005', 'status': 'open'},
            now: () => DateTime(2026),
            formatTime: (value) => '$value',
            stale: true)));
    expect(find.textContaining('封盘时间未提供'), findsOneWidget);
    expect(find.text('连接中断 · 状态待同步'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
