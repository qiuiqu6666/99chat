import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers AppNavigator fallback for chat overlay routes', () {
    final source =
        File('lib/src/widgets/forward_pick_pages.dart').readAsStringSync();
    expect(source, contains('appRootNavigator'));
    expect(source, contains('AppNavigator.key.currentState'));
  });

  test('message tooltip resolves root navigator with uikit helper', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_message_tooltip.dart',
    ).readAsStringSync();
    expect(source, contains('resolveUIKitRootNavigator(context)'));
    expect(source, contains('showUIKitOverlayConfirmDialog'));
    expect(
      source,
      isNot(contains('Navigator.maybeOf(context, rootNavigator: true)')),
    );
  });

  test('forward recent list bridges the app session projection', () {
    final registration =
        File('lib/src/widgets/forward_pick_pages.dart').readAsStringSync();
    final recentList = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/recent_conversation_list.dart',
    ).readAsStringSync();

    expect(registration, contains('appForwardRecentConversations'));
    expect(
        registration, contains('ChatSessionController.instance.conversations'));
    expect(recentList, contains('_recentConversations()'));
    expect(recentList, contains('Listenable.merge(listenables)'));
  });

  test('forward recent conversation avatars are circular', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/recent_conversation_list.dart',
    ).readAsStringSync();
    expect(source, contains('borderRadius: BorderRadius.circular(999)'));
  });
}
