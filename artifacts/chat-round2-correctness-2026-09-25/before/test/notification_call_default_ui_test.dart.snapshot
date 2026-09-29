import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/notification_settings_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';

void main() {
  testWidgets('call notifications are on without a visible switch',
      (tester) async {
    final settings = LocalSetting(autoLoad: false);
    addTearDown(settings.dispose);
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/me/notification-settings') {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'systemMessageNotificationEnabled': true,
            'callNotificationEnabled': false,
            'notificationDisplayContent': 'show_all',
          },
        ));
        return;
      }
      handler.next(options);
    });
    ApiClient.instance.dio.interceptors.add(interceptor);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(interceptor));

    await tester.pumpWidget(ChangeNotifierProvider<LocalSetting>.value(
      value: settings,
      child: const MaterialApp(home: NotificationSettingsPage()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(RegExp(
          '语音和视频通话通知|Voice and Video Call Notifications')),
      findsNothing,
    );
    expect(
      find.textContaining(RegExp(
          '语音和视频通话用弹窗快捷接听|Quick Answer Popup for Voice and Video Calls')),
      findsOneWidget,
    );
    expect(settings.notifyVoiceVideoCall, isTrue);
  });
}
