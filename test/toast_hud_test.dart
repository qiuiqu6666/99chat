import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

Widget _host() => MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: SizedBox.expand()),
    );

void main() {
  tearDown(() {
    AppHud.forceDismiss();
    AppDialog.hideNotice();
  });

  testWidgets('无 HUD 时 toast 同步展示', (tester) async {
    await tester.pumpWidget(_host());
    ToastUtils.toast('提示A');
    await tester.pump();
    expect(find.text('提示A'), findsOneWidget);
    // 让 1.8s 自动收起的定时器走完，避免 pending timer。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('HUD 活跃时 toast 延后到结算之后', (tester) async {
    await tester.pumpWidget(_host());
    AppHud.begin();
    await tester.pump(const Duration(milliseconds: 20));

    // toast 触发 settleActive；showDelay 内 HUD 尚未显示，直接移除，toast 随即出现。
    ToastUtils.toast('提示B');
    expect(find.text('提示B'), findsNothing);
    await tester.pump();
    await tester.pump();
    expect(AppHud.isActive, isFalse);
    expect(find.text('提示B'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('HUD 已显示时 toast 等满 minVisible 才出现', (tester) async {
    await tester.pumpWidget(_host());
    AppHud.begin();
    await tester.pump(AppHud.defaultShowDelay);
    await tester.pump();

    ToastUtils.toast('提示C');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('提示C'), findsNothing);
    expect(AppHud.isActive, isTrue);

    await tester.pump(AppHud.defaultMinVisible);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump();
    expect(AppHud.isActive, isFalse);
    expect(find.text('提示C'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
