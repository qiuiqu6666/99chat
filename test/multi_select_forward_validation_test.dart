import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_multi_select_panel.dart';

V2TimMessage _message({int? status}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 100,
    'message_is_from_self': true,
    'message_status': status ?? 2,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
}

void main() {
  tearDown(() {
    AppHud.forceDismiss();
    AppDialog.hideNotice();
  });
  for (final reason in [
    MultiSelectForwardBlockReason.walletCard,
    MultiSelectForwardBlockReason.contactCard
  ]) {
    testWidgets(
        '$reason shows loading before an automatically dismissed notice',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          navigatorKey: AppNavigator.key,
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showMultiSelectForwardBlockedDialog(
                            context, reason),
                        child: const Text('forward')),
                  ))));
      await tester.tap(find.text('forward'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('app_hud_indicator')), findsOneWidget);
      expect(find.textContaining('不支持转发'), findsNothing);
      await tester.pump(AppHud.defaultMinVisible);
      await tester.pump(AppHud.defaultMinVisible);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.byKey(const ValueKey('app_hud_indicator')), findsNothing);
      expect(find.textContaining('不支持转发'), findsOneWidget);
      // Repeated forwarding must neither restart loading nor extend the notice.
      await tester.tap(find.text('forward'));
      await tester.pump();
      expect(AppHud.isActive, isFalse);
      expect(find.textContaining('不支持转发'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('不支持转发'), findsNothing);
      expect(find.text('forward'), findsOneWidget);
      await tester.tap(find.text('forward'));
      await tester.pump();
      expect(AppHud.isActive, isTrue);
      await tester.pump(AppHud.defaultMinVisible);
      await tester.pump(AppHud.defaultMinVisible);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  }
  test('empty multi-select cannot open forwarding', () {
    expect(
      resolveMultiSelectForwardBlockReason(
        messages: const <V2TimMessage>[],
        isVoteMessage: (_) => false,
        isWalletCardMessage: (_) => false,
        isContactCardMessage: (_) => false,
      ),
      MultiSelectForwardBlockReason.noSelection,
    );
  });

  test('failed, wallet, contact card, and vote messages are rejected', () {
    final failed = _message(
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
    );
    final wallet = _message();
    final contact = _message();
    final vote = _message();

    MultiSelectForwardBlockReason? validate(V2TimMessage message) {
      return resolveMultiSelectForwardBlockReason(
        messages: <V2TimMessage>[message],
        isVoteMessage: (value) => identical(value, vote),
        isWalletCardMessage: (value) => identical(value, wallet),
        isContactCardMessage: (value) => identical(value, contact),
      );
    }

    expect(validate(failed), MultiSelectForwardBlockReason.sendFailed);
    expect(validate(wallet), MultiSelectForwardBlockReason.walletCard);
    expect(validate(contact), MultiSelectForwardBlockReason.contactCard);
    expect(validate(vote), MultiSelectForwardBlockReason.vote);
  });

  test('ordinary selected messages can continue to forwarding', () {
    expect(
      resolveMultiSelectForwardBlockReason(
        messages: <V2TimMessage>[_message()],
        isVoteMessage: (_) => false,
        isWalletCardMessage: (_) => false,
        isContactCardMessage: (_) => false,
      ),
      isNull,
    );
  });
}
