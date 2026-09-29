import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_notify_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/conversation_notify_api.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('failed mute request automatically retries without another user action',
      () async {
    var calls = 0;
    final delivered = Completer<void>();
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => 'retry_owner',
        sendForTest: (items) async {
          if (++calls == 1) throw StateError('temporary outage');
          delivered.complete();
        },
        pageForTest: (_) async =>
            V2TimConversationResult(conversationList: [], isFinished: true));
    addTearDown(service.clearSession);
    await service.reportAfterImSuccess(
        chatType: 'c2c', peerId: 'p', muted: true);
    await delivered.future.timeout(const Duration(seconds: 5));
    expect(calls, 2);
  });

  test('new local mute wins over a delayed login snapshot', () async {
    final gate = Completer<V2TimConversationResult>(),
        started = Completer<void>();
    final sent = <bool>[];
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => 'owner',
        sendForTest: (items) async {
          sent.addAll(items.map((e) => e.muted));
        },
        pageForTest: (_) async {
          started.complete();
          return gate.future;
        });
    addTearDown(service.clearSession);
    final sync = service.syncAllOnLogin();
    await started.future;
    await service.reportAfterImSuccess(
        chatType: 'c2c', peerId: 'p', muted: true);
    gate.complete(V2TimConversationResult(conversationList: [
      V2TimConversation(
          conversationID: 'c2c_p', userID: 'p', type: 1, recvOpt: 0),
    ], isFinished: true));
    await sync;
    expect(sent, [true]);
  });
  test('draft aliases serialize SDK saves and clear; stale save never commits',
      () async {
    final gate = Completer<int>();
    final started = Completer<void>();
    final writes = <String?>[], commits = <String>[];
    final service = ConversationDraftService.forTesting(
        ownerForTest: () => 'owner',
        writeForTest: (id, text) async {
          writes.add(text);
          if (writes.length == 1) {
            started.complete();
            return gate.future;
          }
          return 0;
        },
        readForTest: (_) async => '  spaced\n',
        commitForTest: (id, text) async {
          commits.add(text);
        });
    final first = service.persistDraft(
        conversationID: 'group_@TGS#peer', rawInputText: 'old');
    await started.future;
    final clear = service.clearDraft(conversationID: '@TGS#peer');
    expect(writes, ['old']);
    gate.complete(0);
    await Future.wait([first, clear]);
    expect(writes, ['old', null]);
    expect(commits, ['']);
    expect(
        await service.loadDraftText(conversationID: '@TGS#peer'), '  spaced\n');
  });
  test('SDK draft error never commits and does not poison subsequent writes',
      () async {
    var fail = true;
    final commits = <String>[];
    final service = ConversationDraftService.forTesting(
        ownerForTest: () => 'a',
        writeForTest: (id, text) async => fail ? 1 : 0,
        readForTest: (_) async => null,
        commitForTest: (id, text) async {
          commits.add(text);
        });
    await expectLater(
        service.persistDraft(conversationID: 'c2c_p', rawInputText: 'bad'),
        throwsStateError);
    expect(commits, isEmpty);
    fail = false;
    await service.persistDraft(conversationID: 'c2c_p', rawInputText: 'good');
    expect(commits, ['good']);
  });
  test('account switch invalidates pending draft work', () async {
    var owner = 'a';
    final gate = Completer<int>(), started = Completer<void>();
    final commits = <String>[];
    final service = ConversationDraftService.forTesting(
        ownerForTest: () => owner,
        writeForTest: (id, text) async {
          started.complete();
          return gate.future;
        },
        readForTest: (_) async => null,
        commitForTest: (id, text) async {
          commits.add(text);
        });
    final pending =
        service.persistDraft(conversationID: 'c2c_p', rawInputText: 'old');
    await started.future;
    owner = 'b';
    gate.complete(0);
    await pending;
    expect(commits, isEmpty);
  });
  test('mute failure survives service restart and drains for its owner',
      () async {
    final sent = <bool>[];
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => 'a',
        sendForTest: (items) async {
          throw StateError('offline');
        },
        pageForTest: (_) async =>
            V2TimConversationResult(conversationList: [], isFinished: true));
    await service.reportAfterImSuccess(
        chatType: 'c2c', peerId: 'p', muted: true);
    service.clearSession();
    final restored = ConversationNotifySyncService.forTesting(
        ownerForTest: () => 'a',
        sendForTest: (items) async {
          sent.addAll(items.map((e) => e.muted));
        },
        pageForTest: (_) async =>
            V2TimConversationResult(conversationList: [], isFinished: true));
    addTearDown(restored.clearSession);
    await restored.syncAllOnLogin();
    expect(sent, [true]);
  });
  test('mute last intent wins after in-flight request', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final sent = <bool>[];
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => 'a',
        sendForTest: (items) async {
          sent.add(items.single.muted);
          if (sent.length == 1) {
            started.complete();
            await gate.future;
          }
        },
        pageForTest: (_) async =>
            V2TimConversationResult(conversationList: [], isFinished: true));
    addTearDown(service.clearSession);
    final first = service.reportAfterImSuccess(
        chatType: 'group', peerId: '@TGS#p', muted: true);
    await started.future;
    final last = service.reportAfterImSuccess(
        chatType: 'group', peerId: '@TGS#p', muted: false);
    gate.complete();
    await Future.wait([first, last]);
    expect(sent, [true, false]);
  });
  test('mute sync visits every SDK page and cooldown belongs to account',
      () async {
    var owner = 'a';
    final sent = <String>[], cursors = <String>[];
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => owner,
        sendForTest: (items) async {
          sent.addAll(items.map((e) => '$owner:${e.peerId}'));
        },
        pageForTest: (cursor) async {
          cursors.add('$owner:$cursor');
          return V2TimConversationResult(conversationList: [
            V2TimConversation(
                conversationID: 'c2c_p$cursor',
                userID: 'p$cursor',
                type: 1,
                recvOpt: 1)
          ], nextSeq: '1', isFinished: cursor == '1');
        });
    addTearDown(service.clearSession);
    await service.syncAllOnLogin();
    await service.syncAllOnLogin();
    owner = 'b';
    await service.syncAllOnLogin();
    expect(cursors, ['a:0', 'a:1', 'b:0', 'b:1']);
    expect(sent, ['a:p0', 'a:p1', 'b:p0', 'b:p1']);
  });
  test('old account page cannot enqueue writes for new account', () async {
    var owner = 'a';
    final gate = Completer<V2TimConversationResult>(),
        started = Completer<void>();
    final sent = <ConversationNotifyItem>[];
    final service = ConversationNotifySyncService.forTesting(
        ownerForTest: () => owner,
        sendForTest: (items) async {
          sent.addAll(items);
        },
        pageForTest: (_) async {
          started.complete();
          return gate.future;
        });
    addTearDown(service.clearSession);
    final pending = service.syncAllOnLogin();
    await started.future;
    owner = 'b';
    gate.complete(V2TimConversationResult(conversationList: [
      V2TimConversation(
          conversationID: 'c2c_p', userID: 'p', type: 1, recvOpt: 1)
    ], isFinished: true));
    await pending;
    expect(sent, isEmpty);
  });
}
