import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class _Theme extends ChangeNotifier implements DefaultThemeData {
  @override
  TUITheme get theme => DefTheme.getTheme(ThemeType.blue);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      '10k AI messages stay lazy and search reaches an unbuilt old message',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final errorHandler = FlutterError.onError;
    TIMUIKitCore.getInstance();
    FlutterError.onError = errorHandler;
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'hasMore': false,
          'items': [
            for (var i = 0; i < 10000; i++)
              {
                'id': '$i',
                'role': 'user',
                'content': i == 0 ? 'oldest-needle' : 'Message $i',
                'status': 'complete',
                'capability': 'chat',
                'createdAt': 1718452800000,
              }
          ]
        }
      }));
    }));
    try {
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<DefaultThemeData>(create: (_) => _Theme()),
        ChangeNotifierProvider<LoginUserInfo>(create: (_) => LoginUserInfo()),
      ], child: const MaterialApp(home: AiAssistantPage())));
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      final bubbles = find
          .byWidgetPredicate((w) => w.runtimeType.toString() == '_UserBubble');
      expect(bubbles.evaluate().length, inInclusiveRange(1, 40));
      expect(find.text('oldest-needle'), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search this chat'), 'oldest-needle');
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      expect(bubbles.evaluate().length, lessThan(60));
      expect(
          find.byWidgetPredicate((w) =>
              w.runtimeType.toString() == '_UserBubble' &&
              (w as dynamic).message.text == 'oldest-needle'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = errorHandler;
      dio.interceptors
        ..clear()
        ..addAll(saved);
    }
  });
}
