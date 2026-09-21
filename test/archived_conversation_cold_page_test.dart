import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation archivedRow(String id) => V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.substring(4),
    showName: 'Cold archive contact',
    unreadCount: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'cold-archive-widget-owner';
  const id = 'c2c_cold_archive_contact';
  final local = ConversationLocalStore.instance;
  late DefaultThemeData theme;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    // Match the production account boundary: deleting SQLite fixtures alone
    // leaves Coordinator's previous same-owner snapshot/idempotency state.
    ConversationMutationShadowBridge.instance.clearSession();
    await ApiClient.instance.saveToken('fixture-token', userId: owner);
    local.debugOwnerUserId = owner;
    ConversationLocalStore.bypassUpsertCoalesceForTest = true;
    await local.clearForOwner(owner);
    clearArchivedConversationSessionState();
    archivedConversationC2cIDsNotifier.value = {id};
    theme = DefaultThemeData();
  });
  tearDown(() async {
    ConversationTabStore.debugFetchByIdsOverride = null;
    ConversationMutationShadowBridge.instance.clearSession();
    clearArchivedConversationSessionState();
    await local.clearForOwner(owner);
    local.debugOwnerUserId = null;
    ConversationLocalStore.bypassUpsertCoalesceForTest = false;
    theme.dispose();
    await ApiClient.instance.clearToken();
  });

  Widget page() => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
          ],
          child: MaterialApp(
              locale: const Locale('en'),
              home: ArchivedConversationPage(
                  controller: TIMUIKitConversationController(),
                  listScope: ConversationListScope.c2c,
                  onTapConversation: (_) {})));

  Future<void> frame(WidgetTester tester) async {
    final handler = FlutterError.onError;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await tester.pump(const Duration(milliseconds: 20));
    FlutterError.onError = handler;
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 2000 && !ready(); i++) {
      await frame(tester);
    }
    if (!ready()) {
      debugPrint(
          'ARCHIVE_TEST_DIAG texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()} loading=${find.byType(CircularProgressIndicator).evaluate().length}');
    }
    expect(ready(), isTrue,
        reason: 'archive page must finish the requested SDK work');
    await frame(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await frame(tester);
  }

  testWidgets('empty archive index hydrates first SDK batch without scrolling',
      (tester) async {
    final response =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    final requests = <List<String>>[];
    ConversationTabStore.debugFetchByIdsOverride = (ids) {
      requests.add(List.of(ids));
      return response.future;
    };
    final handler = FlutterError.onError;
    await tester.pumpWidget(page());
    FlutterError.onError = handler;
    await until(tester, () => requests.isNotEmpty);
    expect(requests.single, [id]);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No archived chats'), findsNothing);
    response.complete((conversationList: [archivedRow(id)], code: 0));
    await until(
        tester, () => find.text('Cold archive contact').evaluate().isNotEmpty);
    expect(requests.length, 1);
    expect(find.byType(ListView), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('cold SDK failure exposes retry and retains the missing IDs',
      (tester) async {
    var calls = 0;
    ConversationTabStore.debugFetchByIdsOverride = (ids) async {
      calls++;
      expect(ids, [id]);
      return (
        conversationList:
            calls == 1 ? <V2TimConversation>[] : [archivedRow(id)],
        code: calls == 1 ? 70001 : 0
      );
    };
    final handler = FlutterError.onError;
    await tester.pumpWidget(page());
    FlutterError.onError = handler;
    final retryButton = find.descendant(
        of: find.byType(ArchivedConversationPage),
        matching: find.byType(TextButton));
    await until(tester, () => retryButton.evaluate().isNotEmpty || calls > 1);
    expect(calls, 1, reason: 'a failed cold read must await the user retry');
    expect(retryButton, findsOneWidget);
    final retryLabel = AppI18n.of(tester.element(retryButton))
        .t(zhHans: '重试', zhHant: '重試', en: 'Retry', ja: '再試行', ko: '다시 시도');
    expect(find.widgetWithText(TextButton, retryLabel), findsOneWidget);
    await tester.tap(retryButton);
    await until(
        tester, () => find.text('Cold archive contact').evaluate().isNotEmpty);
    expect(calls, 2);
    await unmount(tester);
  });

  testWidgets('account boundary discards a pending archive hydration result',
      (tester) async {
    final response =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    var requested = false;
    ConversationTabStore.debugFetchByIdsOverride = (ids) {
      requested = true;
      return response.future;
    };
    final handler = FlutterError.onError;
    await tester.pumpWidget(page());
    FlutterError.onError = handler;
    await until(tester, () => requested);
    SessionIdentityService.instance.invalidate();
    response.complete((conversationList: [archivedRow(id)], code: 0));
    for (var i = 0; i < 40; i++) {
      await frame(tester);
    }
    expect(find.text('Cold archive contact'), findsNothing);
    final count =
        await tester.runAsync(() => local.countByConvType(convType: 1));
    expect(count, 0);
    await unmount(tester);
  });
}
