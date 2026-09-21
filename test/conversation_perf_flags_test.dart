import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';

void main() {
  final originalTargetPlatform = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalTargetPlatform;
  });

  test('hydrates during scroll on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(ConversationPerfFlags.virtualHydrateOnlyOnScrollSettle, isFalse);
  });

  test('hydrates during scroll on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(ConversationPerfFlags.virtualHydrateOnlyOnScrollSettle, isFalse);
  });

  test('row retention is off by default and switches cache extent', () {
    expect(ConversationPerfFlags.conversationRowRetentionEnabled, isFalse);
    expect(ConversationPerfFlags.conversationRowRetentionLruLimit, 20);
    final baseline = ConversationPerfFlags.conversationFeedCacheExtent;
    ConversationPerfFlags.debugConversationRowRetentionOverride = true;
    addTearDown(() {
      ConversationPerfFlags.debugConversationRowRetentionOverride = null;
    });
    expect(ConversationPerfFlags.conversationRowRetentionEnabled, isTrue);
    expect(
      ConversationPerfFlags.conversationFeedCacheExtent,
      greaterThan(baseline),
    );
  });
}
