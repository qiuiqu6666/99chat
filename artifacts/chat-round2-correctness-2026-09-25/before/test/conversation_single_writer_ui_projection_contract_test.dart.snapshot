import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String signature, String nextSignature) {
  final start = source.indexOf(signature);
  final end = source.indexOf(nextSignature, start + signature.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
  expect(end, greaterThan(start), reason: 'missing boundary $nextSignature');
  return source.substring(start, end);
}

void main() {
  test('mute unread and metadata publish only committed coordinator batches',
      () {
    final source = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();

    final mute = _methodBody(
      source,
      'Future<V2TimConversation?> applyConversationMuteLocally(',
      'Future<V2TimConversation?> applyConversationUnreadLocally(',
    );
    final metadata = _methodBody(
      source,
      'Future<V2TimConversation?> applyConversationMetadataPatch(',
      'Future<bool> get haveMoreData',
    );
    final unread = _methodBody(
      source,
      'Future<V2TimConversation?> applyConversationUnreadLocally(',
      'Future<V2TimConversation?> applyConversationMetadataPatch(',
    );

    for (final body in <String>[mute, unread, metadata]) {
      expect(body, contains('commitCoordinatorPlan'));
      expect(body, contains('commit.shouldNotifyUi'));
      expect(body, contains('applyCommittedProjection'));
      expect(body, contains('commit.uiBatch'));
    }
  });

  test('conversation page has one cold-start Store projection reload', () {
    final source = File('lib/src/conversation.dart').readAsStringSync();
    expect(
      'ChatSessionController.instance.restoreProjection('.allMatches(source),
      hasLength(1),
    );
    expect(
      source,
      contains('ConversationStoreProjectionReason.coldStart'),
    );
    expect(source, contains('_loadCachedConversationPreviews below'));
  });

  test('legacy Store projection names are test-only and production is typed',
      () {
    final dartFiles = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('.reloadFromLocal(')), reason: file.path);
      expect(
        source,
        isNot(contains('.applyConversationsFromStore(')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('.applyWindowPatchesIfNeeded(')),
        reason: file.path,
      );
    }

    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();
    final reason = File(
      'lib/src/chat_session/conversation_projection_reason.dart',
    ).readAsStringSync();
    expect(reason, contains('enum ConversationStoreProjectionReason'));
    expect(controller, contains('applyCommittedBatchForTest'));
    expect(controller, contains('applyConversationsFromStoreForTest'));
  });

  test('legacy reducer remains independent while runtime uses SDK adapter', () {
    final writer = File(
      'lib/src/chat_session/conversation_projection_writer.dart',
    ).readAsStringSync();

    expect(writer, contains('class ConversationProjectionWriter'));
    expect(writer, contains('ConversationProjectionReducer.reduce'));
    expect(writer, contains('class ConversationProjectionWriteResult'));
    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();
    expect(controller, isNot(contains('late final ConversationProjectionWriter')));
    expect(controller, contains('_adoptTabStoreProjection'));
    expect(controller, isNot(contains('class _ControllerProjectionWriterHost')));
  });

  test('window consumers use the ChatSessionController boundary', () {
    const windowMethods = <String>[
      'ensureTypeIndexHydrated',
      'appendOlderFromLocal',
      'prependNewerFromLocal',
      'slideToHotPrefix',
      'refreshTypeTotals',
      'totalCountForType',
      'typeIndexOfConversationId',
      'conversationAtTypeIndex',
      'updateViewportAnchor',
      'takePinReorderScrollHint',
    ];
    const consumers = <String>[
      'lib/src/conversation.dart',
      'lib/src/widgets/conversation_feed/conversation_feed_body.dart',
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ];
    for (final path in consumers) {
      final source = File(path).readAsStringSync();
      for (final method in windowMethods) {
        expect(
          source,
          isNot(contains('ConversationListNotifier.instance.$method(')),
          reason: '$path still calls the legacy window API $method',
        );
      }
    }
    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();
    final windowState = File(
      'lib/src/chat_session/chat_session_window_state.dart',
    ).readAsStringSync();
    expect(controller, contains('class ChatSessionController'));
    expect(controller, contains('Future<void> ensureTypeIndexHydrated'));
    expect(controller, contains('Future<void> refreshTypeTotals()'));
    expect(
      File('lib/src/chat_session/chat_session_window_controller.dart')
          .readAsStringSync(),
      contains('ConversationTabStore.instance'),
    );
    expect(windowState, contains('int totalCountForType(int convType)'));
    expect(windowState, contains('ConversationPinReorderScrollHint?'));
    expect(
      File('lib/src/services/conversation_local/conversation_list_notifier.dart')
          .existsSync(),
      isFalse,
    );
  });

  test('profile publishers no longer patch conversation notifier directly', () {
    const paths = <String>[
      'lib/src/user_profile.dart',
      'lib/src/services/friend_local/friend_sync_service.dart',
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('applyShowNameLocally(')), reason: path);
      expect(source, isNot(contains('applyFaceUrlLocally(')), reason: path);
    }
  });

  test('mute keeps only pending and rollback optimistic projections', () {
    final conversation = File('lib/src/conversation.dart').readAsStringSync();
    final mainToggle = _methodBody(
      conversation,
      'Future<void> _toggleConversationDisturb(',
      'void _syncEditingStateNotifiers()',
    );
    final archivedToggle = _methodBody(
      conversation,
      'Future<void> _toggleArchivedConversationDisturb(',
      'void _showConversationPeek(',
    );
    final groupProfile = File('lib/src/group_profile.dart').readAsStringSync();
    final groupToggle = _methodBody(
      groupProfile,
      'Future<void> _setGroupMessageDisturb(',
      'Widget _buildMemberPreviewItem(',
    );

    for (final body in <String>[mainToggle, archivedToggle, groupToggle]) {
      expect(body, contains('072 phase-6 allowlist'));
      expect(body, contains('applyConversationMuteLocally'));
    }
    expect('applyRecvOptLocally('.allMatches(mainToggle), hasLength(1));
    expect('applyRecvOptLocally('.allMatches(archivedToggle), hasLength(1));
    expect('applyRecvOptLocally('.allMatches(groupToggle), hasLength(2));

    final syncService = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();
    expect(syncService, isNot(contains('applyRecvOptLocally(')));
  });

  test('pin success consumes commit batch and direct writes stay pending-only',
      () {
    final syncService = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();
    final pinCommit = _methodBody(
      syncService,
      'Future<V2TimConversation?> applyConversationPinLocally(',
      'Future<void> reconcileConversationPinSetLocally(',
    );
    expect(pinCommit, contains('applyCommittedPinProjection'));
    expect(pinCommit, contains('commit.uiBatch'));
    expect(pinCommit, isNot(contains('applyPinnedWithDeferredReorder')));
    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();
    expect(controller, contains('applyCommittedPinProjection'));

    final pinSync = File(
      'lib/src/services/conversation_pin_sync_service.dart',
    ).readAsStringSync();
    final tencentPrimary = _methodBody(
      pinSync,
      'Future<ConversationPinApplyResult> _setPinnedTencentPrimary(',
      'Future<bool> _pinConversationOnTencent(',
    );
    expect(tencentPrimary, contains('072 phase-6 allowlist'));
    expect(
      'applyPinnedWithDeferredReorder('.allMatches(tencentPrimary),
      hasLength(2),
    );
  });

  test('last-message direct projections are explicit pending-only allowlists',
      () {
    final syncService = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();
    expect(
      'applyLastMessageLocally('.allMatches(syncService),
      hasLength(2),
    );
    expect(
      '072 phase-6 allowlist'.allMatches(syncService).length,
      greaterThanOrEqualTo(2),
    );
    final revoke = _methodBody(
      syncService,
      'Future<void> markConversationLastMessageRevoked(',
      'String _ownerUserId()',
    );
    expect(revoke, contains('_commitSdkConversationBatch'));
    expect(revoke, isNot(contains('applyLastMessageLocally(')));
  });
}
