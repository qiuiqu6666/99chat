import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'group-cache-ready-fixture';
  const knownId = 'm2CQNL3N5CI';
  final local = GroupLocalStore.instance;
  final membership = GroupMembershipSyncService.instance;
  final session = ChatSessionController.instance;
  late DefaultThemeData theme;
  late LocalSetting settings;
  late PresenceProvider presence;

  V2TimConversation row(String id) => V2TimConversation(
        conversationID: 'group_$id',
        type: 2,
        groupID: id,
        showName: 'SDK $id',
        unreadCount: 2,
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    await membership.clearSession();
    await ApiClient.instance.saveToken('fixture-token', userId: owner);
    local.debugOwnerUserIdOverride = owner;
    await local.clearForOwner(owner);
    await local.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': knownId,
        'groupName': 'Joined group',
        'groupType': 'Public',
        'memberCount': 10,
        'updatedAt': 100,
      }),
    );
    await local.clearSession();
    session.clearSessionProjection();
    session.isFeedScrolling = () => false;
    session.ensureTabStoreBridgeAttached();
    await membership.syncFull(
        reason: 'cache_ready_fixture', startupLocalFirst: true);
    expect(membership.hasSyncedGroupListOnce, isTrue);
    expect(local.isOwnerFullyCached(), isFalse);
    theme = DefaultThemeData();
    settings = LocalSetting(autoLoad: false)..isShowOnlineStatus = false;
    presence = PresenceProvider();
  });
  tearDown(() async {
    presence.dispose();
    settings.dispose();
    theme.dispose();
    await membership.clearSession();
    await local.clearForOwner(owner);
    local.debugOwnerUserIdOverride = null;
    session.clearSessionProjection();
    await ApiClient.instance.clearToken();
  });

  testWidgets(
      'cold SDK groups show before cache load and refilter on readiness',
      (tester) async {
    final handler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = handler);
    final initialVersion = local.cacheHydration.value.version;
    final known = row(knownId);
    final unknown = row('m2UnknownCache');
    expect(membership.shouldShowConversation(known), isTrue);
    membership.markExplicitGroupRemovalForTest(knownId);
    expect(membership.shouldShowConversation(known), isFalse);
    membership.clearExplicitGroupRemovalForTest(knownId);
    membership.flushJoinedGroupsRevisionCoalesceForTest();
    ConversationTabStore.instance
        .setItemsForTest(convType: 2, items: [known, unknown]);
    final page = Conversation(
      conversationController: TIMUIKitConversationController(),
      listScope: ConversationListScope.group,
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: presence),
        ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
      ],
      child: MaterialApp(
        home: HomeTabActivity(
          isActive: true,
          child: TickerMode(enabled: true, child: page),
        ),
      ),
    ));
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.text('SDK $knownId'), findsOneWidget);
    expect(find.text('SDK m2UnknownCache'), findsOneWidget);
    final pageState = tester.state(find.byType(Conversation));
    await tester.runAsync(() async {
      await local.readAll(ownerUserId: owner, caller: 'fixture_hydrate');
    });
    await tester.pump();
    FlutterError.onError = handler;
    expect(local.cacheHydration.value.version, initialVersion + 1);
    expect(local.cacheHydration.value.ownerUserId, owner);
    expect(tester.state(find.byType(Conversation)), same(pageState));
    expect(find.text('SDK $knownId'), findsOneWidget);
    expect(find.text('SDK m2UnknownCache'), findsNothing);
    await tester.runAsync(() => local.readAll(ownerUserId: owner));
    expect(local.cacheHydration.value.version, initialVersion + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    FlutterError.onError = handler;
  });
}
