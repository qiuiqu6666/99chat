import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

V2TimConversation _c2c({
  required String id,
  required int activeSec,
}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    draftTimestamp: activeSec,
    orderkey: activeSec,
    showName: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('exclude query serialization', () {
    const owner = 'archive_sync_exclude_owner';

    setUp(() async {
      ConversationLocalStore.instance.debugOwnerUserId = owner;
      await ConversationLocalStore.instance.clearForOwner(owner);
    });

    tearDown(() async {
      await ConversationLocalStore.instance.clearForOwner(owner);
      ConversationLocalStore.instance.debugOwnerUserId = null;
    });

    test('parallel exclude COUNT stays correct', () async {
      final items = <V2TimConversation>[
        for (var i = 0; i < 20; i++)
          _c2c(id: 'c2c_ex$i', activeSec: 1700000000 + i),
      ];
      await ConversationLocalStore.instance.upsertBatch(conversations: items);

      final excludeA = {'c2c_ex0', 'c2c_ex1', 'c2c_ex2'};
      final excludeB = {'c2c_ex0'};

      final futures = <Future<int>>[
        for (var i = 0; i < 8; i++)
          ConversationLocalStore.instance.countByConvType(
            convType: 1,
            excludeConversationIds: i.isEven ? excludeA : excludeB,
          ),
      ];
      final results = await Future.wait(futures);

      for (var i = 0; i < results.length; i++) {
        expect(
          results[i],
          i.isEven ? 17 : 19,
          reason: 'index=$i',
        );
      }
    });
  });

  group('syncMainListAfterArchiveChange', () {
    const owner = 'archive_sync_main_owner';
    late ChatSessionController controller;

    setUp(() async {
      ConversationLocalStore.bypassUpsertCoalesceForTest = true;
      ConversationLocalStore.instance.debugOwnerUserId = owner;
      await ConversationLocalStore.instance.clearForOwner(owner);
      archivedConversationC2cIDsNotifier.value = <String>{};
      archivedConversationGroupIDsNotifier.value = <String>{};
      controller = ChatSessionController.instance;
      controller.clearSessionProjection();
    });

    tearDown(() async {
      ConversationTabStore.debugFetchByIdsOverride = null;
      controller.clearSessionProjection();
      archivedConversationC2cIDsNotifier.value = <String>{};
      archivedConversationGroupIDsNotifier.value = <String>{};
      await ConversationLocalStore.instance.clearForOwner(owner);
      ConversationLocalStore.instance.debugOwnerUserId = null;
      ConversationLocalStore.bypassUpsertCoalesceForTest = false;
    });

    test('removedIds purge from UI window', () async {
      final a = _c2c(id: 'c2c_keep', activeSec: 100);
      final b = _c2c(id: 'c2c_gone', activeSec: 90);
      controller.replaceProjectionForTest([a, b]);

      archivedConversationC2cIDsNotifier.value = {'c2c_gone'};
      await ChatSessionController.instance.syncMainListAfterArchiveChange(
        removedIds: const ['c2c_gone'],
        reason: 'test_remove',
      );

      expect(
        controller.conversations.map((c) => c.conversationID),
        ['c2c_keep'],
      );
    });

    test('restoredIds re-admit into UI window', () async {
      final a = _c2c(id: 'c2c_keep2', activeSec: 200);
      final b = _c2c(id: 'c2c_back', activeSec: 180);
      ConversationTabStore.debugFetchByIdsOverride =
          (ids) async => (conversationList: [b], code: 0);
      controller.replaceProjectionForTest([a]);
      archivedConversationC2cIDsNotifier.value = <String>{};

      await ChatSessionController.instance.syncMainListAfterArchiveChange(
        restoredIds: const ['c2c_back'],
        reason: 'test_restore',
      );

      expect(
        controller.conversations.any((c) => c.conversationID == 'c2c_back'),
        isTrue,
      );
      expect(
        controller.conversations.any((c) => c.conversationID == 'c2c_keep2'),
        isTrue,
      );
    });

    test('restoredIds appear in type hydrate for virtual list', () async {
      final a = _c2c(id: 'c2c_keep3', activeSec: 300);
      final b = _c2c(id: 'c2c_back3', activeSec: 280);
      ConversationTabStore.debugFetchByIdsOverride =
          (ids) async => (conversationList: [b], code: 0);
      controller.replaceProjectionForTest([a]);
      // The typed page and main feed both read the seeded SDK store.
      archivedConversationC2cIDsNotifier.value = <String>{};

      await ChatSessionController.instance.syncMainListAfterArchiveChange(
        restoredIds: const ['c2c_back3'],
        reason: 'test_restore_hydrate',
      );

      expect(
        controller.conversations.any((c) => c.conversationID == 'c2c_back3'),
        isTrue,
      );
      expect(
        controller.conversationAtTypeIndex(1, 0)?.conversationID,
        isNotNull,
      );
      final pageIds = <String>[];
      for (var i = 0; i < 8; i++) {
        final row = controller.conversationAtTypeIndex(1, i);
        if (row == null) {
          break;
        }
        pageIds.add(row.conversationID);
      }
      expect(pageIds.contains('c2c_back3'), isTrue);
    });

    test('single-flight coalesces restored while in flight', () async {
      final items = <V2TimConversation>[
        _c2c(id: 'c2c_sf0', activeSec: 300),
        _c2c(id: 'c2c_sf1', activeSec: 290),
        _c2c(id: 'c2c_sf2', activeSec: 280),
      ];
      ConversationTabStore.debugFetchByIdsOverride = (ids) async => (
            conversationList:
                items.where((row) => ids.contains(row.conversationID)).toList(),
            code: 0
          );
      controller.replaceProjectionForTest([items.first]);

      final first =
          ChatSessionController.instance.syncMainListAfterArchiveChange(
        restoredIds: const ['c2c_sf1'],
        reason: 'sf_a',
      );
      final second =
          ChatSessionController.instance.syncMainListAfterArchiveChange(
        restoredIds: const ['c2c_sf2'],
        reason: 'sf_b',
      );
      await Future.wait([first, second]);

      expect(
        controller.conversations.any((c) => c.conversationID == 'c2c_sf1'),
        isTrue,
      );
      expect(
        controller.conversations.any((c) => c.conversationID == 'c2c_sf2'),
        isTrue,
      );
      expect(
          ChatSessionController.instance.pendingArchiveRestoredCountForTest, 0);
      expect(
          ChatSessionController.instance.archiveSyncInFlightForTest, isFalse);
    });
    test('failed SDK restore does not resurrect a stale SQLite archive row',
        () async {
      final stale = _c2c(id: 'c2c_stale', activeSec: 20);
      await ConversationLocalStore.instance.upsertBatch(conversations: [stale]);
      ConversationTabStore.debugFetchByIdsOverride =
          (ids) async => (conversationList: <V2TimConversation>[], code: 6012);
      await controller
          .syncMainListAfterArchiveChange(restoredIds: ['c2c_stale']);
      expect(controller.conversations, isEmpty);
    });

    test('old account SDK restore result is discarded', () async {
      final response =
          Completer<({List<V2TimConversation> conversationList, int code})>();
      final entered = Completer<void>();
      ConversationTabStore.debugFetchByIdsOverride = (ids) {
        entered.complete();
        return response.future;
      };
      final pending =
          controller.syncMainListAfterArchiveChange(restoredIds: ['c2c_old']);
      await entered.future;
      controller.clearSessionProjection();
      response.complete(
          (conversationList: [_c2c(id: 'c2c_old', activeSec: 20)], code: 0));
      await pending;
      expect(controller.conversations, isEmpty);
      expect(ConversationTabStore.instance.itemsForType(1), isEmpty);
    });
  });
}
