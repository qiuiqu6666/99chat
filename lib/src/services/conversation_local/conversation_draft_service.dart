import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/outgoing_identity_contract.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform_stub.dart'
    if (dart.library.js_interop) 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform_web.dart'
    as platform;

import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';

/// An edit capability scoped to the captured login generation. Its opaque
/// draftId also identifies durable acceptance; equal text is a different edit.
class ConversationDraftEdit {
  ConversationDraftEdit._(this.identity, this.conversationID,
      this.editorIdentity, this.revision, this.text,
      [String? persistedId])
      : draftId = persistedId ?? newOutgoingClientCorrelationId();
  final String draftId;
  final SessionIdentity identity;
  final String conversationID;
  final Object editorIdentity;
  final int revision;
  final String? text;
  String get key =>
      '${identity.ownerUserId}|${identity.generation}|$conversationID';
}

class DraftMirrorWriteException implements Exception {
  const DraftMirrorWriteException(this.cause);
  final Object cause;
  @override
  String toString() => 'SDK draft saved; local mirror needs repair: $cause';
}

/// App edits and send acceptance live in the encrypted draft ledger. SDK-only
/// legacy drafts are imported on read; SDK and conversation mirrors are derived.
class ConversationDraftService {
  ConversationDraftService._();

  ConversationDraftService.forTesting(
      {required this.ownerForTest,
      required this.writeForTest,
      required this.readForTest,
      required this.commitForTest,
      this.draftStoreForTest,
      this.draftCipherForTest});
  ImIngressStore? draftStoreForTest;
  OutboxPayloadCipher? draftCipherForTest;
  late final ImIngressStore _draftStore =
      draftStoreForTest ?? platform.createPlatformImIngressStore();
  bool get _durableDrafts => ownerForTest == null || draftStoreForTest != null;
  OutboxPayloadCipher get _draftCipher =>
      draftCipherForTest ?? OutboxPayloadCipher.instance;
  String Function()? ownerForTest;
  Future<int> Function(String, String?)? writeForTest;
  Future<String?> Function(String)? readForTest;
  Future<void> Function(String, String)? commitForTest;

  static final ConversationDraftService instance = ConversationDraftService._();
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> _versions = {};
  final Map<String, ConversationDraftEdit> _edits = {};
  final Set<String> _pendingEdits = {};
  final Set<String> _mirrorRepairPending = {};
  String get _owner =>
      ownerForTest?.call() ?? ContactSocialCacheStore.safeLoginUserId();

  String _sdkId(String raw) {
    final id = ConversationIdCanonical.forStorage(raw);
    if (id.isEmpty || id.startsWith('c2c_')) return id;
    if (raw.trim().startsWith('group_') ||
        ChatIdFormat.isIMGroupOrCommunityId(id) ||
        ChatIdFormat.isCommunityShortToken(id)) {
      return 'group_$id';
    }
    return 'c2c_$id';
  }

  bool isCurrentEdit(ConversationDraftEdit edit) =>
      identical(_edits[edit.key], edit) &&
      SessionIdentityService.instance
          .isCurrent(edit.identity, currentOwnerUserId: _owner);

  ConversationDraftEdit beginEditing(String conversationID) {
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    final id = _sdkId(conversationID);
    final key = '${identity.ownerUserId}|${identity.generation}|$id';
    final previous = _edits[key];
    final pendingText = _pendingEdits.contains(key) ? previous?.text : null;
    final edit = ConversationDraftEdit._(identity, id, Object(), 0, pendingText,
        pendingText == null ? null : previous?.draftId);
    _edits.removeWhere((_, value) => !SessionIdentityService.instance
        .isCurrent(value.identity, currentOwnerUserId: _owner));
    _edits[key] = edit;
    // A new page takes over an accepted edit that has not reached the SDK yet.
    // Invalidating the old editor must not discard that pending content.
    if (pendingText != null) {
      _write(id, pendingText, expectedEdit: edit).catchError((Object error) {
        ConversationDraftLeaveTrace.stage('draft_handoff_write_failed',
            conversationId: id,
            extras: <String, Object?>{
              'mirrorOnly': error is DraftMirrorWriteException
            });
      });
    }
    return edit;
  }

