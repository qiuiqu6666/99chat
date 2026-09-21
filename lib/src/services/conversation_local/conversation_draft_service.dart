import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
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

/// 会话草稿：以 IMSDK 本地会话库为权威，SQLite 仅保留兼容镜像。
class ConversationDraftService {
  ConversationDraftService._();

  ConversationDraftService.forTesting(
      {required this.ownerForTest,
      required this.writeForTest,
      required this.readForTest,
      required this.commitForTest});
  String Function()? ownerForTest;
  Future<int> Function(String, String?)? writeForTest;
  Future<String?> Function(String)? readForTest;
  Future<void> Function(String, String)? commitForTest;

  static final ConversationDraftService instance = ConversationDraftService._();
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> _versions = {};
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

  Future<void> _write(String rawId, String? text) {
    final id = _sdkId(rawId);
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    if (id.isEmpty || identity.ownerUserId.isEmpty) return Future.value();
    final key = '${identity.ownerUserId}|${identity.generation}|$id';
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    bool current() =>
        _versions[key] == version &&
        SessionIdentityService.instance
            .isCurrent(identity, currentOwnerUserId: _owner);
    final next = (_tails[key] ?? Future<void>.value()).then((_) async {
      if (!current()) return;
      final int code;
      if (writeForTest != null) {
        code = await writeForTest!(id, text);
      } else {
        code = (await TencentImSDKPlugin.v2TIMManager
                .getConversationManager()
                .setConversationDraft(conversationID: id, draftText: text))
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
        draftText: text ?? '',
      );
      if (commitForTest != null) {
        await commitForTest!(id, text ?? '');
      } else {
        final commit = await _commitDraft(id, text ?? '', canCommit: current);
        if (current()) await _notifyList(commit);
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
  }) =>
      _write(conversationID, rawInputText);

  Future<void> clearDraft({required String conversationID}) =>
      _write(conversationID, null);

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

  Future<String?> loadDraftText({required String conversationID}) async {
    final id = _sdkId(conversationID);
    if (id.isEmpty) {
      return null;
    }
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: _owner);
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
    if (!SessionIdentityService.instance
        .isCurrent(identity, currentOwnerUserId: _owner)) {
      return null;
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
