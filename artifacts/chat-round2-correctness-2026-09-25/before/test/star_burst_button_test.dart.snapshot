import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/star_burst_button.dart';

void main() {
  testWidgets('star tap gives one light haptic while a toggle is in flight',
      (tester) async {
    final haptics = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final pending = Completer<void>();
    var toggles = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarBurstButton(
          starred: false,
          tooltip: 'Star',
          backgroundColor: Colors.white,
          color: Colors.orange,
          onPressed: () {
            toggles++;
            return pending.future;
          },
        ),
      ),
    ));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(toggles, 1);
    expect(haptics, hasLength(1));
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(toggles, 1);
    expect(haptics, hasLength(1));

    pending.complete();
    await tester.pumpAndSettle();
  });
}
