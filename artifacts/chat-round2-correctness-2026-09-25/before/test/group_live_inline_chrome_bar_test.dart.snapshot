import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_chrome_bar.dart';

Widget _wrap(Widget body) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: body),
  );
}

void main() {
  testWidgets('live status without media hides watch count and mute',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        GroupLiveInlineChromeBar(
          showLiveStatus: true,
          showMediaButtons: false,
          onClose: () {},
        ),
      ),
    );

    expect(find.text('直播中'), findsOneWidget);
    expect(find.textContaining('观看'), findsNothing);
    expect(find.byTooltip('Mute'), findsNothing);
    expect(
      tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.color == const Color(0xFFFC4F53);
      }),
      isTrue,
    );
  });

  testWidgets('media buttons omit live label and close increments',
      (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      _wrap(
        GroupLiveInlineChromeBar(
          showLiveStatus: false,
          showMediaButtons: true,
          muted: false,
          isFullScreen: false,
          onToggleMute: () {},
          onToggleFullscreen: () {},
          onClose: () => closed++,
        ),
      ),
    );

    expect(find.text('直播中'), findsNothing);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(closed, 1);
  });
}