  ConversationDraftEdit? recordEdit(
      ConversationDraftEdit previous, String text) {
    if (!isCurrentEdit(previous)) return null;
    final edit = ConversationDraftEdit._(
        previous.identity,
        previous.conversationID,
        previous.editorIdentity,
        previous.revision + 1,
        text);
    _edits[edit.key] = edit;
    _pendingEdits.add(edit.key);
    return edit;
  }

  Future<ImDraftAcceptance> _protectEdit(
      ConversationDraftEdit edit, String text) async {
    final protected = await _draftCipher.protect(
        ownerUserId: edit.identity.ownerUserId, plaintext: text);
    if (protected == null)
      throw StateError('durable draft encryption unavailable');
    return ImDraftAcceptance(
        ownerUserId: edit.identity.ownerUserId,
        conversationId: edit.conversationID,
        draftId: edit.draftId,
        protectedText: protected.value);
  }

  ImDraftSubmissionContext submissionContext(ConversationDraftEdit edit) =>
      ImDraftSubmissionContext(
          isCurrent: () => isCurrentEdit(edit),
          prepare: () async {
            final draft = await _protectEdit(edit, edit.text ?? '');
            if (isCurrentEdit(edit))
              await _draftStore.transaction(
                  (tx) => (tx as ImDraftTransaction).saveDraftHead(draft));
            return draft;
          });

  bool mirrorRepairPending(ConversationDraftEdit edit) =>
      _mirrorRepairPending.contains(edit.key);

