import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimMessage row(String conv, int seq) => V2TimMessage.fromJson({
  'message_msg_id': '$conv-$seq',
  'message_server_time': seq,
  'message_risk_type_identified': 0,
})
  ..groupID = conv
  ..seq = '$seq'
  ..isSelf = false
  ..status = 2
  ..elemType = 1
  ..textElem = V2TimTextElem(text: 'message $seq');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('published durable bodies remain buffered until visible receipt', () async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('durable-guard-');
    final store = HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#published-durable-guard';
    try {
      global.configureMessageWriterScope(ownerUserID: 'guard-reader',
          accountGeneration: 1, domainGeneration: 1);
      global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
      global.setMessageList(conv, [row(conv, 100)], replace: true,
          applyMemoryWindow: false);
      global.setFollowingLatest(conv, false, notify: false);
      global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
          notify: false);
      await global.applyAppRealtimeMessage(row(conv, 101),
          ingressEventID: 'first-101', ingressSequence: 101);
      expect(global.hasDurableHistoryDeferred(conv), isTrue);
      expect(global.deferredIncomingBufferedCount(conv), 1);

      // A successful connected newest window owns the edge, but no row has
      // been acknowledged as visible yet. Use the real tail-publish contract.
      global.clearMemoryWindowMissingNewer(conv);
      global.setHistoryReadingWindowActive(conv, false);
      global.setFollowingLatest(conv, true, notify: false, absorbUnread: false);
      expect(await global.revealDurableIncomingAfterLatestReturn(conv,
          isCurrent: () => true), isTrue);
      expect(global.canRevealDurableIncomingAfterLatestReturn(conv), isTrue);
      final ids = global.rawMessageList(conv)!
          .map(TUIChatGlobalModel.liveIncomingIdentity).toSet();
      expect(ids.containsAll(global.remainingLiveIncomingIdsFor(conv)), isTrue);
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      expect(global.deferredIncomingBufferedCount(conv), 1,
          reason: 'published durable bodies are retained until visible ACK');
      expect(global.unadmittedRemainingLiveCountFor(conv), 1,
          reason: 'this helper counts buffered identity membership, not absence from raw');
    } finally {
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
      await store.closeIfOpen();
      await directory.delete(recursive: true);
    }
  });
}
