import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  setUp(() {
    ConversationPinSyncService.debugResetTestHooks();
    ConversationPinSyncService.debugAccountScopeOverride = 'pin_test_user';
    ConversationPinSyncService.debugSkipPersistAndUiForTest = true;
    ConversationPinSyncService.instance.clearSession();
    ConversationPinSyncService.instance.debugReplacePinnedIdsForTest(
      const <String>[],
    );
  });

  tearDown(() {
    ConversationPinSyncService.debugResetTestHooks();
    ConversationPinSyncService.instance.clearSession();
  });

  test('TIM fail does not follow-write backend and keeps local set', () async {
    final timCalls = <({String id, bool pinned})>[];

    ConversationPinSyncService.debugPinConversationOverride =
        (conversationID, isPinned) async {
      timCalls.add((id: conversationID, pinned: isPinned));
      return false;
    };

    final conversation = V2TimConversation(
      conversationID: 'c2c_u1',
      type: 1,
      userID: 'u1',
      isPinned: false,
    );

    final result = await ConversationPinService.instance.setPinned(
      conversation: conversation,
      isPinned: true,
      source: 'test_tim_fail',
    );

    expect(result.sdkOk, isFalse);
    expect(result.applied, isFalse);
    expect(result.isPinned, isFalse);
    expect(timCalls, hasLength(1));
    expect(timCalls.single.id, 'c2c_u1');
    expect(timCalls.single.pinned, isTrue);
    expect(
      ConversationPinSyncService.instance.isPinnedConversationId('c2c_u1'),
      isFalse,
    );
  });

  test('TIM success applies without a second backend command', () async {
    final order = <String>[];
    ConversationPinSyncService.debugPinConversationOverride =
        (conversationID, isPinned) async {
      order.add('tim:$conversationID:$isPinned');
      return true;
    };

    final conversation = V2TimConversation(
      conversationID: 'c2c_u2',
      type: 1,
      userID: 'u2',
      isPinned: false,
    );

    final result = await ConversationPinService.instance.setPinned(
      conversation: conversation,
      isPinned: true,
      source: 'test_tim_ok',
    );

    expect(result.sdkOk, isTrue);
    expect(result.applied, isTrue);
    expect(result.isPinned, isTrue);
    expect(order, <String>[
      'tim:c2c_u2:true',
    ]);
    expect(
      ConversationPinSyncService.instance.isPinnedConversationId('c2c_u2'),
      isTrue,
    );
  });

  test('unpin TIM success updates projection without backend follow-write',
      () async {
    ConversationPinSyncService.instance.debugReplacePinnedIdsForTest(
      const <String>['group_g1'],
    );
    ConversationPinSyncService.debugPinConversationOverride =
        (conversationID, isPinned) async => true;

    final conversation = V2TimConversation(
      conversationID: 'group_g1',
      type: 2,
      groupID: 'g1',
      isPinned: true,
    );

    final result = await ConversationPinService.instance.setPinned(
      conversation: conversation,
      isPinned: false,
      source: 'test_unpin',
    );

    expect(result.applied, isTrue);
    expect(result.sdkOk, isTrue);
    expect(result.isPinned, isFalse);
    expect(
      ConversationPinSyncService.instance.isPinnedConversationId('group_g1'),
      isFalse,
    );
  });

  test('late TIM result from previous session cannot update pin state',
      () async {
    final timResult = Completer<bool>();
    ConversationPinSyncService.debugPinConversationOverride =
        (conversationID, isPinned) => timResult.future;

    final pending = ConversationPinService.instance.setPinned(
      conversation: V2TimConversation(
        conversationID: 'c2c_late',
        type: 1,
        userID: 'late',
        isPinned: false,
      ),
      isPinned: true,
      source: 'test_stale_session',
    );
    SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
    await ConversationPinSyncService.instance.clearSession();
    timResult.complete(true);

    final result = await pending;
    expect(result.applied, isFalse);
    expect(
      ConversationPinSyncService.instance.isPinnedConversationId('c2c_late'),
      isFalse,
    );
  });

  test('a cross-device SDK unpin replaces the old cached pin', () {
    final service = ConversationPinSyncService.instance;
    service.debugReplacePinnedIdsForTest(['c2c_peer']);
    final sdkRow = V2TimConversation(
        conversationID: 'c2c_peer', type: 1, userID: 'peer', isPinned: false);
    service.applySdkPinProjection(sdkRow);
    expect(sdkRow.isPinned, isFalse);
    expect(service.isPinnedConversationId('c2c_peer'), isFalse);
    sdkRow.isPinned = true;
    service.applySdkPinProjection(sdkRow);
    expect(service.isPinnedConversationId('c2c_peer'), isTrue);
  });

  test('only an unfinished local command can overlay the SDK pin', () async {
    final result = Completer<bool>();
    ConversationPinSyncService.debugPinConversationOverride =
        (_, __) => result.future;
    final service = ConversationPinSyncService.instance;
    final pending = ConversationPinService.instance.setPinned(
        conversation: V2TimConversation(
            conversationID: 'c2c_peer',
            type: 1,
            userID: 'peer',
            isPinned: false),
        isPinned: true,
        source: 'pending_projection_test');
    await Future<void>.delayed(Duration.zero);
    final oldCallback = V2TimConversation(
        conversationID: 'c2c_peer', type: 1, userID: 'peer', isPinned: false);
    service.applySdkPinProjection(oldCallback);
    expect(oldCallback.isPinned, isTrue);
    final sameSuffixGroup = V2TimConversation(
        conversationID: 'group_peer',
        type: 2,
        groupID: 'peer',
        isPinned: false);
    service.applySdkPinProjection(sameSuffixGroup);
    expect(sameSuffixGroup.isPinned, isFalse);
    result.complete(true);
    await pending;
    final crossDevice = V2TimConversation(
        conversationID: 'c2c_peer', type: 1, userID: 'peer', isPinned: false);
    service.applySdkPinProjection(crossDevice);
    expect(crossDevice.isPinned, isFalse);
  });

  test('opposite taps serialize and a failed pin does not become confirmed',
      () async {
    final result = Completer<bool>();
    final calls = <bool>[];
    ConversationPinSyncService.debugPinConversationOverride = (_, value) {
      calls.add(value);
      return result.future;
    };
    V2TimConversation row() => V2TimConversation(
        conversationID: 'c2c_fast', type: 1, userID: 'fast', isPinned: false);
    final first = ConversationPinService.instance
        .setPinned(conversation: row(), isPinned: true);
    final second = ConversationPinService.instance
        .setPinned(conversation: row(), isPinned: false);
    expect(calls, [true]);
    result.complete(false);
    await first;
    expect((await second).isPinned, isFalse);
    expect(calls, [true]);
    expect(
        ConversationPinSyncService.instance.isPinnedConversationId('c2c_fast'),
        isFalse);
  });

  test('a pinned archived SDK row can unpin without a loaded main-list row',
      () async {
    final calls = <bool>[];
    ConversationPinSyncService.debugPinConversationOverride = (_, value) async {
      calls.add(value);
      return true;
    };
    final result = await ConversationPinService.instance.togglePinned(
        conversation: V2TimConversation(
            conversationID: 'c2c_archived',
            type: 1,
            userID: 'archived',
            isPinned: true));
    expect(calls, [false]);
    expect(result.isPinned, isFalse);
    expect(result.applied, isTrue);
  });
}
