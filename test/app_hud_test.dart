import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';

const _barrier = Key('app_hud_barrier');
const _indicator = Key('app_hud_indicator');

Widget _host() => MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: SizedBox.expand()),
    );

double _indicatorOpacity(WidgetTester tester) {
  final opacity = tester.widget<AnimatedOpacity>(
    find.ancestor(
      of: find.byKey(_indicator),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  return opacity.opacity;
}

void main() {
  tearDown(AppHud.forceDismiss);

  testWidgets('begin 立即挂屏障，showDelay 前不显示转圈', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump();

    expect(AppHud.isActive, isTrue);
    expect(find.byKey(_barrier), findsOneWidget);
    expect(find.byKey(_indicator), findsOneWidget);
    expect(_indicatorOpacity(tester), 0);

    await tester.pump(AppHud.defaultShowDelay);
    await tester.pump();
    expect(_indicatorOpacity(tester), 1);

    final endFuture = session.end();
    await tester.pump(AppHud.defaultMinVisible);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await endFuture;
    await tester.pump();
    expect(AppHud.isActive, isFalse);
    expect(find.byKey(_barrier), findsNothing);
  });

  testWidgets('showDelay 内 end：不闪转圈且屏障立刻移除', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_indicatorOpacity(tester), 0);

    final endFuture = session.end();
    await tester.pump();
    await endFuture;
    await tester.pump();

    expect(AppHud.isActive, isFalse);
    expect(find.byKey(_barrier), findsNothing);
    expect(find.byKey(_indicator), findsNothing);
  });

  testWidgets('已显示后 end：至少停留 minVisible 再收起', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump(AppHud.defaultShowDelay);
    await tester.pump();
    expect(_indicatorOpacity(tester), 1);

    final endFuture = session.end();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_barrier), findsOneWidget);
    expect(_indicatorOpacity(tester), 1);

    await tester.pump(AppHud.defaultMinVisible);
    await tester.pump();
    expect(_indicatorOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await endFuture;
    await tester.pump();

    expect(AppHud.isActive, isFalse);
    expect(find.byKey(_barrier), findsNothing);
  });

  testWidgets('timeout 后自动收起', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin(timeout: const Duration(seconds: 1));
    await tester.pump(AppHud.defaultShowDelay);
    await tester.pump();
    expect(find.byKey(_barrier), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(AppHud.isActive, isFalse);
    expect(session.isEnded, isTrue);
    expect(find.byKey(_barrier), findsNothing);
  });

  testWidgets('settleActive 无会话时同步 no-op；有会话时等同 end', (tester) async {
    await tester.pumpWidget(_host());
    await AppHud.settleActive();
    expect(AppHud.isActive, isFalse);

    final session = AppHud.begin();
    await tester.pump(const Duration(milliseconds: 20));
    final settle = AppHud.settleActive();
    await tester.pump();
    await settle;
    await tester.pump();

    expect(session.isEnded, isTrue);
    expect(AppHud.isActive, isFalse);
    expect(find.byKey(_barrier), findsNothing);
  });

  testWidgets('end 幂等：重复调用不抛错', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump(const Duration(milliseconds: 20));
    final first = session.end();
    final second = session.end();
    await tester.pump();
    await first;
    await second;
    await session.end();
    await tester.pump();
    expect(AppHud.isActive, isFalse);
  });

  testWidgets('forceDismiss 立即移除且旧 session 变为 ended', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump(AppHud.defaultShowDelay);
    await tester.pump();
    expect(find.byKey(_barrier), findsOneWidget);

    AppHud.forceDismiss();
    await tester.pump();

    expect(AppHud.isActive, isFalse);
    expect(session.isEnded, isTrue);
    expect(find.byKey(_barrier), findsNothing);
    await session.end();
  });

  testWidgets('重复 begin：新会话覆盖旧会话，仅一个屏障', (tester) async {
    await tester.pumpWidget(_host());
    final first = AppHud.begin();
    await tester.pump(const Duration(milliseconds: 20));
    final second = AppHud.begin();
    await tester.pump();

    expect(first.isEnded, isTrue);
    expect(second.isEnded, isFalse);
    expect(find.byKey(_barrier), findsOneWidget);

    await second.end();
    await tester.pump();
    expect(find.byKey(_barrier), findsNothing);
  });

  testWidgets('屏障拦截点击', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('tap'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('tap'));
    expect(taps, 1);

    final session = AppHud.begin();
    await tester.pump();
    await tester.tap(find.text('tap'), warnIfMissed: false);
    expect(taps, 1);

    final endFuture = session.end();
    await tester.pump();
    await endFuture;
    await tester.pump();
    await tester.tap(find.text('tap'));
    expect(taps, 2);
  });

  testWidgets('无 Overlay 时 begin 返回空会话，end 安全', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final session = AppHud.begin();
    expect(AppHud.isActive, isFalse);
    expect(session.isEnded, isTrue);
    await session.end();
    await AppHud.settleActive();
  });

  testWidgets('转圈为 CupertinoActivityIndicator', (tester) async {
    await tester.pumpWidget(_host());
    final session = AppHud.begin();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is CupertinoActivityIndicator && w.key == _indicator,
      ),
      findsOneWidget,
    );
    final endFuture = session.end();
    await tester.pump();
    await endFuture;
    await tester.pump();
  });
}
