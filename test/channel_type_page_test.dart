import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/channel_type_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('private channel keeps link subscriptions available when saved',
      (tester) async {
    final dio = ApiClient.instance.dio;
    final oldInterceptors = dio.interceptors.toList();
    dio.interceptors.clear();
    Map<String, dynamic>? saved;
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        dynamic data;
        if (request.path.endsWith('/join-options')) {
          if (request.method == 'PUT') {
            saved = Map<String, dynamic>.from(request.data as Map);
            data = saved;
          } else {
            data = {
              'applyJoinOption': 'free_access',
              'inviteJoinOption': 'free_access',
              'allowJoinByQrCode': true,
              'allowJoinByAlias': true,
            };
          }
        } else if (request.path.endsWith('/api/v1/platform/contact')) {
          data = {'website': 'https://99chat.example'};
        } else {
          handler.reject(DioError(requestOptions: request));
          return;
        }
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'ok': true, 'data': data}));
      },
    ));
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(oldInterceptors);
    });

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('zh', 'CN'),
      supportedLocales: [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ChannelTypePage(groupId: '@TGS#_@TGS#abc', groupName: '测试频道'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('公开'), findsOneWidget);
    expect(find.text('私密'), findsOneWidget);
    expect(tester.widget<Text>(find.text('公开')).style?.fontSize, 16);
    expect(tester.widget<Text>(find.text('公开')).style?.fontWeight,
        FontWeight.normal);
    expect(find.text('公共频道可以在搜索中找到，任何人都可以加入'), findsOneWidget);
    expect(find.text('任何人可以通过点击这个链接加入你的频道'), findsOneWidget);
    expect(find.textContaining('99chat.example'), findsOneWidget);
    await tester.tap(find.text('私密'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved?['allowJoinByAlias'], false);
    expect(saved?['allowJoinByQrCode'], true);
    expect(saved?['applyJoinOption'], 'free_access');
  });
}
