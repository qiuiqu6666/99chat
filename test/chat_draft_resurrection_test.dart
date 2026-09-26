import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _row(String id, [String? draft]) => V2TimConversation(
      conversationID: id,
      type: 1,
      userID: id.substring(4),
      draftText: draft,
      draftTimestamp: draft == null ? null : 123,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConversationTabStore.instance.clear();
    ActiveChatRegistry.instance.reset();
  });
  tearDown(() {
    ActiveChatRegistry.instance.reset();
    ConversationTabStore.instance.clear();
  });

  test('late SDK snapshot cannot resurrect a sent draft in the list', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_row('c2c_peer', 'sent')]);
    tab.applyPatches([_row('c2c_peer')], explicitDraftIds: {'c2c_peer'});
    tab.applyPatches([_row('c2c_peer', 'sent')..faceUrl = 'updated-avatar']);
    final row = tab.itemsForType(1).single;
    expect(row.draftText, isNull);
    expect(row.draftTimestamp, isNull);
    expect(row.faceUrl, 'updated-avatar');
    tab.applyPatches([_row('c2c_peer', 'new edit')],
        explicitDraftIds: {'c2c_peer'});
    expect(tab.itemsForType(1).single.draftText, 'new edit');
  });

  test('clearing an already empty row still fences stale SDK drafts', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_row('c2c_peer')]);
    tab.applyPatches([_row('c2c_peer')], explicitDraftIds: {'c2c_peer'});
    tab.applyPatches([_row('c2c_peer', 'sent')]);
    expect(tab.itemsForType(1).single.draftText, isNull);
  });

  test('in-place SDK mutation cannot undo an explicit draft clear', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_row('c2c_peer', 'sent')]);
    tab.applyPatches([_row('c2c_peer')], explicitDraftIds: {'c2c_peer'});
    final shared = tab.itemsForType(1).single
      ..draftText = 'sent'
      ..draftTimestamp = 123;
    tab.applyPatches([shared]);
    expect(tab.itemsForType(1).single.draftText, isNull);
    expect(tab.itemsForType(1).single.draftTimestamp, isNull);
  });

  for (final latest in <String?>[null, 'new edit']) {
    test('deferred SDK snapshot preserves explicit draft $latest', () {
      final tab = ConversationTabStore.instance;
      ActiveChatRegistry.instance.enter('c2c_active');
      void commit(V2TimConversation row, ConversationMutationField field,
          int generation) {
        tab.applyCommittedViewBatch(
          ConversationUiSnapshotBatch<V2TimConversation>(
            upsertedSnapshots: [row],
            deletedCanonicalIds: const [],
            structureChanged: false,
            changedFieldMasks: {
              'c2c_peer': {field}
            },
            commitGeneration: generation,
          ),
          forceAdmitIds: {'c2c_peer'},
        );
      }

      commit(_row('c2c_peer', latest), ConversationMutationField.draft, 1);
      commit(_row('c2c_peer', 'sent')..faceUrl = 'updated-avatar',
          ConversationMutationField.avatar, 2);
      ActiveChatRegistry.instance.leave('c2c_active');
      tab.flushDeferredCommittedProjection();
      final row = tab.itemsForType(1).single;
      expect(row.draftText, latest);
      expect(row.draftTimestamp, latest == null ? isNull : 123);
      expect(row.faceUrl, 'updated-avatar');
    });
  }

  for (final newText in <String?>[null, 'sent', 'new edit']) {
    test('accepted draft is not restored on reopen; new edit=$newText',
        () async {
      final store = InMemoryImIngressStore();
      final cipher = OutboxPayloadCipher(
        readKey: () async => base64UrlEncode(List.filled(32, 7)),
        writeKey: (_) async {},
      );
      String? sdk = 'sent';
      var mirror = 'sent';
      final service = ConversationDraftService.forTesting(
        ownerForTest: () => 'owner',
        writeForTest: (_, text) async {
          sdk = text;
          return 0;
        },
        readForTest: (_) async => sdk,
        commitForTest: (_, text) async => mirror = text,
        draftStoreForTest: store,
        draftCipherForTest: cipher,
      );
      final sent =
          service.recordEdit(service.beginEditing('c2c_peer'), 'sent')!;
      final accepted = await service.submissionContext(sent).prepare();
      // Durable acceptance can precede the old page's UI/SDK clear callback.
      await store.transaction((tx) =>
          (tx as ImDraftTransaction).acceptDraft(accepted, 'operation'));
      if (newText != null) service.recordEdit(sent, newText);
      final reopened = service.beginEditing('c2c_peer');
      expect(
        await service.loadDraftText(
            conversationID: 'c2c_peer', expectedEdit: reopened),
        newText,
      );
      // A delayed leave/debounce with the accepted identity must also clear
      // the SDK mirror; checking only the encrypted head is insufficient.
      await service.persistDraft(
        conversationID: 'c2c_peer',
        rawInputText: reopened.text ?? '',
        expectedEdit: reopened,
      );
      expect(sdk, newText);
      expect(mirror, newText ?? '');
    });
  }

  test('draft accepted while waiting behind SDK write cannot be republished',
      () async {
    final store = InMemoryImIngressStore();
    final entered = Completer<void>();
    final release = Completer<void>();
    final writes = <String?>[];
    final service = ConversationDraftService.forTesting(
      ownerForTest: () => 'owner',
      writeForTest: (_, text) async {
        writes.add(text);
        if (writes.length == 1) {
          entered.complete();
          await release.future;
        }
        return 0;
      },
      readForTest: (_) async => writes.last,
      commitForTest: (_, __) async {},
      draftStoreForTest: store,
      draftCipherForTest: OutboxPayloadCipher(
        readKey: () async => base64UrlEncode(List.filled(32, 7)),
        writeKey: (_) async {},
      ),
    );
    final old = service.recordEdit(service.beginEditing('c2c_peer'), 'older')!;
    final oldWrite = service.persistDraft(
        conversationID: 'c2c_peer', rawInputText: 'older', expectedEdit: old);
    await entered.future;
    final sent = service.recordEdit(old, 'sent')!;
    final accepted = await service.submissionContext(sent).prepare();
    final queued = service.persistDraft(
        conversationID: 'c2c_peer', rawInputText: 'sent', expectedEdit: sent);
    // Let the non-blocking durable save finish while the SDK queue is held.
    await Future<void>.delayed(Duration.zero);
    await store.transaction(
        (tx) => (tx as ImDraftTransaction).acceptDraft(accepted, 'operation'));
    release.complete();
    await Future.wait([oldWrite, queued]);
    expect(writes, ['older', null]);
  });
}