  Future<void> _write(String rawId, String? text,
      {ConversationDraftEdit? expectedEdit}) {
    final id = _sdkId(rawId);
    final identity = expectedEdit?.identity ??
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    if (id.isEmpty || identity.ownerUserId.isEmpty) return Future.value();
    if (expectedEdit != null &&
        (expectedEdit.conversationID != id || !isCurrentEdit(expectedEdit))) {
      return Future.value();
    }
    final key = '${identity.ownerUserId}|${identity.generation}|$id';
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    bool current() =>
        _versions[key] == version &&
        (expectedEdit == null || isCurrentEdit(expectedEdit)) &&
        SessionIdentityService.instance
            .isCurrent(identity, currentOwnerUserId: _owner);
    // The durable edit must not wait behind a hung SDK write for the same
    // conversation. SDK calls still retain their original serial order.
    final draftEdit = expectedEdit ??
        ConversationDraftEdit._(identity, id, Object(), 0, text);
    final durableSaved = _durableDrafts
        ? (() async {
            if (!current()) return;
            final draft = await _protectEdit(draftEdit, text ?? '');
            if (!current()) return;
            await _draftStore.transaction((tx) async {
              if (current())
                await (tx as ImDraftTransaction).saveDraftHead(draft);
            });
          })()
        : Future<void>.value();
    final next = (_tails[key] ?? Future<void>.value()).then((_) async {
      await durableSaved;
      if (!current()) return;
      // A reopened page can inherit the same edit while the original send's
      // cleanup is pending. Its old text must not revive either mirror after
      // that edit has already been durably accepted by the outbox.
      // Check at dispatch, not when durableSaved starts: acceptance can happen
      // while this operation waits behind an older SDK write.
      final head = _durableDrafts
          ? await _draftStore.transaction((tx) =>
              (tx as ImDraftTransaction).findDraftHead(identity.ownerUserId, id))
          : null;
      if (!current()) return;
      final alreadyAccepted = head?['draft_id'] == draftEdit.draftId &&
          head?['accepted_operation_id'] != null;
      final mirrorText = alreadyAccepted ? null : text;
      final int code;
      if (writeForTest != null) {
        code = await writeForTest!(id, mirrorText);
      } else {
        code = (await TencentImSDKPlugin.v2TIMManager
                .getConversationManager()
                .setConversationDraft(conversationID: id, draftText: mirrorText))
            .code;
      }
      if (!current()) return;
      if (code != 0) {
        ConversationDraftLeaveTrace.stage(
          'sdk_draft_write_failed',
          conversationId: id,
          extras: <String, Object?>{'code': code},
        );
        throw StateError('setConversationDraft failed: $code');
      }
      ConversationDraftLeaveTrace.stage(
        'sdk_draft_write_done',
        conversationId: id,
        draftText: mirrorText ?? '',
      );
      if (expectedEdit != null) _pendingEdits.remove(key);
      try {
        if (commitForTest != null) {
          await commitForTest!(id, mirrorText ?? '');
        } else {
          final commit =
              await _commitDraft(id, mirrorText ?? '', canCommit: current);
          if (current()) await _notifyList(commit);
        }
        if (current()) _mirrorRepairPending.remove(key);
      } catch (error) {
        _mirrorRepairPending.add(key);
        throw DraftMirrorWriteException(error);
      }
    });
    late Future<void> tail;
    tail = next
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
      if (identical(_tails[key], tail)) {
        _tails.remove(key);
        _versions.remove(key);
      }
    });
    _tails[key] = tail;
    return next;
  }

  Future<void> persistDraft({
    required String conversationID,
    required String rawInputText,
    ConversationDraftEdit? expectedEdit,
  }) =>
      _write(conversationID, rawInputText, expectedEdit: expectedEdit);

  Future<void> clearDraft(
          {required String conversationID,
          ConversationDraftEdit? expectedEdit}) =>
      _write(conversationID, null, expectedEdit: expectedEdit);

  /// Clears all IDs known to represent the same active conversation. This is
  /// used after send because group routes can expose both a bare IM ID and a
  /// `group_` UI storage ID during normalization.
  Future<void> clearDraftForConversationIds(
    Iterable<String> conversationIDs,
  ) async {
    final ids =
        conversationIDs.map(_sdkId).where((id) => id.isNotEmpty).toSet();
    for (final id in ids) {
      await clearDraft(conversationID: id);
    }
  }

  Future<String?> loadDraftText(
      {required String conversationID,
      ConversationDraftEdit? expectedEdit}) async {
    final id = _sdkId(conversationID);
    if (id.isEmpty) {
      return null;
    }
    final identity = expectedEdit?.identity ??
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    if (expectedEdit != null && !isCurrentEdit(expectedEdit)) return null;
    final hasPendingEdit =
        expectedEdit != null && _pendingEdits.contains(expectedEdit.key);
    if (_durableDrafts) {
      final head = await _draftStore.transaction((tx) =>
          (tx as ImDraftTransaction).findDraftHead(identity.ownerUserId, id));
      if ((expectedEdit != null && !isCurrentEdit(expectedEdit)) ||
          !SessionIdentityService.instance
              .isCurrent(identity, currentOwnerUserId: _owner)) {
        return null;
      }
      // Pending text is newer than storage only if it is a different edit.
      // A handed-off copy of an accepted draft must not restore sent text.
      if (hasPendingEdit &&
          (head?['draft_id'] != expectedEdit.draftId ||
              head?['accepted_operation_id'] == null)) {
        return expectedEdit.text;
      }
      if (head != null) {
        if ((expectedEdit != null && !isCurrentEdit(expectedEdit)) ||
            !SessionIdentityService.instance
                .isCurrent(identity, currentOwnerUserId: _owner)) return null;
        if (head['accepted_operation_id'] != null) {
          // The operation survived, but a crash may have left the SDK draft.
          // Repair through the same account queue and current edit fence.
          if (expectedEdit != null) {
            unawaited(_write(id, null, expectedEdit: expectedEdit)
                .catchError((Object error) {
              ConversationDraftLeaveTrace.stage(
                  'accepted_draft_cleanup_pending',
                  conversationId: id,
                  extras: {'errorType': error.runtimeType.toString()});
            }));
          }
          return null;
        }
        final saved = await _draftCipher.reveal(
            ownerUserId: identity.ownerUserId,
            value: head['protected_text'] as String);
        if ((expectedEdit != null && !isCurrentEdit(expectedEdit)) ||
            !SessionIdentityService.instance
                .isCurrent(identity, currentOwnerUserId: _owner)) return null;
        if (saved == null)
          throw StateError('durable draft cannot be decrypted');
        return saved.isEmpty ? null : saved;
      }
    }
    if (hasPendingEdit) return expectedEdit.text;
    final String? text;
    if (readForTest != null) {
      text = await readForTest!(id);
    } else {
      final result = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .getConversation(conversationID: id);
      if (result.code != 0) {
        throw StateError('getConversation draft failed: ${result.code}');
      }
      text = result.data?.draftText;
    }
    if ((expectedEdit != null && !isCurrentEdit(expectedEdit)) ||
        !SessionIdentityService.instance
            .isCurrent(identity, currentOwnerUserId: _owner)) {
      return null;
    }
    final key = '${identity.ownerUserId}|${identity.generation}|$id';
    if (_mirrorRepairPending.contains(key)) {
      bool current() =>
          SessionIdentityService.instance
              .isCurrent(identity, currentOwnerUserId: _owner) &&
          (expectedEdit == null || isCurrentEdit(expectedEdit));
      try {
        if (commitForTest != null) {
          await commitForTest!(id, text ?? '');
        } else {
          final commit = await _commitDraft(id, text ?? '', canCommit: current);
          if (current()) await _notifyList(commit);
        }
        if (current()) _mirrorRepairPending.remove(key);
      } catch (_) {
        // SDK remains authoritative even when its derived mirror is unavailable.
      }
    }
    return (text?.trim().isEmpty ?? true) ? null : text;
  }

  Future<void> _notifyList(
    ConversationDatabaseCommitResult<V2TimConversation>? commit,
  ) async {
    if (commit == null || !commit.shouldNotifyUi) {
      ConversationDraftLeaveTrace.stage(
        'apply_committed_projection_skipped',
        extras: <String, Object?>{
          'reason': commit == null ? 'null_commit' : 'no_notify',
        },
      );
      return;
    }
    final snapshotDraft = commit.uiBatch.upsertedSnapshots.isEmpty
        ? null
        : commit.uiBatch.upsertedSnapshots.first.draftText;
    final snapshotId = commit.uiBatch.upsertedSnapshots.isEmpty
        ? ''
        : commit.uiBatch.upsertedSnapshots.first.conversationID;
    ConversationDraftLeaveTrace.stage(
      'apply_committed_projection_start',
      conversationId: snapshotId,
      draftText: snapshotDraft,
    );
    await ChatSessionController.instance.applyCommittedProjection(
      commit.uiBatch,
    );
    ConversationDraftLeaveTrace.stage(
      'apply_committed_projection_done',
      conversationId: snapshotId,
      draftText: snapshotDraft,
    );

    // In SDK-primary mode the just-persisted SDK conversation is already the
    // authoritative row. Do not re-read the potentially stale SQLite mirror
    // and let it overwrite the draft we just displayed.
    return;

    // The SDK conversation stream can publish an older snapshot while the
    // chat route is being removed. Re-read the committed local rows and apply
    // them as an explicit draft projection so that stale SDK data cannot make
    // the draft disappear from the conversation list.
  }

  Future<ConversationDatabaseCommitResult<V2TimConversation>?> _commitDraft(
    String id,
    String text, {
    required bool Function() canCommit,
  }) async {
    final owner = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    if (owner.isEmpty) {
      return null;
    }
    final durable =
        await ConversationLocalStore.instance.coordinatorDurableState(
      ownerUserId: owner,
      conversationId: id,
    );
    // The guard must be checked before the durable write, not only before UI
    // notification. Otherwise a slow old debounce may overwrite a newer
    // input/clear operation and silently resurrect a stale draft.
    if (!canCommit()) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'can_commit'},
      );
      return null;
    }
    ConversationMutationShadowBridge.instance.restoreDurableConversationState(
      ownerUserId: owner,
      conversationId: id,
      generation: durable.generation,
      tombstoned: durable.tombstoned,
    );
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: id,
      fieldPatch: <ConversationMutationField, Object?>{
        ConversationMutationField.draft: text,
      },
    );
    if (plan == null) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'plan_null'},
      );
      return null;
    }
    if (!canCommit()) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'can_commit'},
      );
      return null;
    }
    final result = await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: plan,
    );
    ConversationDraftLeaveTrace.stage(
      'sqlite_draft_commit_done',
      conversationId: id,
      draftText: text,
      extras: <String, Object?>{
        'disposition': result.disposition.name,
        'shouldNotifyUi': result.shouldNotifyUi,
        'upserted': result.upsertedSnapshots.length,
      },
    );
    return result;
  }
}
