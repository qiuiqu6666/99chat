import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_claim_action.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_flow_detail_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail waits for claim records before showing packet totals',
      (tester) async {
    RequestInterceptorHandler? pendingClaims;
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/wallet/red-packet/3525') {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 3525,
            'packetType': 'LUCKY_GROUP',
            'packetCount': 5,
            'claimedCount': 5,
            'remainingCount': 0,
            'totalAmount': 100,
            'status': 'FINISHED',
          },
        ));
      } else if (options.path == '/wallet/red-packet/3525/claim-state') {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'claimState': 'EMPTY',
            'packetStatus': 'FINISHED',
            'remainingCount': 0,
          },
        ));
      } else if (options.path == '/wallet/red-packet/3525/claims') {
        pendingClaims = handler;
      } else {
        handler.next(options);
      }
    });
    ApiClient.instance.dio.interceptors.insert(0, interceptor);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(interceptor));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoginUserInfo()),
        ChangeNotifierProvider(create: (_) => DefaultThemeData()),
      ],
      child: const MaterialApp(
        home: RedPacketProjectDetailPage(
          orderId: '3525',
          packetType: 'LUCKY_GROUP',
          autoClaim: false,
          initialClaimOutcome:
              RedPacketClaimOutcome(RedPacketClaimStatus.empty),
          seedPacket: {'packetCount': 5, 'totalAmount': 100},
        ),
      ),
    ));
    for (var i = 0; i < 10 && pendingClaims == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(pendingClaims, isNotNull);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.textContaining('已领取 0/5'), findsNothing);
    expect(find.textContaining('领取记录暂时加载失败'), findsNothing);

    pendingClaims!.resolve(Response<dynamic>(
      requestOptions: RequestOptions(path: '/wallet/red-packet/3525/claims'),
      statusCode: 200,
      data: {'claims': <dynamic>[]},
    ));
    pendingClaims = null;
    for (var i = 0; i < 30 && pendingClaims == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(pendingClaims, isNotNull);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.textContaining('已领取 0/5'), findsNothing);

    pendingClaims!.resolve(Response<dynamic>(
      requestOptions: RequestOptions(path: '/wallet/red-packet/3525/claims'),
      statusCode: 200,
      data: {
        'claims': List.generate(
          5,
          (index) => {'name': '领取者$index', 'amount': 20},
        ),
      },
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('已领取 5/5'), findsOneWidget);
    expect(find.textContaining('领取记录暂时加载失败'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
