import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/chat_cards/red_packet_card.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_open_flow_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an already empty card remains tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RedPacketCard(
            msg: '恭喜发财',
            status: 'finished',
            timeText: '12:00',
            onTap: () => tapped = true,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('已被领完'));
    expect(tapped, isTrue);
  });

  testWidgets('410 empty opens read-only details after claim stops',
      (tester) async {
    var postCount = 0;
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST' &&
          options.path.endsWith('/wallet/red-packet/3525/claim')) {
        postCount++;
        handler.reject(DioError(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 410,
            data: {'code': 'RED_PACKET_EMPTY'},
          ),
          type: DioErrorType.response,
        ));
      } else {
        handler.next(options);
      }
    });
    ApiClient.instance.dio.interceptors.insert(0, interceptor);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(interceptor));

    await tester.pumpWidget(MaterialApp(
      home: RedPacketPreviewPage(
        data: RedPacketOpenPreviewData(
          orderId: '3525',
          packetType: 'LUCKY_GROUP',
          autoClaim: true,
          claimResultBuilder: (context, outcome) => Scaffold(
            body: Center(child: Text('详情：${outcome?.status.name}')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();

    expect(postCount, 1);
    expect(find.text('详情：empty'), findsOneWidget);
  });
}
