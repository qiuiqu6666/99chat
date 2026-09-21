import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sync = ConversationSyncService.instance;
  final tabs = ConversationTabStore.instance;
  var restores = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatSessionController.instance.clearSessionProjection();
    tabs.clear();
    sync.resetChatTransitionStateForTesting();
    sync.debugOwnerUserId = 'sdk_bootstrap_owner';
    restores = 0;
    sync.projectionRestoreImplOverride = () async {
      restores++;
    };
  });
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ChatSessionController.instance.clearSessionProjection();
    tabs.clear();
    sync.resetChatTransitionStateForTesting();
  });

  test('login, mounted tabs and post-home reuse each SDK first request',
      () async {
    final release = Completer<void>();
    final calls = <int, int>{};
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls.update(convType, (value) => value + 1, ifAbsent: () => 1);
      await release.future;
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final login = sync.bootstrapTypedFirstScreen(reason: 'login');
    final postHome = sync.bootstrapTypedFirstScreen(reason: 'post_home');
    final view = tabs.ensurePrimed(coldStart: true);
    expect(identical(login, postHome), isTrue);
    expect(tabs.isLoading, isTrue);
    expect(calls, {1: 1, 2: 1});
    release.complete();
    expect(await login, ConversationBootstrapResult.success);
    await postHome;
    await view;
    expect(calls, {1: 1, 2: 1});
    expect(restores, 1);
    expect(tabs.primedForType(1), isTrue);
    expect(tabs.primedForType(2), isTrue);
    expect(tabs.isLoading, isFalse);
  });

  test('concurrent explicit refresh waits for first page then refreshes once',
      () async {
    final release = Completer<void>();
    final calls = <int, int>{};
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls.update(convType, (value) => value + 1, ifAbsent: () => 1);
      if (calls[convType] == 1) await release.future;
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final initial = sync.bootstrapTypedFirstScreen();
    final refresh = sync.bootstrapTypedFirstScreen(reset: true);
    final repeatedRefresh = sync.bootstrapTypedFirstScreen(reset: true);
    release.complete();
    await Future.wait([initial, refresh, repeatedRefresh]);
    expect(calls, {1: 2, 2: 2});
    expect(restores, 2);
  });

  test('retry reads only failed SDK type and accepts successful empty pages',
      () async {
    final calls = <int, int>{};
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls.update(convType, (value) => value + 1, ifAbsent: () => 1);
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: convType == 1 && calls[1] == 1 ? 70001 : 0,
        desc: ''
      );
    };
    expect(await sync.bootstrapTypedFirstScreen(),
        ConversationBootstrapResult.failed);
    expect(tabs.primedForType(1), isFalse);
    expect(tabs.lastLoadFailedForType(1), isTrue);
    expect(tabs.primedForType(2), isTrue);
    expect(await sync.bootstrapTypedFirstScreen(),
        ConversationBootstrapResult.success);
    expect(calls, {1: 2, 2: 1});
    expect(tabs.lastLoadFailedForType(1), isFalse);
  });
  test(
      'controller first screen stays unready after a failed SDK page, then retries',
      () async {
    final controller = ChatSessionController.instance;
    final calls = <int, int>{};
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls.update(convType, (value) => value + 1, ifAbsent: () => 1);
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: convType == 1 && calls[1] == 1 ? 70001 : 0,
        desc: ''
      );
    };
    await controller.restoreProjection(
        reason: ConversationStoreProjectionReason.coldStart);
    expect(controller.firstScreenReady, isFalse);
    expect(tabs.primedForType(2), isTrue);
    await controller.restoreProjection(
        reason: ConversationStoreProjectionReason.coldStart);
    expect(controller.firstScreenReady, isTrue);
    expect(calls, {1: 2, 2: 1});
  });

  test('visible first screen readiness follows only its SDK type', () async {
    final controller = ChatSessionController.instance;
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
              conversationList: <V2TimConversation>[],
              nextSeq: '0',
              isFinished: true,
              code: convType == 1 ? 70001 : 0,
              desc: ''
            );
    await controller.restoreProjection(
        reason: ConversationStoreProjectionReason.coldStart,
        visibleConvType: 1);
    expect(controller.firstScreenReady, isFalse);
    await controller.restoreProjection(
        reason: ConversationStoreProjectionReason.coldStart,
        visibleConvType: 2);
    expect(controller.firstScreenReady, isTrue);
    expect(tabs.primedForType(1), isFalse);
  });
}
