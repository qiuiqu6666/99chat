import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_profile_pin_bar.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  late ScrollController scroll;
  late TIMUIKitConversationController controller;
  late TUITheme theme;
  final pinCalls = <bool>[];
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    ActiveChatRegistry.instance.reset();
    ConversationPinSyncService.debugResetTestHooks();
    ConversationPinSyncService.instance.clearSession();
    ConversationPinSyncService.debugAccountScopeOverride = 'pin_feed';
    ConversationPinSyncService.debugPinConversationOverride = (_, value) async {
      pinCalls.add(value);
      return true;
    };
    pinCalls.clear();
    session.clearSessionProjection();
    session.isFeedScrolling = () => false;
    session.ensureTabStoreBridgeAttached();
    scroll = ScrollController();
    controller = TIMUIKitConversationController();
    theme = TUITheme();
  });
  tearDown(() {
    scroll.dispose();
    ActiveChatRegistry.instance.reset();
    ConversationPinSyncService.debugResetTestHooks();
    ConversationPinSyncService.instance.clearSession();
    session.isFeedScrolling = null;
    session.clearSessionProjection();
  });

  Widget host({required bool active, int convType = 1}) => MaterialApp(
        home: TickerMode(
          enabled: active,
          child: ConversationFeedBody(
            workEnabled: active,
            isGroupTab: convType == 2,
            previewCacheScopeKey: 'profile-pin-$convType',
            archiveScope: convType == 2
                ? ConversationArchiveScope.group
                : ConversationArchiveScope.c2c,
            theme: theme,
            feedScrollController: scroll,
            scrollPhysics: const ClampingScrollPhysics(),
            controller: controller,
            getVisibleConversations: () {
              return store.conversations;
            },
            getArchivedConversations: () => [],
            conversationTimestampMs: (_) => 0,
            buildConversationRow: (conversation) {
              return Text('${conversation.showName}:${conversation.isPinned}');
            },
            resolveConversationAvatarUrl: (_) {
              return const AvatarImageWarmSource(url: null);
            },
            onArchivedTap: () {},
            onGroupNoticeTap: () {},
            onGroupNoticePin: () async {},
            onGroupNoticeToggleMute: () async {},
            onGroupNoticeDelete: () async {},
          ),
        ),
      );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final pinned in [true, false]) {
      testWidgets(
          '${platform.name} group profile switch applies pin=$pinned with an old snapshot',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final handler = FlutterError.onError;
        try {
          final target = pinRow(2, 'target', 1700000100000, pinned: !pinned);
          store.setItemsForTest(convType: 2, items: [target]);
          ConversationPinSyncService.instance.applySdkPinProjection(target);
          final stale = pinRow(2, 'target', 1700000100000, pinned: pinned);
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
            body: ConversationGroupProfilePinBar(
              groupID: target.groupID!,
              conversation: stale,
              source: 'group_profile',
              isUseCheckedBoxOnWide: false,
            ),
          )));
          FlutterError.onError = handler;
          expect(
              tester
                  .widget<CupertinoSwitch>(find.byType(CupertinoSwitch))
                  .value,
              !pinned);
          await tester.tap(find.byType(CupertinoSwitch));
          await tester.pumpAndSettle();
          FlutterError.onError = handler;
          expect(pinCalls, [pinned]);
          expect(
              store.conversationForId(target.conversationID)!.isPinned, pinned);
          expect(
              tester
                  .widget<CupertinoSwitch>(find.byType(CupertinoSwitch))
                  .value,
              pinned);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = handler;
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  for (final type in [1, 2]) {
    for (final pinned in [true, false]) {
      testWidgets(
          'failed settings type $type pin=$pinned rolls back the live row',
          (tester) async {
        final target = pinRow(type, 'target', 1700000100000, pinned: !pinned);
        final other = pinRow(type, 'other', 1700000200000);
        store.setItemsForTest(
            convType: type, items: pinned ? [other, target] : [target, other]);
        ConversationPinSyncService.instance.applySdkPinProjection(target);
        ConversationPinSyncService.debugPinConversationOverride =
            (_, value) async {
          pinCalls.add(value);
          return false;
        };
        await tester.pumpWidget(host(active: true, convType: type));
        final result = await ConversationPinService.instance.setPinned(
            conversation: pinRow(type, 'target', 1700000100000, pinned: pinned),
            isPinned: pinned,
            source: 'settings_failure');
        await tester.pump();
        expect(result.applied, isFalse);
        expect(result.isPinned, !pinned);
        expect(pinCalls, [pinned]);
        expect(
            store.conversationForId(target.conversationID)!.isPinned, !pinned);
        expect(find.text('target:${!pinned}'), findsOneWidget);
        final targetY = tester.getTopLeft(find.text('target:${!pinned}')).dy;
        final otherY = tester.getTopLeft(find.text('other:false')).dy;
        expect(targetY < otherY, !pinned);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final type in [1, 2]) {
    for (final pinned in [true, false]) {
      for (final stale in [false, true]) {
        testWidgets(
            'settings type $type pin=$pinned stale=$stale updates hidden feed',
            (tester) async {
          final target = pinRow(type, 'target', 1700000100000, pinned: !pinned);
          final other = pinRow(type, 'other', 1700000200000);
          store.clear();
          store.setItemsForTest(
              convType: type,
              items: pinned ? [other, target] : [target, other]);
          ConversationPinSyncService.instance.applySdkPinProjection(target);
          await tester.pumpWidget(host(active: true, convType: type));
          await tester.pump();
          final id = target.conversationID;
          ActiveChatRegistry.instance.enter(id, routeVisible: false);
          await tester.pumpWidget(host(active: false, convType: type));
          final snapshot = stale
              ? pinRow(type, 'target', 1700000100000, pinned: pinned)
              : target;
          final result = await ConversationPinService.instance.setPinned(
              conversation: snapshot,
              isPinned: pinned,
              source: type == 2 ? 'group_profile' : 'c2c_chat_settings');
          expect(result.applied, isTrue);
          expect(pinCalls, [pinned],
              reason: 'an explicit settings command must reach SDK');
          expect(store.conversationForId(id)!.isPinned, pinned);
          session.flushDeferredListUiBeforeChatLeave(conversationId: id);
          ActiveChatRegistry.instance.leave(id);
          await tester.pumpWidget(host(active: true, convType: type));
          await tester.pump();
          expect(find.text('target:$pinned'), findsOneWidget);
          final targetY = tester.getTopLeft(find.text('target:$pinned')).dy;
          final otherY = tester.getTopLeft(find.text('other:false')).dy;
          expect(targetY < otherY, pinned,
              reason:
                  'first returned frame has the new order; store=${store.conversations.map((r) => "${r.showName}:${r.isPinned}:${r.orderkey}").toList()} positions=$targetY/$otherY');
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

V2TimConversation pinRow(int type, String name, int order,
        {bool pinned = false}) =>
    V2TimConversation(
      conversationID: type == 2 ? 'group_@TGS#$name' : 'c2c_$name',
      userID: type == 1 ? name : null,
      groupID: type == 2 ? '@TGS#$name' : null,
      type: type,
      showName: name,
      isPinned: pinned,
      orderkey: order,
      unreadCount: 0,
    );
