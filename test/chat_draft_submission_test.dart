import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_draft_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('late send success preserves B, its debounce and its leave save', () {
    fakeAsync((clock) {
      final draft = ChatDraftController();
      final saved = <String>[];
      void save(String text, int _) => saved.add(text);
      draft.onChanged('A', persist: save);
      final sent = draft.captureSubmission('A');
      expect(draft.clearForSubmission(sent), isTrue);
      draft.onChanged('B', persist: save);
      expect(draft.markSendCompleted(sent), isFalse);
      expect(draft.text, 'B');
      expect(draft.shouldSuppressLifecyclePersist, isFalse);
      clock.elapse(ChatDraftController.debounceDuration);
      expect(saved, ['B']);
      draft.dispose();
    });
  });

  test('same text is a new edit; old submissions and old loads are rejected',
      () {
    final draft = ChatDraftController();
    final loadRevision = draft.stateRevision;
    draft.onChanged('A', persist: (_, __) {});
    final first = draft.captureSubmission('A');
    draft.clearForSubmission(first);
    draft.onChanged('A', persist: (_, __) {});
    final second = draft.captureSubmission('A');
    draft.clearForSubmission(second);
    draft.onChanged('B', persist: (_, __) {});
    expect(draft.markSendCompleted(second), isFalse);
    expect(draft.markSendCompleted(first), isFalse);
    expect(draft.canApplyLoadedDraft(loadRevision), isFalse);
    expect(draft.text, 'B');
    draft.beginConversation();
    expect(draft.markSendCompleted(second), isFalse);
    draft.dispose();
  });

  test('persisted B survives A completion, page disposal and reopen', () async {
    final f = _DraftFixture();
    var edit = f.service.beginEditing('c2c_peer');
    edit = f.service.recordEdit(edit, 'A')!;
    final submittedClear = f.service.recordEdit(edit, '')!;
    await f.service
        .clearDraft(conversationID: 'c2c_peer', expectedEdit: submittedClear);
    final b = f.service.recordEdit(submittedClear, 'B')!;
    await f.save(b);
    await f.service
        .clearDraft(conversationID: 'c2c_peer', expectedEdit: submittedClear);
    final reopened = f.service.beginEditing('c2c_peer');
    expect(
        await f.service
            .loadDraftText(conversationID: 'c2c_peer', expectedEdit: reopened),
        'B');
    expect(f.sdk, 'B');
    expect(f.mirror, 'B');
    expect(f.writes, [null, 'B']);
  });

  test('new edit invalidates queued clear before debounce has persisted',
      () async {
    final f = _DraftFixture();
    final original = f.service.beginEditing('group_@TGS#peer');
    final clear = f.service.recordEdit(original, '')!;
    final pendingClear =
        f.service.clearDraft(conversationID: '@TGS#peer', expectedEdit: clear);
    final b = f.service.recordEdit(clear, 'B')!;
    await pendingClear;
    expect(f.writes, isEmpty);
    await f.save(b);
    expect(f.sdk, 'B');
    expect(f.mirror, 'B');
  });

  test('new page takes over unsaved B without revision collision or lost write',
      () async {
    final f = _DraftFixture();
    final old = f.service.beginEditing('c2c_peer');
    final a = f.service.recordEdit(old, 'A')!;
    final clear = f.service.recordEdit(a, '')!;
    final b = f.service.recordEdit(clear, 'B')!;
    final reopened = f.service.beginEditing('c2c_peer');
    expect(identical(reopened.editorIdentity, old.editorIdentity), isFalse);
    expect(
        await f.service
            .loadDraftText(conversationID: 'c2c_peer', expectedEdit: reopened),
        'B');
    await f.service.clearDraft(conversationID: 'c2c_peer', expectedEdit: clear);
    await f.save(b); // Late old-page leave/debounce cannot reclaim ownership.
    await f.save(reopened);
    expect(f.sdk, 'B');
    expect(f.mirror, 'B');
  });

  test('in-flight old SDK clear cannot publish its mirror over new B',
      () async {
    final f = _DraftFixture();
    final started = Completer<void>(), gate = Completer<void>();
    f.beforeWrite = (_) async {
      started.complete();
      await gate.future;
    };
    final original = f.service.beginEditing('c2c_peer');
    final clear = f.service.recordEdit(original, '')!;
    final clearing =
        f.service.clearDraft(conversationID: 'c2c_peer', expectedEdit: clear);
    await started.future;
    final b = f.service.recordEdit(clear, 'B')!;
    final saving = f.save(b);
    f.beforeWrite = null;
    gate.complete();
    await Future.wait([clearing, saving]);
    expect(f.writes, [null, 'B']);
    expect(f.commits, ['B']);
    expect(f.sdk, 'B');
  });

  test('account switch and same-owner relogin reject old captured tokens',
      () async {
    final f = _DraftFixture();
    var edit = f.service.beginEditing('c2c_peer');
    edit = f.service.recordEdit(edit, 'A')!;
    f.owner = 'another_owner';
    await f.save(edit);
    f.owner = 'owner';
    SessionIdentityService.instance
        .invalidate(reason: 'draft_regression_relogin');
    await f.save(edit);
    expect(f.writes, isEmpty);
  });

  test('SDK error leaves mirror unchanged and the next edit can save',
      () async {
    final f = _DraftFixture()..code = 1;
    final a = f.service.recordEdit(f.service.beginEditing('c2c_peer'), 'A')!;
    await expectLater(f.save(a), throwsStateError);
    expect(f.commits, isEmpty);
    f.code = 0;
    final b = f.service.recordEdit(a, 'B')!;
    await f.save(b);
    expect(f.sdk, 'B');
    expect(f.mirror, 'B');
  });

  test('SDK success plus mirror failure repairs from SDK without a resend',
      () async {
    final f = _DraftFixture()..failMirror = true;
    final a = f.service.recordEdit(f.service.beginEditing('c2c_peer'), 'A')!;
    await expectLater(f.save(a), throwsA(isA<DraftMirrorWriteException>()));
    expect(f.sdk, 'A');
    expect(f.mirror, isNull);
    expect(f.service.mirrorRepairPending(a), isTrue);
    f.failMirror = false;
    expect(
        await f.service
            .loadDraftText(conversationID: 'c2c_peer', expectedEdit: a),
        'A');
    expect(f.mirror, 'A');
    expect(f.writes, ['A']);
    expect(f.service.mirrorRepairPending(a), isFalse);
  });

  test('a late SDK draft load cannot restore A over new B', () async {
    final f = _DraftFixture();
    final started = Completer<void>(), gate = Completer<String?>();
    f.service.readForTest = (_) {
      started.complete();
      return gate.future;
    };
    final original = f.service.beginEditing('c2c_peer');
    final loading = f.service
        .loadDraftText(conversationID: 'c2c_peer', expectedEdit: original);
    await started.future;
    final b = f.service.recordEdit(original, 'B')!;
    gate.complete('A');
    expect(await loading, isNull);
    await f.save(b);
    expect(f.sdk, 'B');
  });
}

class _DraftFixture {
  _DraftFixture() {
    service = ConversationDraftService.forTesting(
      ownerForTest: () => owner,
      writeForTest: (_, text) async {
        writes.add(text);
        await beforeWrite?.call(text);
        if (code == 0) sdk = text;
        return code;
      },
      readForTest: (_) async => sdk,
      commitForTest: (_, text) async {
        if (failMirror) throw StateError('disk full');
        commits.add(text);
        mirror = text;
      },
    );
  }
  late final ConversationDraftService service;
  String owner = 'owner';
  String? sdk, mirror;
  int code = 0;
  bool failMirror = false;
  Future<void> Function(String?)? beforeWrite;
  final writes = <String?>[];
  final commits = <String>[];
  Future<void> save(ConversationDraftEdit edit) => service.persistDraft(
      conversationID: edit.conversationID,
      rawInputText: edit.text ?? '',
      expectedEdit: edit);
}
