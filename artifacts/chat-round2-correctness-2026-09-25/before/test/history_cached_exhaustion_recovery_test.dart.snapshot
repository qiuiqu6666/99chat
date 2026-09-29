import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = MessageHistoryCoverageStore.instance;
  late Directory directory;
  final scope = AccountScopedConversationKey(
    ownerUserId: 'cached_history_owner',
    conversationType: ImConversationType.group,
    conversationId: 'group_@TGS#cached_history',
  );

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('cached_exhaustion_');
    store.debugOwnerUserId = scope.ownerUserId;
    store.debugDatabasePath = p.join(directory.path, 'coverage.db');
    await store.clearSession();
    await store.saveForOwner(
        scope.ownerUserId,
        MessageHistoryCoverage(
          conversationKey: scope.conversationId,
          isGroup: true,
          clearEpoch: 12,
          coverageRevision: 7,
          status: MessageHistoryCoverageStatus.verified,
          olderExhausted: true,
          newerHasMore: false,
          holes: const [],
          ranges: const [
            MessageHistoryCoverageRange(
              key: 'im06:cloud:old-request',
              direction: MessageHistoryCoverageDirection.older,
              startSeq: 61,
              endSeq: 100,
              proofKind: MessageHistoryProofKind.transportObserved,
              closed: true,
              generation: 4,
            )
          ],
          updatedAtMs: 1,
        ));
    // Simulate a process restart: reload SQLite, not the in-memory DTO.
    await store.clearSession();
  });

  tearDown(() async {
    final global = serviceLocator<TUIChatGlobalModel>();
    global.clearData();
    global.appMessageHistoryCoverageRepository = null;
    await store.clearSession();
    store.debugOwnerUserId = null;
    store.debugDatabasePath = null;
    directory.deleteSync(recursive: true);
  });

  test('restored metadata keeps bounds but cannot close history', () async {
    final adapter = Im06MessageHistoryCoverageStoreAdapter(store);
    final restored = (await adapter.load(scope))!;
    expect(restored.clearEpoch, 12);
    expect(restored.coverageRevision, 7);
    expect(restored.ranges.single.returnedBounds.oldestSequence, 61);
    expect(restored.ranges.single.proof.level, ImHistoryProofLevel.none);
    expect(restored.isClosed(Im06HistoryCoverageDirection.older), isFalse);
    await adapter.save(restored);
    await store.clearSession();
    expect(
        (await adapter.load(scope))!
            .isClosed(Im06HistoryCoverageDirection.older),
        isFalse);
  });

  test('persisted group exhaustion leaves a new page eligible to probe',
      () async {
    final global = serviceLocator<TUIChatGlobalModel>();
    global.appMessageHistoryCoverageRepository = store;
    await global.ensureMessageHistoryCoverageLoaded(scope.conversationId);
    expect(
        global.messageHistoryCoverageFor(scope.conversationId)!.olderExhausted,
        isTrue);
    global.setMessageList(
      scope.conversationId,
      List.generate(40, (index) {
        final seq = 100 - index;
        return V2TimMessage.fromJson({
          'message_msg_id': 'm$seq',
          'message_server_time': seq,
          'message_seq': '$seq',
          'message_status': 2,
          'message_risk_type_identified': 0,
        })
          ..groupID = '@TGS#cached_history';
      }),
      replace: true,
      applyMemoryWindow: false,
      needResetNewMessageCount: false,
    );
    expect(global.rawMessageCount(scope.conversationId), 40);
    final model = TUIChatSeparateViewModel()
      ..conversationID = scope.conversationId
      ..conversationType = ConvType.group;
    model.syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
    expect(model.historyAvailability, HistoryAvailability.unknown);
    model.haveMoreData = true;
    model.syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
    expect(model.historyAvailability, HistoryAvailability.available);
    // A live request may still close this page. Cache synchronization must not
    // reopen it on rebuild and create repeated empty SDK requests.
    model.haveMoreData = false;
    model.syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
    expect(model.historyAvailability, HistoryAvailability.exhausted);
    model.dispose();
    final reopened = TUIChatSeparateViewModel()
      ..conversationID = scope.conversationId
      ..conversationType = ConvType.group;
    reopened.syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
    expect(reopened.historyAvailability, HistoryAvailability.unknown);
    expect(global.rawMessageCount(scope.conversationId), 40);
    reopened.dispose();
  });
}
