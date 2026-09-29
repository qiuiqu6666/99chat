import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_folder_chip_bar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';

typedef SdkRows = ({List<V2TimConversation> conversationList, int code});

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  final folders = ConversationFolderStore.instance;
  late DefaultThemeData theme;
  late LocalSetting settings;
  late TIMUIKitConversationController controller;
  void Function(FlutterErrorDetails)? originalHandler;
  final pending = <Completer<SdkRows>>[];
  final requests = <List<String>>[];
  V2TimConversation row(String id) => V2TimConversation(
      conversationID: 'c2c_$id', type: 1, userID: id, showName: id);
  ConversationFolder folder(String id, Iterable<String> members) =>
      ConversationFolder(
          folderId: id,
          name: id,
          sortOrder: 0,
          members: {for (final member in members) 'c2c_$member': null});

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temporary =
        await Directory.systemTemp.createTemp('folder-flash-test-');
    await databaseFactory.setDatabasesPath(temporary.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    originalHandler = FlutterError.onError;
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance
        .saveToken('fixture-token', userId: 'folder-reader');
    ConversationLocalStore.instance.debugOwnerUserId = 'folder-reader';
    await ConversationLocalStore.instance.preloadHistoryClearIndex();
    session.clearSessionProjection();
    session.ensureTabStoreBridgeAttached();
    ConversationListSyncNotifier.instance.clearSession();
    ConversationListSyncNotifier.instance.setHasSyncedOnce(true);
    await folders.ensureLoaded();
    store.setItemsForTest(
        convType: 1, items: List.generate(3000, (i) => row('loaded_$i')));
    pending.clear();
    requests.clear();
    ConversationTabStore.debugFetchByIdsOverride = (ids) {
      requests.add(List.of(ids));
      final result = Completer<SdkRows>();
      pending.add(result);
      return result.future;
    };
    theme = DefaultThemeData();
    settings = LocalSetting(autoLoad: false)..isShowOnlineStatus = false;
    controller = TIMUIKitConversationController();
  });
  tearDown(() async {
    for (final response in pending) {
      if (!response.isCompleted) {
        response.complete((conversationList: <V2TimConversation>[], code: 0));
      }
    }
    ConversationTabStore.debugFetchByIdsOverride = null;
    session.clearSessionProjection();
    await folders.clearSession();
    await ApiClient.instance.clearToken();
    settings.dispose();
    theme.dispose();
    FlutterError.onError = originalHandler;
  });
  tearDownAll(() async {
    ConversationLocalStore.instance.debugOwnerUserId = null;
    await ConversationLocalStore.instance.closeDatabaseForTest();
  });
  Future<void> frame(WidgetTester tester) async {
    FlutterError.onError = originalHandler;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await tester.pump(const Duration(milliseconds: 30));
    FlutterError.onError = originalHandler;
  }

  Future<void> mount(WidgetTester tester, List<ConversationFolder> values,
      {ConversationListScope scope = ConversationListScope.all}) async {
    originalHandler = FlutterError.onError;
    folders.foldersNotifier.value = values;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(create: (_) => PresenceProvider()),
          ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
        ],
        child: MaterialApp(
            home: Conversation(
                conversationController: controller, listScope: scope))));
    FlutterError.onError = originalHandler;
    await frame(tester);
  }

  Future<void> select(WidgetTester tester, String id) async {
    tester
        .widget<ConversationFolderChipBar>(
            find.byType(ConversationFolderChipBar))
        .onSelectFolder(id);
    await frame(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final response in pending) {
      if (!response.isCompleted) {
        response.complete((conversationList: <V2TimConversation>[], code: 0));
      }
    }
    await tester.pump(const Duration(seconds: 3));
    FlutterError.onError = originalHandler;
  }

  testWidgets(
      'follow-up: unselected folder membership and archive refresh badges',
      (tester) async {
    final aggregate = ConversationUnreadAggregate.instance;
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
          conversationList: [
            row('loaded_0')..unreadCount = 3,
            row('loaded_1')..unreadCount = 7
          ],
          isFinished: true,
        );
    try {
      await aggregate
          .readSdkUnreadCountsForIds({'c2c_loaded_0', 'c2c_loaded_1'});
      await mount(tester, [
        folder('a', ['loaded_0']),
        folder('b', ['loaded_1'])
      ]);
      await frame(tester);
      int unread(String id) {
        final bar = tester.widget<ConversationFolderChipBar>(
            find.byType(ConversationFolderChipBar));
        return bar.unreadForFolder(folders.folderById(id)!);
      }

      expect(unread('a'), 3);
      expect(unread('b'), 7);
      folders.foldersNotifier.value = [
        folder('a', ['loaded_0']),
        folder('b', ['loaded_0'])
      ];
      await frame(tester);
      expect(unread('b'), 3);
      archivedConversationC2cIDsNotifier.value = {'c2c_loaded_0'};
      await frame(tester);
      expect(unread('a'), 0);
      expect(unread('b'), 0);
    } finally {
      await close(tester);
      archivedConversationC2cIDsNotifier.value = {};
      aggregate.resetForTest();
    }
  });

  testWidgets(
      'follow-up: filtered content patches preserve snapshots and skip unrelated rows',
      (tester) async {
    try {
      await mount(tester, [
        folder('visible', ['loaded_0', 'loaded_1'])
      ]);
      await select(tester, 'visible');
      final feed = tester
          .widget<ConversationFeedBody>(find.byType(ConversationFeedBody));
      final before = feed.getVisibleConversations();
      store.applyPatches([row('loaded_0')..draftText = 'edited'],
          preserveOrder: true, explicitDraftIds: {'c2c_loaded_0'});
      expect(store.conversationForId('c2c_loaded_0')!.draftText, 'edited');
      final after = feed.getVisibleConversations();
      expect(after.map((r) => r.conversationID),
          before.map((r) => r.conversationID));
      expect(
          after.firstWhere((r) => r.conversationID == 'c2c_loaded_0').draftText,
          'edited');
      expect(
          before
              .firstWhere((r) => r.conversationID == 'c2c_loaded_0')
              .draftText,
          isNull);
      store.applyPatches([row('loaded_2')..draftText = 'outside'],
          preserveOrder: true, explicitDraftIds: {'c2c_loaded_2'});
      expect(feed.getVisibleConversations(), same(after));
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'follow-up: filtered view recovers after missing more than 64 updates',
      (tester) async {
    try {
      await mount(tester, [
        folder('visible', ['loaded_0', 'loaded_1'])
      ]);
      await select(tester, 'visible');
      final feed = tester
          .widget<ConversationFeedBody>(find.byType(ConversationFeedBody));
      store.applyPatches([row('loaded_1')..draftText = 'initial'],
          preserveOrder: true, explicitDraftIds: {'c2c_loaded_1'});
      feed.getVisibleConversations();
      final structureRevision = store.structureRevision;
      for (var i = 0; i < 70; i++) {
        store.applyPatches([row('loaded_1')..draftText = 'update $i'],
            preserveOrder: true, explicitDraftIds: {'c2c_loaded_1'});
      }
      expect(store.structureRevision, structureRevision);
      final rows = feed.getVisibleConversations();
      expect(rows, hasLength(2));
      expect(
          rows.firstWhere((r) => r.conversationID == 'c2c_loaded_1').draftText,
          'update 69');
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'cold folder never claims empty while a later SDK batch is pending',
      (tester) async {
    try {
      await mount(
          tester, [folder('cold', List.generate(201, (i) => 'cold_$i'))]);
      await select(tester, 'cold');
      expect(requests.single.length, 100);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending[0].complete((conversationList: <V2TimConversation>[], code: 0));
      await frame(tester);
      expect(requests.length, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending[1].complete((conversationList: [row('cold_100')], code: 0));
      await frame(tester);
      expect(find.text('cold_100'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      await close(tester);
    }
  });

  for (final awaitingServer in [false, true]) {
    for (final syncEndsFirst in [false, true]) {
      testWidgets(
          'group folder recovers after SDK sync without switching folders (sync first: $syncEndsFirst, awaiting: $awaitingServer)',
          (tester) async {
        originalHandler = FlutterError.onError;
        var requestCount = 0;
        var visibleCount = 0;
        final setPending = awaitingServer
            ? ConversationListSyncNotifier.instance.setAwaitingServerSync
            : ConversationListSyncNotifier.instance.setSyncing;
        try {
          await mount(
              tester,
              [
                ConversationFolder(
                    folderId: 'groups',
                    name: 'groups',
                    sortOrder: 0,
                    members: {'group_late': null})
              ],
              scope: ConversationListScope.group);
          setPending(true);
          await select(tester, 'groups');
          if (syncEndsFirst) {
            setPending(false);
            await frame(tester);
          }
          pending.single
              .complete((conversationList: <V2TimConversation>[], code: 0));
          await frame(tester);
          if (!syncEndsFirst) {
            setPending(false);
            await frame(tester);
          }
          requestCount = requests.length;
          if (requestCount == 2) {
            pending.last.complete((
              conversationList: [
                V2TimConversation(
                    conversationID: 'group_late',
                    groupID: 'late',
                    type: 2,
                    showName: 'late group')
              ],
              code: 0
            ));
            await frame(tester);
            visibleCount = find.text('late group').evaluate().length;
          }
        } finally {
          await close(tester);
        }
        expect(requestCount, 2);
        expect(visibleCount, 1);
      });
    }
  }

  testWidgets('A B A switches reject old completions and repeated taps join',
      (tester) async {
    await mount(tester, [
      folder('A', ['a']),
      folder('B', ['b'])
    ]);
    await select(tester, 'A');
    await select(tester, 'A');
    expect(requests.length, 1);
    await select(tester, 'B');
    await select(tester, 'A');
    expect(requests.length, 3);
    pending[0].complete((conversationList: [row('a')], code: 0));
    pending[1].complete((conversationList: [row('b')], code: 0));
    await frame(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    pending[2].complete((conversationList: [row('a')], code: 0));
    await frame(tester);
    expect(find.text('a'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await select(tester, 'A');
    expect(requests.length, 3);
    expect(find.text('a'), findsOneWidget);
    await close(tester);
  });

  testWidgets('SDK failure shows retry rather than empty or endless loading',
      (tester) async {
    await mount(tester, [
      folder('retry', ['retry_chat'])
    ]);
    await select(tester, 'retry');
    pending[0].complete((conversationList: <V2TimConversation>[], code: 70001));
    await frame(tester);
    final feed = find.byType(ConversationFeedBody);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        find.text(
            tester.widget<ConversationFeedBody>(feed).folderEmptyMessage!),
        findsNothing);
    final retry = find.descendant(of: feed, matching: find.byType(TextButton));
    expect(retry, findsOneWidget);
    await frame(tester);
    expect(requests.length, 1);
    await tester.tap(retry);
    await frame(tester);
    expect(requests.length, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending[1].complete((conversationList: [row('retry_chat')], code: 0));
    await frame(tester);
    expect(find.text('retry_chat'), findsOneWidget);
    await close(tester);
  });

  testWidgets('partial failure retries preserve rows and join pending batches',
      (tester) async {
    try {
      await mount(
          tester, [folder('partial', List.generate(101, (i) => 'partial_$i'))]);
      await select(tester, 'partial');
      pending[0]
          .complete((conversationList: <V2TimConversation>[], code: 70001));
      await frame(tester);
      expect(requests.length, 2);
      await select(tester, 'partial');
      expect(requests.length, 2);
      pending[1].complete((conversationList: [row('partial_100')], code: 0));
      await frame(tester);
      expect(find.text('partial_100'), findsOneWidget);
      await select(tester, 'partial');
      expect(requests.length, 3);
      expect(requests.last.length, 100);
      expect(requests.last, isNot(contains('c2c_partial_100')));
      expect(find.text('partial_100'), findsOneWidget);
      await select(tester, 'partial');
      expect(requests.length, 3);
      pending[2].complete((conversationList: [row('partial_0')], code: 0));
      await frame(tester);
      final feed = tester
          .widget<ConversationFeedBody>(find.byType(ConversationFeedBody));
      expect(feed.getVisibleConversations().map((row) => row.conversationID),
          containsAll(['c2c_partial_0', 'c2c_partial_100']));
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'empty folders need no lookup but unresolved members remain retryable',
      (tester) async {
    await mount(tester, [
      folder('empty', []),
      folder('deleted', ['gone'])
    ]);
    await select(tester, 'empty');
    final emptyText = tester
        .widget<ConversationFeedBody>(find.byType(ConversationFeedBody))
        .folderEmptyMessage!;
    expect(requests, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(emptyText), findsOneWidget);
    await select(tester, 'deleted');
    expect(find.text(emptyText), findsNothing);
    pending[0].complete((conversationList: <V2TimConversation>[], code: 0));
    await frame(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(emptyText), findsNothing);
    await frame(tester);
    expect(requests.length, 1);
    await select(tester, 'deleted');
    expect(requests.length, 2);
    pending.last.complete((conversationList: [row('gone')], code: 0));
    await frame(tester);
    expect(find.text('gone'), findsOneWidget);
    await close(tester);
  });

  testWidgets('membership change retires the old batch even without renaming',
      (tester) async {
    await mount(tester, [
      folder('members', ['old'])
    ]);
    await select(tester, 'members');
    folders.foldersNotifier.value = [
      folder('members', ['new'])
    ];
    await frame(tester);
    expect(requests, [
      ['c2c_old'],
      ['c2c_new']
    ]);
    pending[0].complete((conversationList: [row('old')], code: 0));
    await frame(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('old'), findsNothing);
    pending[1].complete((conversationList: [row('new')], code: 0));
    await frame(tester);
    expect(find.text('new'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
      'large loaded folder appears immediately in committed source order',
      (tester) async {
    final ids = List.generate(1500, (i) => 'loaded_${i * 2}');
    await mount(tester, [folder('loaded', ids)]);
    await select(tester, 'loaded');
    expect(requests, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final feed =
        tester.widget<ConversationFeedBody>(find.byType(ConversationFeedBody));
    expect(feed.getVisibleConversations().map((r) => r.conversationID),
        ids.map((id) => 'c2c_$id'));
    expect(find.text('loaded_0'), findsOneWidget);
    await close(tester);
  });
}
