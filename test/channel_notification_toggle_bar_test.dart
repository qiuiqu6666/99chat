import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/channel_notification_toggle_bar.dart';

void main() {
  testWidgets('subscriber switches notification status without a mute warning',
      (tester) async {
    var muted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        return ChannelNotificationToggleBar(
          muted: muted,
          busy: false,
          onTap: () => setState(() => muted = !muted),
        );
      })),
    ));

    expect(find.text('Receive notifications'), findsOneWidget);
    expect(find.text('You have been muted'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('channel-notification-toggle')));
    await tester.pump();
    expect(find.text('Muted'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('channel-notification-toggle')));
    await tester.pump();
    expect(find.text('Receive notifications'), findsOneWidget);
  });
}
