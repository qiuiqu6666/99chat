import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/c2c_friend_message_blocked_bar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_input_bar_metrics.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_forbidden_input_bar.dart';

void main() {
  for (final bottom in [0.0, 34.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final blocked in [false, true]) {
        testWidgets('bar height: blocked=$blocked inset=$bottom scale=$scale',
            (tester) async {
          const key = Key('bar');
          await tester.pumpWidget(MaterialApp(home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
              padding: EdgeInsets.only(bottom: bottom),
              viewPadding: EdgeInsets.only(bottom: bottom),
            ),
            child: Align(alignment: Alignment.bottomCenter,
              child: SizedBox(width: 320, key: key,
                child: blocked
                    ? C2cFriendMessageBlockedBar(peerUserId: '', theme: TUITheme())
                    : SafeArea(top: false, child: TIMUIKitForbiddenInputBar(
                        text: '全体禁言中，暂时无法发送消息', theme: TUITheme())),
              ),
            ),
          )));
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byKey(key)).height,
              ChatInputBarMetrics.height + bottom);
          if (blocked) {
            final link = find.descendant(of: find.byType(C2cFriendMessageBlockedBar),
                matching: find.byType(GestureDetector));
            expect(link, findsOneWidget);
            await tester.tap(link);
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
