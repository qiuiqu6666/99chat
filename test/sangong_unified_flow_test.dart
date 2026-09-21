import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_admin_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/sangong_account_flow_list.dart';

void main() {
  test('explicit tab arrays take priority and contributions are not ledger events', () {
    final report = SangongUserFlowReport.fromJson({'flow': {
      'entries': [
        {'ledgerId': 1, 'type': 'bet_hold', 'amount': -500},
        {'ledgerId': 2, 'type': 'admin_credit', 'amount': 1000},
      ],
      'betFlow': [],
      'bankerFlow': [
        {'ledgerId': 3, 'type': 'settle_banker', 'amount': -169},
        {'ledgerId': 4, 'type': 'settle_win', 'amount': 10},
        {'ledgerId': 5, 'type': 'settle_void', 'amount': 169},
      ],
      'coBankFlow': [
        {'roundId': 88, 'sessionId': 10, 'periodNo': 3,
         'userId': 12, 'imUserId': '100001', 'nickname': '张三',
         'amount': 1000, 'sharePercent': 25.0, 'isMainBanker': false,
         'poolTotal': 4000, 'settledAmount': -169},
        {'roundId': 88, 'isMainBanker': true, 'amount': 3000, 'settledAmount': 0},
      ],
    }});
    expect(report.betEntries, isEmpty);
    expect(report.bankerEntries.single.amount, -169);
    expect(report.counts.banker, 1);
    expect(report.scoreEntries.single.amount, 1000);
    expect(report.coBankFlow.first.sharePercent, 25);
    expect(report.coBankFlow.first.settledAmount, -169);
    expect(report.coBankFlow.last.isMainBanker, isTrue);
    expect(report.coBankFlow.last.settledAmount, 0);
    final empty = SangongUserFlowReport.fromJson({'flow': {
      'entries': [{'type': 'settle_banker', 'amount': 100}],
      'bankerFlow': [], 'coBankFlow': [],
    }});
    expect(empty.bankerEntries, isEmpty);
    expect(empty.coBankFlow, isEmpty);
  });
  test('user-flow request decodes the documented envelope', () async {
    final dio = SangongGameHttp.adminClient;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/api/v1/admin/reports/user-flow');
      expect(request.queryParameters, {'imUserId': '100001'});
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'ok': true,
        'flow': {
          'entries': [
            {
              'ledgerId': 1008,
              'type': 'settle_win',
              'amount': 800,
              'balanceAfter': 10300
            },
            {
              'ledgerId': 2001,
              'type': 'admin_credit',
              'amount': 10000,
              'balanceAfter': 20300
            },
          ],
          'count': 2
        },
      }));
    }));
    try {
      final result =
          await SangongAdminApi.instance.fetchUserFlow(imUserId: ' 100001 ');
      expect(result.betEntries.single.type, 'settle_win');
      expect(result.scoreEntries.single.type, 'admin_credit');
    } finally {
      dio.interceptors
        ..clear()
        ..addAll(saved);
    }
  });

  test(
      'all documented types split correctly; rebates excluded; newest ID first',
      () {
    final types = [
      'bet_hold',
      'bet_recall',
      'bet_void',
      'bet_restart',
      'settle_win',
      'settle_banker',
      'settle_void',
      'admin_credit',
      'credit',
      'admin_debit',
      'debit',
      'user_transfer_in',
      'user_transfer_out',
      'rebate_player',
      'rebate_player_void',
      'unknown'
    ];
    final report = SangongUserFlowReport.fromJson({
      'ok': true,
      'flow': {
        'count': types.length,
        'entries': [
          for (var i = 0; i < types.length; i++)
            {
              'ledgerId': i + 1,
              'type': types[i],
              'amount': i.isEven ? -500 : 800,
              'balanceAfter': 9500,
              'note': '说明',
              'createdAt': '2026-09-16T02:00:00.000+00:00',
            }
        ],
      }
    });
    expect(report.hasUnifiedEntries, isTrue);
    expect(report.entries, hasLength(16));
    expect(report.betEntries, hasLength(7));
    expect(report.scoreEntries, hasLength(6));
    expect(report.counts.bet, 7);
    expect(report.counts.ledger, 6);
    expect(report.bankerEntries.map((entry) => entry.type), ['settle_banker']);
    expect(report.betEntries.first.type, 'settle_void');
    expect(report.betEntries.last.amount, -500);
    expect(report.betEntries.last.createdAt, '2026-09-16T02:00:00.000+00:00');
    expect(report.betEntries.last.sessionId, isNull);
    expect(report.betEntries.last.operator, '');
    expect(report.scoreEntries.map((e) => e.type), contains('admin_credit'));
  });

  testWidgets('settlement shows actual amount and note, never pending status',
      (tester) async {
    final report = SangongUserFlowReport.fromJson({
      'flow': {
        'entries': [
          {
            'ledgerId': 1008,
            'type': 'settle_win',
            'amount': 800,
            'balanceAfter': 10300,
            'refType': 'round',
            'refId': 88,
            'note': '闲赢派彩'
          },
        ]
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SangongAccountFlowList(
                entries: report.betEntries, bets: true))));
    expect(find.text('【时间未提供】 结算派彩:+800 剩余:10300', findRichText: true),
        findsOneWidget);
    expect(find.text('闲赢派彩'), findsOneWidget);
    expect(find.text('待结算'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin transfers render signed amounts and filtered totals',
      (tester) async {
    final report = SangongUserFlowReport.fromJson({
      'flow': {
        'entries': [
          {
            'ledgerId': 2001,
            'type': 'admin_credit',
            'amount': 10000,
            'balanceAfter': 20300,
            'note': '上分',
            'operator': '张三(88)'
          },
          {
            'ledgerId': 2002,
            'type': 'admin_debit',
            'amount': -2000,
            'balanceAfter': 18300,
            'operator': '88'
          },
          {'ledgerId': 2003, 'type': 'rebate_player', 'amount': 999},
        ]
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SangongAccountFlowList(
                entries: report.scoreEntries, bets: false))));
    expect(find.text('本页2笔 总上分:10000 总下分:2000', findRichText: true),
        findsOneWidget);
    expect(find.text('【时间未提供】 下分:-2000 剩余:18300', findRichText: true),
        findsOneWidget);
    expect(find.text('【时间未提供】 上分:+10000 剩余:20300', findRichText: true),
        findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('操作人：张三(88)'), findsOneWidget);
    expect(find.text('操作人：88'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
