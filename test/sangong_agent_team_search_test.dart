import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_team_page.dart';

void main() {
  testWidgets('searches downline locally and retains search across scopes', (
    tester,
  ) async {
    final dio = SangongGameHttp.client;
    final saved = dio.interceptors.toList();
    final scopes = <bool>[];
    dio.interceptors.clear();
    addTearDown(() {
      dio.interceptors
        ..clear()
        ..addAll(saved);
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.path, '/api/v1/me/team/members');
          final direct = request.queryParameters['direct'] == true;
          scopes.add(direct);
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'members': [
                  {'imUserId': 'User-1001', 'nickname': '小明', 'levelNo': 1},
                  if (!direct)
                    {
                      'imUserId': 'User-1002',
                      'nickname': 'Alice',
                      'levelNo': 2,
                    },
                ],
              },
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SangongAgentTeamPage()));
    await tester.pumpAndSettle();
    expect(find.text('共 2 人'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' 小明 ');
    await tester.pump();
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('找到 1 人 / 共 2 人'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' ALI ');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('小明'), findsNothing);

    await tester.enterText(find.byType(TextField), 'user-1002');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(scopes, [false]);

    await tester.tap(find.text('直属下级'));
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的下级'), findsOneWidget);
    expect(find.text('找到 0 人 / 共 1 人'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'user-1002',
    );
    expect(scopes, [false, true]);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('共 1 人'), findsOneWidget);
    expect(find.byTooltip('清空搜索'), findsNothing);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('共 1 人'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
