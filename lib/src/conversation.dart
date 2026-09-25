import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_anchor_scroll_controller.dart';
// ignore_for_file: unused_element, empty_catches

import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_paging_policy.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_preview_revision.dart';

import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_slidable_plus_plus/flutter_slidable_plus_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_entry_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_system_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_incremental_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_entry_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_receive_opt_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/account_scoped_conversation_key.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_group_receive_opt.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/conversation_pin_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_window_slide_result.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_rebase_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/folder_unread_refresh_gate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_notify_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_warm_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_coverage_repair_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_viewport_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/open_viewport_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_pipeline_clock.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_conversation_badge.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_rows.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_scroll_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_sync_gate.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/rebase_banner.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_ui.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_folder_chip_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_folder_swipe_region.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_desktop_context_menu.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_slidable.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/lazy_conversation_slidable.dart';
import 'package:tencent_cloud_chat_demo/src/utils/feed_scroll_restore_policy.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/src/utils/archive_conversation_lookup.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_fingerprint.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_folder_unread_index.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_content_patch.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_notice_selection.dart';
import 'package:tencent_cloud_chat_demo/src/pages/desktop_login_sessions_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/desktop_login_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/desktop_login_banner.dart';
import 'package:tencent_cloud_chat_demo/src/api/device_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/web_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_list_pressable.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_group_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_group_title_color.dart';
import 'package:tencent_cloud_chat_demo/src/multi_platform_widget/search_entry/search_entry.dart';
import 'package:tencent_cloud_chat_demo/src/multi_platform_widget/search_entry/search_entry_wide.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tim_ui_kit_sticker_plugin/utils/tim_custom_face_data.dart';
import 'package:tencent_cloud_chat_demo/src/all_group_application_list.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_group_notice_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_archive_host.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_demo/utils/user_guide.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart'
    show TUIChatGlobalModel;
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/unread_tongue_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/tim_uikit_conversation_item.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_emoji_sticker_list.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_display_helper.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_peek/conversation_peek_actions.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_peek/conversation_peek_overlay.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/ios_back_gesture.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';

List<CustomEmojiFaceData> _conversationPreviewEmojiList(BuildContext context) {
  return buildChatEmojiStickerList(context);
}

/// 会话列表滚动物理，与通讯录 [AZListViewContainer] 保持一致。
/// Web / 桌面用 Clamping，减少竖向回弹与左右滑抢手势。
ScrollPhysics conversationFeedScrollPhysics(BuildContext context) {
  if (conversationSlidableUseWebFeel(context)) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
  return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

Color _conversationItemBackground(TUITheme theme, {required bool pinned}) {
  return conversationFeedItemBackground(theme, pinned: pinned);
}

final ValueNotifier<bool> conversationEditingNotifier = ValueNotifier<bool>(
  false,
);
final ValueNotifier<bool> conversationAllSelectedNotifier = ValueNotifier<bool>(
  false,
);
final Map<ConversationListScope, VoidCallback?>
    conversationToggleEditModeActions = {};
final Map<ConversationListScope, Widget Function(TUITheme)>
    conversationEditActionBarBuilders = {};
final Map<ConversationListScope, VoidCallback?>
    conversationToggleSelectAllActions = {};
final Map<ConversationListScope, VoidCallback?>
    conversationScrollNextUnreadActions = {};
final Map<ConversationListScope, VoidCallback?> conversationScrollToTopActions =
    {};
const String archivedEntryIconAsset = 'assets/img/archive_icon.png';
const String groupNoticeEntryIconAsset = 'assets/img/group_notice_icon.png';
const double _systemEntryAvatarSize = 54;

Widget _buildSystemEntryAvatar(String assetPath) {
  return SizedBox(
    width: _systemEntryAvatarSize,
    height: _systemEntryAvatarSize,
    child: ClipOval(
      child: Transform.scale(
        scale: 1.48,
        child: Image.asset(
          assetPath,
          width: _systemEntryAvatarSize,
          height: _systemEntryAvatarSize,
          fit: BoxFit.cover,
        ),
      ),
    ),
  );
}

const String archivedEditIconSvg = '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="M897.39456 416.256v448.64c0 35.968-23.04 64-59.2 64H183.92256c-36.096 0-55.936-28.032-55.936-64V150.848c0-36.032 19.84-56 55.936-56h456.256a32 32 0 0 0 0-64H153.97056C99.76256 30.912 63.98656 78.72 63.98656 132.672v773.76c0 54.016 35.776 86.4 89.984 86.4h718.016c54.208 0 89.984-32.384 89.984-86.4V416.256a32.256 32.256 0 1 0-64.512 0z m-464.384 263.04l548.096-548.48a36.864 36.864 0 0 0 0-52.352 37.312 37.312 0 0 0-52.608 0l-548.032 548.48a36.736 36.736 0 0 0 0 52.352 37.44 37.44 0 0 0 52.544 0z" fill="#1D86F0"/>
</svg>
''';

/// 会话列表展示范围：单聊（消息）或群聊。
enum ConversationListScope { all, c2c, group }

/// Inserts business-only rows without reordering the SDK window. The source
/// wins when a folder lookup or official placeholder repeats a loaded row.
List<V2TimConversation> mergeConversationFeedSupplementsInSourceOrder({
  required List<V2TimConversation> source,
  required Iterable<V2TimConversation> supplements,
  required int Function(V2TimConversation, V2TimConversation) compare,
}) {
  final seen = <String>{
    for (final row in source)
      ConversationIdCanonical.forStorage(row.conversationID),
  };
  final additional = <V2TimConversation>[];
  for (final row in supplements) {
    final id = ConversationIdCanonical.forStorage(row.conversationID);
    if (id.isEmpty || !seen.add(id)) continue;
    additional.add(row);
  }
  if (additional.isEmpty) return source;
  additional.sort(compare);
  final result = <V2TimConversation>[];
  var next = 0;
  for (final row in source) {
    while (next < additional.length && compare(additional[next], row) < 0) {
      result.add(additional[next++]);
    }
    result.add(row);
  }
  result.addAll(additional.skip(next));
  return result;
}

bool conversationRecvOptMuted(V2TimConversation conversation) {
  return ConversationNotifySyncService.recvOptToMuted(conversation.recvOpt);
}

bool conversationShouldShowMuteIcon(V2TimConversation conversation) {
  if (conversation.groupType == "Meeting") {
    return false;
  }
  return conversationRecvOptMuted(conversation);
}

bool conversationMatchesScope(
  V2TimConversation conversation,
  ConversationListScope scope,
) {
  if (scope == ConversationListScope.all) {
    return true;
  }
  final isGroup = conversation.type == 2 ||
      (TencentUtils.checkString(conversation.groupID)?.isNotEmpty ?? false);
  return scope == ConversationListScope.group ? isGroup : !isGroup;
}

ConversationArchiveScope archiveScopeForListScope(ConversationListScope scope) {
  return scope == ConversationListScope.group
      ? ConversationArchiveScope.group
      : ConversationArchiveScope.c2c;
}

MarkReadListScope markReadListScopeOf(ConversationListScope scope) {
  switch (scope) {
    case ConversationListScope.all:
      return MarkReadListScope.all;
    case ConversationListScope.c2c:
      return MarkReadListScope.c2c;
    case ConversationListScope.group:
      return MarkReadListScope.group;
  }
}

Set<String> archivedConversationIdsForListScope(ConversationListScope scope) {
  switch (scope) {
    case ConversationListScope.c2c:
      return Set<String>.from(archivedConversationC2cIDsNotifier.value);
    case ConversationListScope.group:
      return Set<String>.from(archivedConversationGroupIDsNotifier.value);
    case ConversationListScope.all:
      return <String>{
        ...archivedConversationC2cIDsNotifier.value,
        ...archivedConversationGroupIDsNotifier.value,
      };
  }
}

Set<String> allArchivedConversationIds() {
  return <String>{
    ...archivedConversationC2cIDsNotifier.value,
    ...archivedConversationGroupIDsNotifier.value,
  };
}

Future<bool> confirmMarkReadAllDialog(
  BuildContext context, {
  required int conversationCount,
  required int unreadSum,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return CupertinoAlertDialog(
        title: Text(
          AppI18n.of(dialogContext).t(
            zhHans: '全部已读',
            zhHant: '全部已讀',
            en: 'Read All',
            ja: 'すべて既読',
            ko: '모두 읽음',
          ),
        ),
        content: Text(
          AppI18n.of(dialogContext).t(
            zhHans: '将清除 $conversationCount 个会话的未读（合计 $unreadSum），是否继续？',
            zhHant: '將清除 $conversationCount 個會話的未讀（合計 $unreadSum），是否繼續？',
            en: 'Clear unread for $conversationCount chats (total $unreadSum)?',
            ja: '$conversationCount 件の未読（合計 $unreadSum）をクリアしますか？',
            ko: '대화 $conversationCount개 미읽음(합계 $unreadSum)을 지우겠습니까?',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              AppI18n.of(dialogContext).t(
                zhHans: '取消',
                zhHant: '取消',
                en: 'Cancel',
                ja: 'キャンセル',
                ko: '취소',
              ),
            ),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppI18n.of(dialogContext).t(
                zhHans: '确定',
                zhHant: '確定',
                en: 'OK',
                ja: 'OK',
                ko: '확인',
              ),
            ),
          ),
        ],
      );
    },
  );
  return result == true;
}

String markReadActionLabel(
  BuildContext context, {
  required bool hasSelection,
}) {
  if (hasSelection) {
    return AppI18n.of(context).t(
      zhHans: '标记已读',
      zhHant: '標記已讀',
      en: 'Mark as Read',
      ja: '既読にする',
      ko: '읽음 표시',
    );
  }
  return AppI18n.of(context).t(
    zhHans: '全部已读',
    zhHant: '全部已讀',
    en: 'Read All',
    ja: 'すべて既読',
    ko: '모두 읽음',
  );
}

/// 归档 ID 集合匹配：兼容裸 ID / c2c_ / group_ 形态差异。
/// 热路径用 Expando 缓存 token Set，避免对归档集线性 sameConversation。
final Expando<Set<String>> _archiveLookupTokenCache = Expando<Set<String>>();

bool conversationIdInArchivedSet(
  Set<String> archivedIDs,
  String conversationID,
) {
  final id = conversationID.trim();
  if (id.isEmpty || archivedIDs.isEmpty) {
    return false;
  }
  if (archivedIDs.contains(id)) {
    return true;
  }
  var lookup = _archiveLookupTokenCache[archivedIDs];
  if (lookup == null) {
    lookup = buildArchiveLookupTokenSet(archivedIDs);
    _archiveLookupTokenCache[archivedIDs] = lookup;
  }
  return conversationIdInArchivedLookup(lookup, id);
}

void showConversationPeekForItem({
  required BuildContext context,
  required V2TimConversation conversation,
  required String displayName,
  required ConversationPeekActions actions,
}) {
  if (kIsWeb ||
      PlatformUtils().isWinMacDesktop ||
      !ConversationPeekService.canPeek(conversation)) {
    return;
  }
  ConversationPeekOverlay.show(
    context: context,
    conversation: conversation,
    displayName: displayName,
    actions: actions,
  );
}

/// 合并消息 Tab / 群聊 Tab 的会话全量刷新，避免同一 Bus 事件触发两次 reload。
class _ConversationListRefreshCoordinator {
  _ConversationListRefreshCoordinator._();

  static final Set<_ConversationState> _states = <_ConversationState>{};
  static Timer? _fullRefreshTimer;
  static DateTime? _lastFullRefreshAt;
  static const Duration _debounce = Duration(milliseconds: 800);
  static const Set<String> _skipWhenLoadedReasons = <String>{
    'im_uikit_lists_refreshed',
    'cold_start_ready',
    'friend_became_friends',
    'friend_became_friends_sent',
    'friend_application_refresh',
    'friend_list_changed',
    'friend_application_added',
    'new_message',
    'conversation_pin_toggle',
    'friend_remark_updated',
    'group_display_updated',
  };

  static bool _shouldSkipFullReloadWhenLoaded(String? reason) {
    final model = serviceLocator<TUIConversationViewModel>();
    if (!model.hasLoadedOnce) {
      return false;
    }
    if (reason != null && _skipWhenLoadedReasons.contains(reason)) {
      return true;
    }
    if (reason != null && reason.startsWith('group_changed_')) {
      return true;
    }
    if (reason != null && reason.endsWith('_done')) {
      return true;
    }
    return false;
  }

  static void register(_ConversationState state) {
    _states.add(state);
  }

  static void unregister(_ConversationState state) {
    _states.remove(state);
    if (_states.isEmpty) {
      _fullRefreshTimer?.cancel();
      _fullRefreshTimer = null;
    }
  }

  static void scheduleFullRefresh({String? reason}) {
    if (_shouldSkipFullReloadWhenLoaded(reason)) {
      return;
    }

    final now = DateTime.now();
    final last = _lastFullRefreshAt;
    if (last != null && now.difference(last) < _debounce) {
      _fullRefreshTimer?.cancel();
      _fullRefreshTimer = Timer(_debounce, _executeFullRefresh);
      return;
    }
    _executeFullRefresh();
  }

  static void _executeFullRefresh() {
    _fullRefreshTimer = null;
    final states = _states.where((state) => state.mounted).toList();
    if (states.isEmpty) {
      return;
    }

    _lastFullRefreshAt = DateTime.now();
    ConversationPinFlickerLog.log(
      'coordinator_full_refresh',
      extras: <String, Object?>{
        'states': states.length,
        'deferring': ChatSessionController.instance.isDeferringPinReorder,
      },
    );

    for (final state in states) {
      state._captureFeedScrollOffsetBeforeReload();
      state._suppressFeedPaging(const Duration(seconds: 2));
    }

    unawaited(
      ConversationSyncService.instance.syncFromSdk(
        reason: 'coordinator_full_refresh',
        reset: false,
        drainMode: ConversationSdkDrainMode.singlePage,
        reloadUiEachPage: false,
      ),
    );

    for (final state in states) {
      state._syncWebGroupConversations();
    }

    for (final state in states) {
      state._waitForFeedListStableThenRestore();
    }
  }
}

class Conversation extends StatefulWidget {
  final TIMUIKitConversationController conversationController;
  final ConversationListScope listScope;
  final bool hostEditActionBar;
  final ValueChanged<V2TimConversation?>? onConversationChanged;
  final VoidCallback? onClickSearch;
  final ValueChanged<Offset?>? onClickPlus;

  /// Used for specify the current conversation, usually used for showing the conversation indicator background color on wide screen.
  final V2TimConversation? selectedConversation;

  const Conversation({
    Key? key,
    required this.conversationController,
    this.listScope = ConversationListScope.c2c,
    this.hostEditActionBar = false,
    this.onConversationChanged,
    this.onClickSearch,
    this.onClickPlus,
    this.selectedConversation,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ConversationState();
}

class _ConversationState extends State<Conversation> {
  late TIMUIKitConversationController _controller;
  List<String> jumpedConversations = [];
  V2TimConversation? selectedConversation;
  bool _isEditing = false;
  Set<String> _selectedConversationIDs = <String>{};

  /// 编辑态 / 勾选变更用局部通知，避免整页 setState 拆毁 feed 树。
  final ValueNotifier<bool> _editingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> _selectionRevision = ValueNotifier<int>(0);
  final TUIFriendShipViewModel _friendShipViewModel =
      serviceLocator<TUIFriendShipViewModel>();
  final MessageService _messageService = serviceLocator<MessageService>();
  String? _openingConversationID;
  String? _embeddedActiveConversationID;
  final Map<String, int> _embeddedEntryUnreadById = <String, int>{};
  Timer? _conversationPreviewSaveTimer;
  List<CustomEmojiFaceData> _previewEmojiList = const [];
  Object? _previewEmojiToken;
  final ConversationAnchorScrollController _feedScrollController =
      ConversationAnchorScrollController();

  /// 滚动监听缓存；置顶时即使 hasClients 瞬时异常也能拿到真实偏移。
  double? _lastKnownFeedScrollOffset;
  double? _pendingFeedScrollRestoreOffset;
  Timer? _patchConversationTimer;
  final Set<String> _pendingPatchConversationIds = <String>{};
  String? _lastPatchReason;
  Timer? _feedScrollStableRestoreTimer;
  VoidCallback? _feedScrollStableRestoreListener;
  bool _feedPageLoadScheduled = false;

  bool _feedPageLoadInFlight = false;
  bool _viewportFillDone = false;
  int _viewportFillPagesDone = 0;

  /// sync 期间跳过的 SDK 补页；sync 结束后再试一次。
  bool _feedSdkPagePending = false;

  /// 触底确认本地+SDK 都无更多（供 footer）。
  bool _feedBottomExhausted = false;
  bool _viewportFillPendingAfterSync = false;
  bool _wasFeedSyncing = false;
  bool _folderSyncWasPending =
      ConversationListSyncNotifier.instance.isSyncing ||
      ConversationListSyncNotifier.instance.isAwaitingServerSync ||
      !ConversationListSyncNotifier.instance.hasSyncedOnce;
  int _folderSyncReadyRevision = 0;

  /// 会话行估算高度：仅用于挑选锚点 index，不作裁顶跳距。
  static const double _feedRowEstimateHeight = 72;
  bool _scopeHydrationInFlight = false;
  bool _scopeHydrationFinished = false;
  DateTime? _suppressFeedPagingUntil;
  Timer? _feedPagingResumeTimer;
  Timer? _viewportWarmSettleTimer;
  Timer? _folderUnreadSettleTimer;
  Timer? _feedScrollEndSettleTimer;
  Timer? _feedPageContinueTimer;
  bool _feedSkipViewportWarmOnNextSettle = false;
  double? _pendingFeedScrollTarget;

  /// 停滑后略等弹簧/惯性收尾，再 flush UI 与滚动补偿，减轻末段顿挫。
  static const Duration _feedScrollEndSettleDelay = Duration(milliseconds: 72);
  Timer? _folderUnreadLeaveKickTimer;
  bool _feedWasScrolling = false;
  DateTime? _lastViewportAnchorPublishAt;

  /// 用于判断滚动方向：仅上滑近顶才 prepend，避免软裁后 offset 被夹到近顶又 jumpTo(0)。
  double? _lastFeedScrollPixelsForDirection;

  ValueNotifier<bool>? _feedScrollingNotifier;
  static const Duration _viewportWarmSettleDelay = Duration(milliseconds: 200);
  BuildContext? _feedRowBuildContext;
  TUITheme? _feedRowTheme;
  LocalSetting? _feedRowLocalSetting;

  /// null =「全部」；有值时列表只显示该分组成员。
  String? _selectedFolderId;
  bool _folderReorderEditing = false;
  /// 分组 UI 身份指纹（folderId + name）；不含 sortOrder，用于跳过「仅重排」整页 setState。
  List<String> _folderUiIdentity = const <String>[];
  // Only SDK ByIDs supplements for the selected folder. Loaded main-list rows
  // are always resolved from TabStore. Selection/membership changes and dispose
  // retire this cache; account identity also fences every asynchronous result.
  final Map<String, V2TimConversation> _folderSdkRows = {};
  final Set<String> _folderSdkDeletedIds = <String>{};
  Set<String> _folderSdkMemberIds = const <String>{};
  bool _folderSdkLookupRetryable = false;
  SessionIdentity? _folderSdkIdentity;
  int _folderHydrateGeneration = 0;
  int? _folderHydratingGeneration;
  bool _wasRouteVisibleForDesktopBanner = false;
  final Map<String, int> _folderUnreadById = <String, int>{};
  final ConversationFolderUnreadIndex _folderUnreadIndex = ConversationFolderUnreadIndex();
  int _folderUnreadConfigurationRevision = 0;
  int _folderUnreadAppliedConfigurationRevision = -1;
  int _folderUnreadSourceRevision = -1;
  SessionIdentity? _folderUnreadIdentity;
  bool _folderUnreadRefreshInFlight = false;
  List<String>? _cachedVisibleConversationIds;
  List<V2TimConversation>? _visibleConversationView;
  final Map<String, int> _visiblePositions = {};
  bool _visibleUsesFullStoreView = false;
  int _visibleCacheContentRevision = -1;
  final Map<String, V2TimConversation> _visibleOfficialPlaceholders = {};
  SessionIdentity? _visibleCacheIdentity;
  Set<String> _cachedVisibleIds = const <String>{};
  int _visibleCacheSourceLength = -1;
  Set<String> _visibleCacheSourceIds = const <String>{};
  int _visibleCacheStructureRevision = -1;
  int _visibilityRevision = 0;
  int _visibleCacheVisibilityRevision = -1;
  final Map<String, _ConversationPreviewProjectionEntry>
      _previewProjectionByConversation =
      <String, _ConversationPreviewProjectionEntry>{};
  final Map<String, V2TimConversation> _pendingPreviewProjectionRows =
      <String, V2TimConversation>{};
  final Map<String, ConversationPreviewRevision>
      _previewProjectionRowRevisions = <String, ConversationPreviewRevision>{};
  bool _previewProjectionDrainScheduled = false;
  bool _conversationWorkEnabled = true;

  static const int _previewProjectionRowsPerFrame = 6;

  ValueListenable<int> _previewProjectionRevisionOf(String conversationId) {
    final id = conversationId.trim();
    return _previewProjectionRowRevisions.putIfAbsent(
      id,
      ConversationPreviewRevision.new,
    );
  }

  ConversationPreviewToken _previewProjectionToken(
    TUIChatGlobalModel globalModel,
    V2TimConversation conversation,
  ) {
    final cacheKey = ConversationPreviewHistorySync.conversationMessageCacheKey(
        conversation);
    final conversationId = conversation.conversationID.trim();
    final revisionKey =
        cacheKey?.isNotEmpty == true ? cacheKey! : conversationId;
    return ConversationPreviewToken(
      message: conversation.lastMessage,
      conversationKey: revisionKey,
      listRevision: globalModel.messageListRevisionFor(revisionKey),
      projectionRevision: globalModel.messageProjectionRevisionFor(revisionKey),
    );
  }

  V2TimMessage? _previewLastMessageFor(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final token = _previewProjectionToken(globalModel, conversation);
    final cached = _previewProjectionByConversation[id];
    if (cached != null && cached.token == token.token) {
      return cached.message;
    }
    // Never scan a chat projection from a row build. Keep the previous preview
    // for this frame and reconcile it in the next frame's bounded work batch.
    _queuePreviewProjection(conversation, capturedToken: token);
    return cached?.message ?? conversation.lastMessage;
  }

  void _queuePreviewProjection(V2TimConversation conversation,
      {ConversationPreviewToken? capturedToken}) {
    if (!_conversationWorkEnabled) return;
    final id = conversation.conversationID.trim();
    if (id.isEmpty) return;
    final token = capturedToken ?? _previewProjectionToken(
      serviceLocator<TUIChatGlobalModel>(),
      conversation,
    );
    if (_previewProjectionByConversation[id]?.token == token.token) {
      _pendingPreviewProjectionRows.remove(id);
      return;
    }
    _pendingPreviewProjectionRows[id] = conversation;
    if (_previewProjectionDrainScheduled) return;
    _previewProjectionDrainScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _drainPreviewProjectionRows();
    });
  }

  void _queueVisiblePreviewProjections() {
    if (!_conversationWorkEnabled) return;
    // A filtered conversation list includes every loaded row, not just the
    // viewport. Only mounted row builders subscribe to these notifiers.
    // Newly mounted rows request their own projection in _previewLastMessageFor.
    final observedIds = <String>{
      for (final entry in _previewProjectionRowRevisions.entries)
        if (entry.value.isObserved) entry.key,
    };
    if (observedIds.isEmpty) return;
    final store = ConversationTabStore.instance;
    for (final conversation in resolveObservedConversationRows(
      observedIds: observedIds,
      lookup: (id) => store.conversationForId(id) ??
          _folderSdkRows[ConversationIdCanonical.forStorage(id)] ??
          _visibleOfficialPlaceholders[ConversationIdCanonical.forStorage(id)],
    )) {
      _queuePreviewProjection(conversation);
    }
  }

  void _drainPreviewProjectionRows() {
    if (!mounted || !_conversationWorkEnabled) {
      _pendingPreviewProjectionRows.clear();
      _previewProjectionDrainScheduled = false;
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final ids = _pendingPreviewProjectionRows.keys
        .take(_previewProjectionRowsPerFrame)
        .toList(growable: false);
    for (final id in ids) {
      final conversation = _pendingPreviewProjectionRows.remove(id);
      if (conversation == null) continue;
      // The row may have left the viewport after it queued this work.
      if (_previewProjectionRowRevisions[id]?.isObserved != true) continue;
      final token = _previewProjectionToken(globalModel, conversation);
      final previous = _previewProjectionByConversation[id];
      if (previous?.token == token.token) continue;
      final resolved =
          ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
        globalModel: globalModel,
        conversation: conversation,
      );
      _previewProjectionByConversation[id] =
          _ConversationPreviewProjectionEntry(
        token: token.token,
        message: resolved,
        capturedFingerprint: identical(resolved, conversation.lastMessage)
            ? token.messageFingerprint : null,
      );
      // On the first projection pass the row may currently be showing
      // `conversation.lastMessage`. Compare against that fallback as well so
      // the asynchronously precomputed result is painted when it differs.
      final paintedFingerprint = previous?.messageFingerprint ??
          token.messageFingerprint;
      final changed = paintedFingerprint !=
          _previewProjectionByConversation[id]!.messageFingerprint;
      if (changed) {
        final notifier = _previewProjectionRowRevisions[id];
        if (notifier != null) notifier.value++;
      }
    }
    if (_pendingPreviewProjectionRows.isEmpty) {
      _previewProjectionDrainScheduled = false;
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _drainPreviewProjectionRows();
    });
  }

  void _invalidateVisibleConversationsCache() {
    _visibilityRevision++;
    _cachedVisibleConversationIds = null;
    _visibleConversationView = null;
    _visiblePositions.clear();
    _visibleUsesFullStoreView = false;
    _visibleCacheContentRevision = -1;
    _visibleOfficialPlaceholders.clear();
    _visibleCacheIdentity = null;
    _cachedVisibleIds = const <String>{};
    _visibleCacheSourceLength = -1;
    _visibleCacheSourceIds = const <String>{};
    _visibleCacheStructureRevision = -1;
    _visibleCacheVisibilityRevision = -1;
  }

  void _onSessionProjectionChanged() {
    if (!_conversationWorkEnabled) {
      ConversationFeedPerf.increment('visible_projection_inactive_skip');
      return;
    }
    final revision = ChatSessionController.instance.structureRevision;
    // Content-only updates (unread, draft, avatar, nickname, read status)
    // keep the visible ID/order set stable. Do not rerun the full membership
    // and archive filter for those notifications.
    if (_visibleCacheStructureRevision != revision) {
      // Keep the previous visible membership. _getVisibleConversations can
      // refresh row references in current source order when the source length
      // is unchanged. Insert/remove or visibility changes still fall back to
      // the full filter path.
      ConversationFeedPerf.increment('visible_projection_dirty');
    }
    _queueVisiblePreviewProjections();
  }

  void _selectFolder(String? folderId) {
    final trimmed = folderId?.trim();
    final normalized = trimmed?.isEmpty == true ? null : trimmed;
    if (normalized == _selectedFolderId) {
      if (normalized != null &&
          _folderSdkLookupRetryable &&
          _folderHydratingGeneration != _folderHydrateGeneration) {
        setState(() => _hydrateFolderRows(normalized));
      }
      return;
    }
    _folderHydrateGeneration++;
    setState(() {
      _invalidateVisibleConversationsCache();
      _selectedFolderId = normalized;
      _folderSdkRows.clear();
      _folderSdkDeletedIds.clear();
      _folderSdkMemberIds = const <String>{};
      _folderSdkIdentity = null;
      _folderSdkLookupRetryable = false;
    });
    final selected = _selectedFolderId;
    if (selected == null) return;
    _hydrateFolderRows(selected);
  }

  void _selectAdjacentFolderFromSwipe(int direction) {
    if (_folderReorderEditing || _isEditing) return;
    final folders = ConversationFolderStore.instance.folders;
    final selection = conversationFolderAfterSwipe(
      folderIds:
          folders.map((folder) => folder.folderId).toList(growable: false),
      selectedFolderId: _selectedFolderId,
      direction: direction,
    );
    if (selection.changed) _selectFolder(selection.folderId);
  }

  void _hydrateFolderRows(String selected) {
    final identity = SessionIdentityService.instance.capture();
    final folder = ConversationFolderStore.instance.folderById(selected);
    final sdkIdsByKey = <String, String>{
      if (folder != null)
        for (final id in folder.conversationIds)
          ConversationIdCanonical.forStorage(id): id.trim(),
    };
    final memberIds = sdkIdsByKey.keys.toSet();
    final previousIdentity = _folderSdkIdentity;
    if (previousIdentity != null &&
        SessionIdentityService.instance.isCurrent(previousIdentity) &&
        !_folderSdkLookupRetryable &&
        memberIds.length == _folderSdkMemberIds.length &&
        memberIds.every(_folderSdkMemberIds.contains)) {
      return;
    }
    final generation = ++_folderHydrateGeneration;
    if (previousIdentity == null ||
        !SessionIdentityService.instance.isCurrent(previousIdentity)) {
      _folderSdkRows.clear();
      _folderSdkDeletedIds.clear();
    } else {
      _folderSdkRows.removeWhere((id, _) => !memberIds.contains(id));
      _folderSdkDeletedIds.removeWhere((id) => !memberIds.contains(id));
    }
    _folderSdkMemberIds = memberIds;
    _folderSdkLookupRetryable = false;
    _folderSdkIdentity = identity;
    _invalidateVisibleConversationsCache();
    if (identity.ownerUserId.isEmpty ||
        folder == null ||
        folder.conversationIds.isEmpty) return;
    final store = ConversationTabStore.instance;
    final missingIds = memberIds
        .where((id) =>
            !_folderSdkDeletedIds.contains(id) &&
            store.conversationForId(sdkIdsByKey[id]!) == null &&
            !_folderSdkRows.containsKey(id))
        .map((id) => sdkIdsByKey[id]!)
        .toList(growable: false);
    if (missingIds.isEmpty) return;
    _folderHydratingGeneration = generation;
    final syncReadyRevision = _folderSyncReadyRevision;
    bool isCurrent() =>
        mounted &&
        generation == _folderHydrateGeneration &&
        _selectedFolderId == selected &&
        SessionIdentityService.instance.isCurrent(identity);
    unawaited(() async {
      for (var offset = 0; offset < missingIds.length; offset += 100) {
        if (!isCurrent()) return;
        final end = (offset + 100).clamp(0, missingIds.length).toInt();
        try {
          final result = await store
              .readSdkConversationsByIds(missingIds.sublist(offset, end));
          if (!isCurrent()) return;
          if (result.code != 0) {
            _folderSdkLookupRetryable = true;
            continue;
          }
          setState(() {
            for (final row in result.conversationList) {
              if (!folder.containsConversationId(row.conversationID)) continue;
              final key =
                  ConversationIdCanonical.forStorage(row.conversationID);
              if (_folderSdkDeletedIds.contains(key)) continue;
              _folderSdkRows[key] = row;
            }
            // A successful SDK call may still be incomplete during roaming.
            // Missing members are unresolved, not proof of an empty folder.
            if (missingIds.sublist(offset, end).any((id) =>
                !_folderSdkDeletedIds
                    .contains(ConversationIdCanonical.forStorage(id)) &&
                !_folderSdkRows
                    .containsKey(ConversationIdCanonical.forStorage(id)) &&
                store.conversationForId(id) == null)) {
              _folderSdkLookupRetryable = true;
            }
            _invalidateVisibleConversationsCache();
          });
        } catch (error) {
          if (!isCurrent()) return;
          _folderSdkLookupRetryable = true;
          debugPrint('Folder SDK lookup failed: $error');
        }
      }
      // Only this folder visit can finish its loading state. An old response
      // must not dismiss the next folder's placeholder (including A -> B -> A).
      if (!isCurrent()) return;
      setState(() {
        _folderHydratingGeneration = null;
        // Sync may finish while this request is still in flight. Consume that
        // readiness change once, without polling or overlapping SDK batches.
        if (_folderSdkLookupRetryable &&
            syncReadyRevision != _folderSyncReadyRevision) {
          _hydrateFolderRows(selected);
        }
      });
    }());
  }

  void _forgetDeletedFolderRow(
    String conversationId,
    SessionIdentity expectedIdentity,
  ) {
    if (!mounted ||
        !SessionIdentityService.instance.isCurrent(expectedIdentity)) return;
    final selected = _selectedFolderId;
    if (selected == null) return;
    final folder = ConversationFolderStore.instance.folderById(selected);
    if (folder?.containsConversationId(conversationId) != true) return;
    final key = ConversationIdCanonical.forStorage(conversationId);
    _folderSdkDeletedIds.add(key);
    _folderSdkRows.remove(key);
    _invalidateVisibleConversationsCache();
  }

  void _onSdkDeletedFolderRows() {
    if (!mounted || _selectedFolderId == null) return;
    final identity = SessionIdentityService.instance.capture();
    final previousRevision = _visibilityRevision;
    for (final id
        in ChatSessionController.instance.sdkDeletedConversationIds.value) {
      _forgetDeletedFolderRow(id, identity);
    }
    if (_visibilityRevision != previousRevision) setState(() {});
  }

  void _onArchivedIdsChangedForMainList() {
    _folderUnreadConfigurationRevision++;
    _folderUnreadForceFull = true;
    _scheduleFolderUnreadRefresh();
    // 主列表同步由进程级同步单例监听负责，此处只刷新本页可见缓存。
    _invalidateVisibleConversationsCache();
    if (mounted) {
      setState(() {});
    }
  }

  void _onJoinedGroupsRevision() {
    _invalidateVisibleConversationsCache();
    if (mounted) {
      setState(() {});
    }
  }

  void _onGroupCacheHydrated() {
    if (GroupLocalStore.instance.cacheHydration.value.ownerUserId !=
        GroupLocalStore.instance.currentOwnerUserId()) return;
    _onJoinedGroupsRevision();
  }

  void _onGroupStoreCommitForDisplay() {
    final commit = GroupLocalStore.instance.commitListenable.value;
    if (commit.upserted.isEmpty && commit.deletedGroupIds.isEmpty) {
      return;
    }
    final conversationIds = <String>{};
    for (final record in commit.upserted) {
      final gid = record.groupId.trim();
      if (gid.isEmpty) {
        continue;
      }
      conversationIds.add(gid.startsWith('group_') ? gid : 'group_$gid');
    }
    ChatSessionController.instance.bumpRowRevisions(conversationIds);
    _onJoinedGroupsRevision();
  }

  bool get _hostsDesktopLoginBanner {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _refreshDesktopLoginBanner({
    String reason = 'manual',
    bool force = false,
  }) {
    if (!_hostsDesktopLoginBanner) {
      return Future<void>.value();
    }
    return DesktopLoginSessionService.instance.refresh(
      reason: reason,
      force: force,
    );
  }

  void _scheduleDesktopLoginBannerRefreshOnVisible(bool routeVisible) {
    if (!_hostsDesktopLoginBanner) {
      _wasRouteVisibleForDesktopBanner = routeVisible;
      return;
    }
    if (routeVisible && !_wasRouteVisibleForDesktopBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_refreshDesktopLoginBanner(reason: 'visible'));
      });
    }
    _wasRouteVisibleForDesktopBanner = routeVisible;
  }

  ConversationArchiveScope get _archiveScope =>
      archiveScopeForListScope(widget.listScope);

  ValueNotifier<Set<String>> get _archivedIDsNotifier =>
      archivedConversationIDsNotifierFor(_archiveScope);

  String get _previewCacheScopeKey {
    if (widget.listScope == ConversationListScope.group) {
      return 'group';
    }
    if (widget.listScope == ConversationListScope.all) {
      return 'all';
    }
    return 'c2c';
  }

  /// 会话页可能早于 IM Login 挂载；未登录时跳过公众号资料预取。
  Future<void> _ensureOfficialAccountsAfterImLogin() async {
    try {
      final login = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
      final userId = login.data?.trim() ?? '';
      if (userId.isEmpty) {
        return;
      }
      await PlatformOfficialAccountService.loadDismissedState(force: true);
      await PlatformOfficialAccountService.ensureSubscribed();
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stickers = Provider.of<CustomStickerPackageData>(context);
    final locale = Localizations.localeOf(context);
    final token = Object.hash(
      identityHashCode(stickers.customStickerPackageList),
      locale,
    );
    if (_previewEmojiToken != token) {
      _previewEmojiToken = token;
      _previewEmojiList = _conversationPreviewEmojiList(context);
    }
  }

  @override
  void initState() {
    super.initState();
    StartupPerfLog.markTagged(
      'conversation_init_start',
      category: 'cold_start',
      details: <String, Object>{'scope': widget.listScope.name},
    );
    _controller = widget.conversationController;
    ConversationHistoryWarmScheduler.instance.armLaunchWarmSuppress();
    if (archivedConversationPersistToDisk) {
      ensureArchivedConversationIDsLoaded();
    }
    ArchivedConversationEntryVisibility.instance.ensureStarted();
    conversationToggleEditModeActions[widget.listScope] = toggleEditMode;
    if (widget.hostEditActionBar) {
      conversationEditActionBarBuilders[widget.listScope] = (theme) =>
          AnimatedBuilder(
            animation: _selectionRevision,
            builder: (_, __) => _buildEditBottomActionBar(theme),
          );
    }
    conversationToggleSelectAllActions[widget.listScope] = toggleSelectAll;
    conversationScrollNextUnreadActions[widget.listScope] =
        scrollToNextUnreadConversation;
    conversationScrollToTopActions[widget.listScope] = scrollFeedToTop;
    if (kIsWeb) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) {
          return;
        }
        unawaited(GroupNoticeUnreadService.instance.ensureLoaded());
        unawaited(GroupNoticeEntrySettingsService.instance.ensureLoaded());
        unawaited(ConversationFolderStore.instance.ensureLoaded());
      });
    } else {
      unawaited(GroupNoticeUnreadService.instance.ensureLoaded());
      unawaited(GroupNoticeEntrySettingsService.instance.ensureLoaded());
      unawaited(ConversationFolderStore.instance.ensureLoaded());
    }
    ConversationFolderStore.instance.foldersNotifier.addListener(
      _onFoldersChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        StartupPerfLog.markTagged(
          'conversation_postframe',
          category: 'cold_start',
          details: <String, Object>{'scope': widget.listScope.name},
        );
        _syncEditingStateNotifiers();
        if (kIsWeb) {
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _syncWebGroupConversations();
            }
          });
        } else {
          _syncWebGroupConversations();
        }
      }
    });
    if (kIsWeb) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) {
          return;
        }
        unawaited(_ensureOfficialAccountsAfterImLogin());
      });
    } else {
      // Official-account metadata is not required for the conversation
      // shell. Keep native startup consistent with web and avoid an SDK/API
      // request during conversation init.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          unawaited(_ensureOfficialAccountsAfterImLogin());
        }
      });
    }
    // Cold-start projection is loaded exactly once by
    // _restoreSdkConversationFirstWindow below. A second concurrent restore marks
    // the session projection dirty and causes another whole-window pass after the first.
    if (kIsWeb) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          unawaited(_ensureScopeConversationsHydrated());
        }
      });
    } else {
      // The cached preview is the only data allowed to participate before
      // the first frame. Defer the secondary scope hydration on native too;
      // otherwise it can win the restore single-flight and open SQLite before
      // the shell has painted.
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          unawaited(_ensureScopeConversationsHydrated());
        }
      });
    }
    PlatformOfficialAccountService.infoRevision.addListener(
      _onOfficialInfoUpdated,
    );
    ConversationRefreshBus.instance.revision.addListener(
      _onConversationRefreshRequested,
    );
    PeerProfileRefreshBus.instance.revision.addListener(
      _onPeerProfileRefreshForListCache,
    );
    _ConversationListRefreshCoordinator.register(this);
    _feedScrollController.addListener(_onFeedScroll);
    ConversationListSyncNotifier.instance.addListener(_onFeedSyncStateChanged);
    _wasFeedSyncing = ConversationListSyncNotifier.instance.isSyncing;
    ChatSessionController.instance.listScrollOffsetProvider =
        _currentFeedScrollOffset;
    ChatSessionController.instance.isFeedScrolling = () {
      if (!_feedScrollController.hasClients) {
        return false;
      }
      return _feedScrollController.position.isScrollingNotifier.value;
    };
    ConversationLocalStore.instance.isUiBusyForWriteCoalesce = () {
      final scrolling = ChatSessionController.instance.isFeedScrollingNow;
      return scrolling ||
          ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat;
    };
    GroupLocalStore.instance.isUiBusyForWrite = () {
      final scrolling = ChatSessionController.instance.isFeedScrollingNow;
      return scrolling ||
          ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat;
    };
    _scheduleFolderUnreadRefresh();
    ChatSessionController.instance.addListener(_scheduleFolderUnreadRefresh);
    ConversationUnreadAggregate.instance.sdkUnreadRevision
        .addListener(_scheduleFolderUnreadRefresh);
    _visibleCacheStructureRevision =
        ChatSessionController.instance.structureRevision;
    ChatSessionController.instance.addListener(_onSessionProjectionChanged);
    ChatSessionController.instance.sdkDeletedConversationIds
        .addListener(_onSdkDeletedFolderRows);
    ChatSessionController.instance.ensureArchiveChangeListenersAttached();
    archivedConversationC2cIDsNotifier.addListener(
      _onArchivedIdsChangedForMainList,
    );
    archivedConversationGroupIDsNotifier.addListener(
      _onArchivedIdsChangedForMainList,
    );
    GroupMembershipSyncService.instance.joinedGroupsRevision.addListener(
      _onJoinedGroupsRevision,
    );
    GroupLocalStore.instance.cacheHydration.addListener(_onGroupCacheHydrated);
    GroupLocalStore.instance.commitListenable
        .addListener(_onGroupStoreCommitForDisplay);
    _restoreSdkConversationFirstWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runViewportWarmNow(reason: 'home_visible');
      _queueVisiblePreviewProjections();
    });
    unawaited(ConversationLocalStore.instance.preloadHistoryClearIndex());
    // 首帧不调度视口暖窗，避免与冷启动会话同步争抢导致卡顿；
    // 滚动停稳（scroll_end）与按下（press）仍预热。
    // Desktop login sessions are loaded only when the banner becomes
    // visible. Do not issue /me/devices during conversation cold start.
    StartupPerfLog.markTagged(
      'conversation_init_end',
      category: 'cold_start',
      details: <String, Object>{'scope': widget.listScope.name},
    );
  }

  bool _groupBootstrapQueued = false;

  /// P1-3: 节流 — 同一 widget 生命周期内 N 秒内多次进入群 Tab，
  /// 只触发一次 7×100 的 join-applications 全量拉取。force:true 路径
  /// （approve / reject / delete 等）不受影响。
  static const Duration _groupJoinAppRefreshInterval = Duration(seconds: 30);
  DateTime? _lastGroupJoinAppRefreshAt;
  Future<void>? _groupJoinAppRefreshInFlight;

  void _scheduleGroupBootstrapWhenActive() {
    if (widget.listScope != ConversationListScope.group ||
        _groupBootstrapQueued ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _groupBootstrapQueued = true;
    GroupLiveIndexSyncService.instance.onGroupTabVisible();
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted || !TickerMode.valuesOf(context).enabled) {
        _groupBootstrapQueued = false;
        GroupLiveIndexSyncService.instance.onGroupTabHidden();
        return;
      }
      final now = DateTime.now();
      final lastAt = _lastGroupJoinAppRefreshAt;
      if (lastAt != null &&
          now.difference(lastAt) < _groupJoinAppRefreshInterval) {
        // 节流命中：跳过全量 join-applications 拉取，仍做增量同步。
        await GroupNoticeIncrementalSyncService.instance.sync(
          reason: 'group_tab_active_throttled',
        );
        return;
      }
      // 合并同 in-flight：第二次进来时直接 await 同一个 Future。
      if (_groupJoinAppRefreshInFlight != null) {
        await _groupJoinAppRefreshInFlight;
        return;
      }
      _lastGroupJoinAppRefreshAt = now;
      _groupJoinAppRefreshInFlight = Future.wait<void>([
        GroupJoinApplicationService.instance.refresh(syncMembership: false),
        GroupNoticeIncrementalSyncService.instance.sync(
          reason: 'group_tab_active',
        ),
      ]);
      try {
        await _groupJoinAppRefreshInFlight;
      } finally {
        _groupJoinAppRefreshInFlight = null;
      }
    });
  }

  Widget? _buildConversationNickNameWidget({
    required V2TimConversation conversation,
    required String showName,
    required Color? fallbackTitleColor,
    required double fontSize,
  }) {
    if (widget.listScope == ConversationListScope.group) {
      return buildGroupConversationListNickName(
        userId: conversation.userID,
        name: showName,
        fallbackTitleColor: fallbackTitleColor,
        fontSize: fontSize,
        groupType: conversation.groupType,
        groupId: conversation.groupID,
      );
    }
    return buildConversationListNickName(
      userId: conversation.userID,
      name: showName,
      fallbackTitleColor: fallbackTitleColor,
      fontSize: fontSize,
      groupType: conversation.groupType,
    );
  }

  void _onFoldersChanged() {
    if (!mounted) {
      return;
    }
    // Membership can change in an unselected folder without changing the
    // capsule name or the selected folder's rows.
    _folderUnreadConfigurationRevision++;
    _folderUnreadForceFull = true;
    _scheduleFolderUnreadRefresh();
    final folders = ConversationFolderStore.instance.folders;
    final nextIdentity = folders
        .map((folder) => '${folder.folderId}\u0000${folder.name}')
        .toList(growable: false);
    final identityChanged = !listEquals(nextIdentity, _folderUiIdentity);
    _folderUiIdentity = nextIdentity;

    final selected = _selectedFolderId;
    final selectedMissing = selected != null &&
        ConversationFolderStore.instance.folderById(selected) == null;
    final selectedMembers = selected == null
        ? const <String>{}
        : {
            for (final id in ConversationFolderStore.instance
                    .folderById(selected)?.members.keys ?? const <String>[])
              ConversationIdCanonical.forStorage(id),
          };
    final membershipChanged = selected != null &&
        (selectedMembers.length != _folderSdkMemberIds.length ||
            !selectedMembers.every(_folderSdkMemberIds.contains));

    if (!identityChanged && !selectedMissing && !membershipChanged) {
      // 仅 sortOrder/顺序变化：胶囊条由 ValueListenableBuilder 更新，勿整页 setState。
      return;
    }

    _invalidateVisibleConversationsCache();
    if (selectedMissing) {
      _invalidateVisibleConversationsCache();
      _selectedFolderId = null;
      _folderHydrateGeneration++;
      _folderSdkRows.clear();
      _folderSdkDeletedIds.clear();
      _folderSdkIdentity = null;
    } else if (selected != null) {
      _hydrateFolderRows(selected);
    }
    _folderUnreadForceFull = true;
    _scheduleFolderUnreadRefresh();
    setState(() {});
  }

  void _scheduleFolderUnreadRefresh() {
    if (!_conversationWorkEnabled) {
      _folderUnreadRefreshDeferred = true;
      ConversationFeedPerf.increment('folder_unread_inactive_skip');
      return;
    }
    if (_folderUnreadRefreshInFlight) {
      _folderUnreadRefreshDeferred = true;
      return;
    }
    if (ConversationFolderStore.instance.folders.isEmpty &&
        _folderUnreadById.isEmpty &&
        _folderUnreadIndex.isEmpty &&
        !_folderUnreadForceFull) {
      ConversationFeedPerf.increment('folder_unread_empty_noop');
      return;
    }
    final scrolling = ChatSessionController.instance.isFeedScrollingNow;
    final quiet = ConversationSyncService.instance.isInResumeQuietWindow;
    final inChat = ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat;
    final postLeave = ConversationPerfFlags.folderUnreadDeferOnChatLeave &&
        ChatSessionController.instance.isPostChatLeaveQuiet;
    if (scrolling ||
        inChat ||
        postLeave ||
        (quiet && ConversationPerfFlags.resumeQuietBlocksHeavyUiReload)) {
      ConversationPerfGateLog.log(
        'folder_unread_deferred',
        extras: <String, Object?>{
          'cause': scrolling
              ? 'scroll'
              : (inChat ? 'active_chat' : (postLeave ? 'chat_leave' : 'quiet')),
        },
      );
      if (postLeave) {
        // Preserve a pending folder/archive invalidation during chat leave.
        _folderUnreadLeaveKickTimer?.cancel();
        final remain =
            ChatSessionController.instance.postChatLeaveQuietRemaining;
        _folderUnreadLeaveKickTimer = Timer(
          remain + const Duration(milliseconds: 48),
          () {
            _folderUnreadLeaveKickTimer = null;
            if (mounted) {
              _scheduleFolderUnreadRefresh();
            }
          },
        );
      }
      if (quiet && !scrolling && !inChat && !postLeave) {
        ConversationPerfGateLog.log(
          'resume_quiet_block',
          extras: <String, Object?>{'what': 'folder_unread'},
        );
      }
      _folderUnreadRefreshDeferred = true;
      return;
    }
    _runFolderUnreadRefresh();
  }

  bool _folderUnreadRefreshDeferred = false;
  bool _folderUnreadForceFull = true;

  void _runFolderUnreadRefresh() {
    if (_folderUnreadRefreshInFlight) {
      return;
    }
    final aggregate = ConversationUnreadAggregate.instance;
    final sourceRevision = aggregate.sdkUnreadRevision.value;
    final configurationRevision = _folderUnreadConfigurationRevision;
    final identity = SessionIdentityService.instance.capture();
    final previousIdentity = _folderUnreadIdentity;
    final changedIds = aggregate.rawUnreadChangesSince(_folderUnreadSourceRevision);
    final forceFull = _folderUnreadForceFull ||
        previousIdentity == null ||
        !SessionIdentityService.instance.isCurrent(previousIdentity) ||
        _folderUnreadAppliedConfigurationRevision != configurationRevision ||
        changedIds == null;
    if (!forceFull && changedIds.isEmpty) return;
    if (ConversationPerfFlags.folderUnreadSingleFlightEnabled &&
        FolderUnreadRefreshGate.markJoinIfBusy()) {
      _folderUnreadRefreshDeferred = true;
      return;
    }
    final useSingleFlight =
        ConversationPerfFlags.folderUnreadSingleFlightEnabled;
    // 先同步占坑，再跑查库，避免双 Tab 同时开跑。
    final done = Completer<void>();
    final flight = done.future;
    if (useSingleFlight) {
      final claimed = FolderUnreadRefreshGate.tryClaimFlight(done);
      if (claimed == null) {
        _folderUnreadRefreshDeferred = true;
        return;
      }
    }
    _folderUnreadRefreshDeferred = false;
    _folderUnreadRefreshInFlight = true;
    ConversationPerfGateLog.log(
      forceFull ? 'folder_unread_run' : 'folder_unread_incremental',
    );
    unawaited(() async {
      try {
        if (forceFull) {
          _folderUnreadIndex.rebuild({
            for (final folder in ConversationFolderStore.instance.folders)
              folder.folderId: folder.conversationIds
                  .where((id) => !_isConversationArchivedInEitherScope(id))
                  .toList(growable: false),
          });
        }
        final queryIds = forceFull
            ? _folderUnreadIndex.allQueryIds.toSet()
            : _folderUnreadIndex.queryIdsForChanges(changedIds);
        final unreadById = queryIds.isEmpty
            ? const <String, int>{}
            : await aggregate.readSdkUnreadCountsForIds(queryIds);
        if (!mounted ||
            !SessionIdentityService.instance.isCurrent(identity)) {
          return;
        }
        if (configurationRevision != _folderUnreadConfigurationRevision) {
          _folderUnreadRefreshDeferred = true;
          return;
        }
        _folderUnreadIndex.applyCounts(unreadById);
        final next = _folderUnreadIndex.totals;
        _folderUnreadSourceRevision = sourceRevision;
        _folderUnreadAppliedConfigurationRevision = configurationRevision;
        _folderUnreadIdentity = identity;
        _folderUnreadForceFull = false;
        if (!mapEquals(_folderUnreadById, next)) {
          _folderUnreadById..clear()..addAll(next);
          setState(() {});
        }
      } catch (error) {
        if (kDebugMode) debugPrint('Folder unread SDK refresh failed: $error');
      } finally {
        _folderUnreadRefreshInFlight = false;
        if (!done.isCompleted) {
          done.complete();
        }
        final localDeferred = _folderUnreadRefreshDeferred;
        _folderUnreadRefreshDeferred = false;
        if (useSingleFlight) {
          FolderUnreadRefreshGate.onFlightFinished(
            flight,
            onPendingKick: () {
              if (mounted) {
                _scheduleFolderUnreadRefresh();
              }
            },
          );
        }
        if (localDeferred && mounted) {
          scheduleMicrotask(() {
            if (mounted) {
              _scheduleFolderUnreadRefresh();
            }
          });
        }
      }
    }());
  }

  Future<void> _ensureScopeConversationsHydrated() async {
    if (_scopeHydrationInFlight) {
      return;
    }
    _scopeHydrationInFlight = true;
    try {
      // The first-screen projection is restored exactly once by
      // _restoreSdkConversationFirstWindow. Scope hydration is a follow-up
      // reconciliation step; restoring here as well creates a second
      // cold-start projection request and can reopen the DB during first
      // paint.
      await ConversationSyncService.instance.ensureVisibleConversations(
        hasVisibleConversations: () => _getVisibleConversations().isNotEmpty,
        visibleConvType:
            widget.listScope == ConversationListScope.group ? 2 : 1,
        reason: widget.listScope == ConversationListScope.group
            ? 'group_tab'
            : 'c2c_tab',
      );
      if (mounted) {
        setState(() {});
      }
    } finally {
      _scopeHydrationInFlight = false;
      _scopeHydrationFinished = true;
    }
  }

  Future<void> _restoreSdkConversationFirstWindow() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    if (ConversationListSyncNotifier.instance.hasSyncedOnce) {
      return;
    }

    // Let Flutter finish its first frame, then ask the SDK-backed TabStore for
    // the authoritative typed first window. The retired SharedPreferences
    // preview list no longer participates in UI restoration.
    await _waitForConversationFirstFrame();
    if (!mounted ||
        !SessionIdentityService.instance.isCurrent(identity) ||
        ConversationListSyncNotifier.instance.hasSyncedOnce) {
      return;
    }

    await ChatSessionController.instance.restoreProjection(
      reason: ConversationStoreProjectionReason.coldStart,
      visibleConvType: widget.listScope == ConversationListScope.group ? 2 : 1,
    );
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    _suppressFeedPaging(const Duration(milliseconds: 800));
    _viewportFillDone = false;
    _viewportFillPagesDone = 0;
    if (!mounted || ConversationListSyncNotifier.instance.hasSyncedOnce) {
      return;
    }
    if (ChatSessionController.instance.hasLocalData) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_maybeFillFeedViewportOnce());
        }
      });
      return;
    }
  }

  Future<void> _waitForConversationFirstFrame() {
    final gate = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
    return gate.future;
  }

  void _onOfficialInfoUpdated() {
    _invalidateVisibleConversationsCache();
    if (mounted) setState(() {});
  }

  void _onPeerProfileRefreshForListCache() {
    final latest = PeerProfileRefreshBus.instance.latestChangedUserIds;
    if (latest.isNotEmpty) {
      final revision = PeerProfileRefreshBus.instance.revision.value;
      final conversationIds = <String>{};
      for (final userId in latest) {
        ChatSessionController.instance.applyPeerDisplayNameFromStore(
          userId,
          busRevision: revision,
        );
        conversationIds.add('c2c_$userId');
      }
      ChatSessionController.instance.bumpRowRevisions(conversationIds);
    }
    _invalidateVisibleConversationsCache();
    if (mounted) {
      setState(() {});
    }
  }

  void _onConversationRefreshRequested() {
    if (!mounted) return;
    final bus = ConversationRefreshBus.instance;
    final events = bus.lastEvents.isNotEmpty
        ? bus.lastEvents
        : <ConversationRefreshEvent>[
            ConversationRefreshEvent(
              sequence: 0,
              reason: bus.lastReason,
              conversationId: bus.lastConversationId,
            ),
          ];
    String? fullRefreshReason;
    for (final event in events) {
      final reason = event.reason;
      ConversationPinFlickerLog.log(
        'refresh_bus',
        conversationID: event.conversationId,
        extras: <String, Object?>{
          'reason': reason,
          'patchOnly': _shouldPatchConversationOnly(reason),
          'deferring': ChatSessionController.instance.isDeferringPinReorder,
        },
      );
      if (!_shouldPatchConversationOnly(reason)) {
        fullRefreshReason = reason;
        continue;
      }
      if (reason == 'new_message' || _isReadStatePatchReason(reason)) {
        _patchConversationTimer?.cancel();
        _patchConversationUpdates(
          reason: reason,
          conversationId: event.conversationId,
        );
        continue;
      }
      _queuePatchConversationUpdates(
        reason: reason,
        conversationId: event.conversationId,
      );
    }
    if (fullRefreshReason != null) {
      _ConversationListRefreshCoordinator.scheduleFullRefresh(
        reason: fullRefreshReason,
      );
    }
  }

  void _queuePatchConversationUpdates({
    String? reason,
    String? conversationId,
  }) {
    _lastPatchReason = reason;
    _pendingPatchConversationIds.addAll(
      _collectPatchConversationIds(
        reason: reason,
        conversationId: conversationId,
      ),
    );
    _patchConversationTimer?.cancel();
    _patchConversationTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      final ids = Set<String>.from(_pendingPatchConversationIds);
      _pendingPatchConversationIds.clear();
      _flushPatchConversationIds(ids, reason: _lastPatchReason);
    });
  }

  Set<String> _collectPatchConversationIds({
    String? reason,
    String? conversationId,
  }) {
    if (reason == 'new_message' || _isReadStatePatchReason(reason)) {
      return const <String>{};
    }
    final conversationIDs = <String>{};
    if (_isFriendPatchReason(reason)) {
      final busConversationID = conversationId;
      if (busConversationID != null && busConversationID.isNotEmpty) {
        conversationIDs.add(busConversationID);
      }
      return conversationIDs;
    }
    final busConversationID = conversationId;
    if (busConversationID != null && busConversationID.isNotEmpty) {
      conversationIDs.add(busConversationID);
    }
    final selectedConversationID =
        _controller.selectedConversation?.conversationID ??
            widget.selectedConversation?.conversationID;
    if (selectedConversationID != null && selectedConversationID.isNotEmpty) {
      conversationIDs.add(selectedConversationID);
    }
    return conversationIDs;
  }

  void _flushPatchConversationIds(
    Set<String> conversationIDs, {
    String? reason,
  }) {
    if (conversationIDs.isEmpty) {
      return;
    }
    for (final conversationID in conversationIDs) {
      try {
        unawaited(
          ConversationSyncService.instance.refreshConversationItem(
            conversationID,
          ),
        );
      } catch (_) {}
    }
    _syncWebGroupConversations();
  }

  bool _isFriendPatchReason(String? reason) {
    return reason == 'friend_became_friends' ||
        reason == 'friend_became_friends_sent' ||
        reason == 'friend_application_refresh' ||
        reason == 'friend_application_added' ||
        reason == 'friend_list_changed';
  }

  bool _isReadStatePatchReason(String? reason) {
    return reason == 'conversation_read' ||
        reason == 'conversation_mark_read' ||
        reason == 'conversation_archive_read';
  }

  bool _shouldPatchConversationOnly(String? reason) {
    return reason == 'conversation_read' ||
        reason == 'conversation_mark_read' ||
        reason == 'conversation_archive_read' ||
        reason == 'wallet_chat_card' ||
        reason == 'wallet_chat_card_failed' ||
        reason == 'message_resend_success' ||
        reason == 'outgoing_message_sent' ||
        reason == 'new_message' ||
        reason == 'wallet_message_sent' ||
        reason == 'contact_card_sent' ||
        reason == 'call_history_message' ||
        reason == 'chat_recovery' ||
        reason == 'friend_became_friends' ||
        reason == 'friend_became_friends_sent' ||
        reason == 'friend_application_refresh' ||
        reason == 'friend_application_added' ||
        reason == 'friend_list_changed';
  }

  double? _currentFeedScrollOffset() {
    if (!_feedScrollController.hasClients) {
      return null;
    }
    return _feedScrollController.offset;
  }

  void _scheduleFeedScrollRestore(double offset, {VoidCallback? onRestored}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final currentOffset = _currentFeedScrollOffset();
      final maxExtent = _feedScrollController.hasClients
          ? _feedScrollController.position.maxScrollExtent
          : 0.0;
      final isUserScrolling = _feedScrollController.hasClients &&
          _feedScrollController.position.isScrollingNotifier.value;
      final decision = FeedScrollRestorePolicy.evaluate(
        pendingOffset: offset,
        currentOffset: currentOffset,
        maxScrollExtent: maxExtent,
        isSyncing: ConversationListSyncNotifier.instance.isSyncing,
        isLoadingConversationData: _controller.model.isLoadingConversationData,
        isUserScrolling: isUserScrolling,
      );
      if (!decision.shouldRestore) {
        if (decision.reason != 'no_clients') {
          onRestored?.call();
        }
        return;
      }
      _feedScrollController.jumpTo(decision.targetOffset!);
      onRestored?.call();
    });
  }

  void _restoreFeedScrollOffsetOnce() {
    final pendingOffset = _pendingFeedScrollRestoreOffset;
    if (pendingOffset == null) {
      return;
    }
    _scheduleFeedScrollRestore(
      pendingOffset,
      onRestored: () {
        if (_pendingFeedScrollRestoreOffset == pendingOffset) {
          _pendingFeedScrollRestoreOffset = null;
        }
      },
    );
  }

  void _cancelFeedScrollStableRestore() {
    _feedScrollStableRestoreTimer?.cancel();
    _feedScrollStableRestoreTimer = null;
    final listener = _feedScrollStableRestoreListener;
    if (listener != null) {
      ChatSessionController.instance.removeListener(listener);
      _feedScrollStableRestoreListener = null;
    }
  }

  void _waitForFeedListStableThenRestore() {
    _cancelFeedScrollStableRestore();

    void tryRestore() {
      if (!mounted) {
        _cancelFeedScrollStableRestore();
        return;
      }
      if (!ConversationListSyncNotifier.instance.isSyncing &&
          !_controller.model.isLoadingConversationData) {
        _cancelFeedScrollStableRestore();
        _restoreFeedScrollOffsetOnce();
      }
    }

    _feedScrollStableRestoreListener = tryRestore;
    ChatSessionController.instance.addListener(tryRestore);
    _feedScrollStableRestoreTimer = Timer(
      const Duration(milliseconds: 1200),
      () {
        if (!mounted) {
          _cancelFeedScrollStableRestore();
          return;
        }
        _cancelFeedScrollStableRestore();
        _restoreFeedScrollOffsetOnce();
      },
    );
    tryRestore();
  }

  void _patchCurrentConversation() {
    _patchConversationUpdates();
  }

  void _patchConversationUpdates({
    String? reason,
    String? conversationId,
  }) {
    if (reason == 'new_message') {
      // 预览由 ConversationSyncService 的入站消息补丁即时写入；
      // 通知服务仍可提供同一补丁作为兜底，勿在这里 refreshConversationItem
      // 抢写旧的 SDK 会话快照。
      return;
    }
    if (_isReadStatePatchReason(reason)) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _flushPatchConversationIds(
      _collectPatchConversationIds(
        reason: reason,
        conversationId: conversationId,
      ),
      reason: reason,
    );
  }

  void _suppressFeedPaging(Duration duration) {
    final until = DateTime.now().add(duration);
    final current = _suppressFeedPagingUntil;
    if (current == null || until.isAfter(current)) {
      _suppressFeedPagingUntil = until;
      _feedPagingResumeTimer?.cancel();
      _feedPagingResumeTimer = Timer(duration, () {
        _feedPagingResumeTimer = null;
        _suppressFeedPagingUntil = null;
        if (mounted) _continueFeedPagingIfNeeded();
      });
    }
  }

  bool get _isFeedPagingSuppressed {
    final until = _suppressFeedPagingUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _onFeedScroll() {
    if (!_feedScrollController.hasClients) {
      return;
    }
    _lastKnownFeedScrollOffset = _feedScrollController.offset;
    _attachFeedScrollingNotifier();
    _handleFeedScrollingState(
      _feedScrollController.position.isScrollingNotifier.value,
    );
    _publishViewportAnchorFromScroll();
    if (_isFeedPagingSuppressed) {
      return;
    }
    final position = _feedScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    final pixels = position.pixels;
    final lastPixels = _lastFeedScrollPixelsForDirection;
    _lastFeedScrollPixelsForDirection = pixels;
    final scrollingDown = lastPixels != null && pixels > lastPixels + 2.0;
    final scrollingUp = lastPixels != null && pixels < lastPixels - 2.0;

    // 只在「正在下滑」时触底续载。软裁后 Flutter 常把 offset 夹到 maxExtent，
    // 若这里无条件距底 240 就 append，会 50ms 一页把 3000 条瞬间滑完（日志连环 trimStart=40）。
    if (scrollingDown && !_hasFeedLookaheadBuffer()) {
      _scheduleFeedPageLoad(allowSdk: true);
      return;
    }
    if (scrollingUp &&
        _feedWindowTrimmed() &&
        conversationFeedNeedsNewerPrefix(
          viewportHeight: position.viewportDimension,
          pixels: pixels,
        )) {
      _scheduleFeedNewerRestore();
    }
  }

  void _attachFeedScrollingNotifier() {
    if (!_feedScrollController.hasClients) {
      return;
    }
    final notifier = _feedScrollController.position.isScrollingNotifier;
    if (identical(_feedScrollingNotifier, notifier)) {
      return;
    }
    _feedScrollingNotifier?.removeListener(_onFeedScrollingNotifier);
    _feedScrollingNotifier = notifier;
    _feedScrollingNotifier!.addListener(_onFeedScrollingNotifier);
  }

  void _onFeedScrollingNotifier() {
    final scrolling = _feedScrollingNotifier?.value ?? false;
    _handleFeedScrollingState(scrolling);
  }

  void _handleFeedScrollingState(bool scrolling) {
    if (scrolling && !_feedWasScrolling) {
      _feedWasScrolling = true;
      _feedScrollEndSettleTimer?.cancel();
      _feedScrollEndSettleTimer = null;
      _viewportWarmSettleTimer?.cancel();
      ConversationSyncService.instance.onFeedScrollStarted();
      ConversationHistoryWarmScheduler.instance.setFeedScrolling(
        true,
        reason: 'scroll_start',
      );
      ChatCoverageRepairScheduler.instance.pause(reason: 'feed_scroll');
      OpenViewportCache.instance.pause(reason: 'feed_scroll');
    } else if (!scrolling && _feedWasScrolling) {
      _feedWasScrolling = false;
      ConversationHistoryWarmScheduler.instance.setFeedScrolling(
        false,
        reason: 'scroll_end',
      );
      ChatCoverageRepairScheduler.instance.resume();
      OpenViewportCache.instance.resume();
      _scheduleFeedScrollEndSettleWork();
    }
  }

  void _scheduleFeedScrollEndSettleWork() {
    _feedScrollEndSettleTimer?.cancel();
    _feedScrollEndSettleTimer = Timer(_feedScrollEndSettleDelay, () {
      _feedScrollEndSettleTimer = null;
      if (!mounted) {
        return;
      }
      if (_feedScrollController.hasClients &&
          _feedScrollController.position.isScrollingNotifier.value) {
        _scheduleFeedScrollEndSettleWork();
        return;
      }
      _onFeedScrollEndSettled();
    });
  }

  void _onFeedScrollEndSettled() {
    _flushPendingFeedScrollTarget();
    ConversationSyncService.instance
        .flushDeferredProjectionRestoreAfterScroll();
    ChatSessionController.instance.flushDeferredUiNotifyIfNeeded(
      reason: 'scroll_end',
    );
    if (_feedScrollController.hasClients) {
      final position = _feedScrollController.position;
      if (position.pixels <= _feedRowEstimateHeight) {
        _restoreTrimmedFeedHeadIfNeeded();
      }
      if (position.maxScrollExtent > 0 &&
          position.pixels >= position.maxScrollExtent - 480) {
        _scheduleFeedPageLoad();
      }
    }
    final skipWarmAndFolderUnread =
        _feedPageLoadInFlight || _feedSkipViewportWarmOnNextSettle;
    if (!_feedPageLoadInFlight && _feedSkipViewportWarmOnNextSettle) {
      _feedSkipViewportWarmOnNextSettle = false;
    }
    if (!skipWarmAndFolderUnread) {
      if (_folderUnreadRefreshDeferred) {
        _scheduleFolderUnreadAfterScrollSettle();
      }
      _scheduleViewportWarmAfterSettle(reason: 'scroll_end');
    }
  }

  void _scheduleFolderUnreadAfterScrollSettle() {
    _folderUnreadSettleTimer?.cancel();
    final settle = ConversationPerfFlags.folderUnreadSettleAfterScroll;
    if (settle <= Duration.zero) {
      _scheduleFolderUnreadRefresh();
      return;
    }
    _folderUnreadSettleTimer = Timer(settle, () {
      _folderUnreadSettleTimer = null;
      if (!mounted) {
        return;
      }
      final scrolling = ChatSessionController.instance.isFeedScrollingNow;
      if (scrolling) {
        _folderUnreadRefreshDeferred = true;
        return;
      }
      _scheduleFolderUnreadRefresh();
    });
  }

  void _scheduleViewportWarmAfterSettle({required String reason}) {
    _viewportWarmSettleTimer?.cancel();
    _viewportWarmSettleTimer = Timer(_viewportWarmSettleDelay, () {
      if (!mounted) {
        return;
      }
      if (_feedScrollController.hasClients &&
          _feedScrollController.position.isScrollingNotifier.value) {
        return;
      }
      _runViewportWarmNow(reason: reason);
    });
  }

  void _runViewportWarmNow({required String reason}) {
    if (!mounted) {
      return;
    }
    if (!_feedScrollController.hasClients) {
      return;
    }
    final position = _feedScrollController.position;
    final visible = _getVisibleConversations();
    ChatCoverageRepairScheduler.instance.resume();
    final rows = buildConversationFeedRows(
      conversations: visible,
      includeArchivedEntry: _selectedFolderId == null &&
          ArchivedConversationEntryVisibility.instance
              .shouldShow(_archiveScope),
      includeGroupNoticeEntry: _selectedFolderId == null &&
          widget.listScope == ConversationListScope.group,
      applications: GroupJoinApplicationService.instance.applications,
      notices: GroupSystemNoticeService.instance.notices,
      conversationTimestampMs: _getConversationTimestampMs,
      groupNoticePinned: GroupNoticeEntrySettingsService.instance.isPinned,
      groupNoticeDismissWatermarkMs:
          GroupNoticeEntrySettingsService.instance.dismissWatermarkMs,
    );
    final rowConversations = <V2TimConversation?>[
      for (final row in rows)
        row.kind == ConversationFeedRowKind.conversation
            ? row.conversation
            : null,
    ];
    if (widget.listScope == ConversationListScope.group) {
      final candidate =
          ConversationHistoryWarmScheduler.selectViewportCenterCandidate(
        rowConversations: rowConversations,
        scrollOffset: position.pixels,
        viewportHeight: position.viewportDimension,
      );
      if (candidate == null) {
        return;
      }
      ConversationHistoryWarmScheduler.instance.scheduleViewportWarm(
        visibleOrdered: <V2TimConversation>[candidate],
        reason: '${reason}_${widget.listScope.name}_center_one',
      );
      ChatCoverageRepairScheduler.instance.schedule(
        <V2TimConversation>[candidate],
        reason: '${reason}_${widget.listScope.name}_center_one',
        currentVisible: _getVisibleConversations,
      );
      unawaited(
        OpenViewportCache.instance.prepareVisible(
          visible: <V2TimConversation>[candidate],
          viewportHeight: position.viewportDimension,
          reason: '${reason}_${widget.listScope.name}_center_one',
        ),
      );
      return;
    }
    final candidates =
        ConversationHistoryWarmScheduler.selectViewportCandidates(
      rowConversations: rowConversations,
      scrollOffset: position.pixels,
      viewportHeight: position.viewportDimension,
    );
    ConversationHistoryWarmScheduler.instance.scheduleViewportWarm(
      visibleOrdered: candidates,
      reason: '${reason}_${widget.listScope.name}',
    );
    ChatCoverageRepairScheduler.instance.schedule(
      candidates,
      reason: '${reason}_${widget.listScope.name}',
      currentVisible: _getVisibleConversations,
    );
    unawaited(
      OpenViewportCache.instance.prepareVisible(
        visible: candidates,
        viewportHeight: position.viewportDimension,
        reason: '${reason}_${widget.listScope.name}',
      ),
    );
  }

  void _warmConversationOnPress(V2TimConversation conversation) {
    final isGroup = conversationMatchesScope(
      conversation,
      ConversationListScope.group,
    );
    if (isGroup) {
      if (!ConversationPerfFlags.groupPressWarmOnTapDownEnabled) {
        return;
      }
    } else if (!ConversationPerfFlags.pressWarmOnTapDownEnabled) {
      return;
    }
    if (_isEditing || !ConversationHistoryWarmScheduler.viewportWarmEnabled) {
      return;
    }
    // User-directed reads share the navigation/page flight and are independent
    // of background viewport warm pauses. This path stays local-only.
    unawaited(ChatOpenViewportCoordinator.instance.ensureLocalSnapshotForOpen(
      conversation: conversation,
    ));
    ChatImageMessagePrefetch.prefetchForConversation(conversation);
  }

  int? _feedConvTypeFilter() {
    switch (widget.listScope) {
      case ConversationListScope.c2c:
        return 1;
      case ConversationListScope.group:
        return 2;
      case ConversationListScope.all:
        return null;
    }
  }

  bool _feedWindowTrimmed() {
    final store = ConversationTabStore.instance;
    final type = _feedConvTypeFilter();
    final types = type == null ? const <int>[1, 2] : <int>[type];
    return types.any(store.windowTrimmedForType);
  }

  void _scheduleFeedNewerRestore({bool twoPhase = false}) {
    if (_feedPageLoadScheduled ||
        _feedPageLoadInFlight ||
        _isFeedPagingSuppressed) {
      return;
    }
    _feedPageLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedPageLoadScheduled = false;
      if (!mounted || _feedPageLoadInFlight || _isFeedPagingSuppressed) {
        return;
      }
      unawaited(_restoreNewerFeedPrefix(twoPhase: twoPhase));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _restoreNewerFeedPrefix({required bool twoPhase}) async {
    if (!mounted || _feedPageLoadInFlight || _isFeedPagingSuppressed) {
      return;
    }
    final store = ConversationTabStore.instance;
    final type = _feedConvTypeFilter();
    final types = type == null ? const <int>[1, 2] : <int>[type];
    final trimmed = types.where(store.windowTrimmedForType).toList();
    if (trimmed.isEmpty) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    _feedPageLoadInFlight = true;
    _captureFeedScrollAnchor();
    try {
      for (final convType in trimmed) {
        await store.restoreNewerPrefixForViewport(convType: convType);
        if (!mounted || !SessionIdentityService.instance.isCurrent(identity)) {
          return;
        }
        if (twoPhase && ConversationPerfFlags.restoreHotHeadTwoPhaseEnabled) {
          await store.restoreNewerPrefixForViewport(
            convType: convType,
            count: ConversationPerfFlags.uiAppendOlderMaxPerType,
          );
          if (!mounted ||
              !SessionIdentityService.instance.isCurrent(identity)) {
            return;
          }
        }
      }
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _restoreFeedScrollAnchor();
        });
      }
    } finally {
      _feedPageLoadInFlight = false;
    }
  }

  void _scheduleFeedPageLoad({bool allowSdk = true}) {
    if (_feedPageLoadScheduled ||
        _feedPageLoadInFlight ||
        _isFeedPagingSuppressed) {
      return;
    }
    _feedPageLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedPageLoadScheduled = false;
      if (!mounted || _feedPageLoadInFlight || _isFeedPagingSuppressed) {
        return;
      }
      unawaited(_loadMoreFeedConversations(allowSdk: allowSdk));
    });
    // addPostFrameCallback alone does not request a frame when the user has
    // stopped interacting (notably a retry timer firing at the bottom).
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 当前列表底部是否已经预留了足够的内容。
  /// 不能只看 maxScrollExtent > 0，否则刚多出一行也会被当成“首屏已填满”。
  bool _hasFeedLookaheadBuffer() {
    if (!_feedScrollController.hasClients) return false;
    final position = _feedScrollController.position;
    // Start the next page roughly ten rows before the visual bottom. This
    // hides SDK latency while preserving the existing per-list single-flight.
    double? loadedExtent;
    {
      final type = _feedConvTypeFilter();
      final store = ConversationTabStore.instance;
      final count = _selectedFolderId != null
          ? _getVisibleConversations().length
          : type == null
              ? store.countForType(1) + store.countForType(2)
              : store.countForType(type);
      loadedExtent =
          (count + _feedLeadingHeaderRowCount()) * _feedRowEstimateHeight;
    }
    return !conversationFeedNeedsPage(
      viewportHeight: position.viewportDimension,
      extentAfter: position.extentAfter,
      pixels: position.pixels,
      loadedContentExtent: loadedExtent,
    );
  }

  void _continueFeedPagingIfNeeded() {
    if (!mounted ||
        _feedBottomExhausted ||
        _feedPageLoadInFlight ||
        _isFeedPagingSuppressed ||
        !_feedScrollController.hasClients ||
        _hasFeedLookaheadBuffer()) {
      return;
    }
    _scheduleFeedPageLoad(allowSdk: true);
  }

  ConversationScrollAnchor? _renderedFeedAnchor;

  List<String?> _renderedFeedAnchorIds() {
    final rows = buildConversationFeedRows(
      conversations: _getVisibleConversations(),
      includeArchivedEntry: _selectedFolderId == null &&
          ArchivedConversationEntryVisibility.instance
              .shouldShow(_archiveScope),
      includeGroupNoticeEntry: _selectedFolderId == null &&
          widget.listScope == ConversationListScope.group,
      applications: GroupJoinApplicationService.instance.applications,
      notices: GroupSystemNoticeService.instance.notices,
      conversationTimestampMs: _getConversationTimestampMs,
      groupNoticePinned: GroupNoticeEntrySettingsService.instance.isPinned,
      groupNoticeDismissWatermarkMs:
          GroupNoticeEntrySettingsService.instance.dismissWatermarkMs,
    );
    return [
      for (final row in rows)
        row.conversation == null
            ? null
            : ConversationTabStore.instance
                .rowIdentityKey(row.conversation!.conversationID)
    ];
  }

  void _captureFeedScrollAnchor() {
    _renderedFeedAnchor = null;
    _feedScrollController.resolveLayoutOffset = null;
    if (!_feedScrollController.hasClients) return;
    final position = _feedScrollController.position;
    var previousRows = _renderedFeedAnchorIds();
    var previousExtent = conversationFeedRowExtent(context);
    _renderedFeedAnchor = ConversationScrollAnchor.capture(previousRows,
        offset: position.pixels,
        extent: previousExtent,
        sampleAhead: position.viewportDimension * 0.25);
    if (_renderedFeedAnchor case final anchor?) {
      ChatSessionController.instance.updateViewportAnchor(anchor.id);
    }
    _feedScrollController.resolveLayoutOffset = (pixels) {
      if (!mounted) return null;
      final rows = _renderedFeedAnchorIds();
      final extent = conversationFeedRowExtent(context);
      if (listEquals(rows, previousRows) && extent == previousExtent)
        return null;
      // Capture at the current offset, including motion while a page was loading.
      final anchor = ConversationScrollAnchor.capture(previousRows,
          offset: pixels,
          extent: previousExtent,
          sampleAhead: position.viewportDimension * 0.25);
      final target = anchor?.restore(rows, extent: extent);
      previousRows = rows;
      previousExtent = extent;
      if (target == null) {
        ConversationFeedPerf.increment('conversation_anchor_missing');
      } else {
        ConversationFeedPerf.gauge('conversation_anchor_correction_millipixels',
            ((target - pixels).abs() * 1000).round());
      }
      return target;
    };
  }

  ({String id, int typeIndex})? _virtualFeedConversationAtSample(
    double sample,
  ) {
    {
      return null;
    }
  }

  bool get _isVirtualScopedFeedActive {
    {
      return false;
    }
  }

  /// 归档入口 + 群通知入口（插在会话列表中的非会话行数估算，用于锚点）。
  int _feedLeadingHeaderRowCount() {
    if (_selectedFolderId != null) {
      return 0;
    }
    // buildConversationFeedRows：置顶群通知可能插在会话中间；归档常在顶部或按时间插入。
    // 锚点用「视口中线附近会话 id」更稳，这里仅作粗估：有归档入口时 +1。
    // 与 Feed 一致：看归档 ID 集合，不看主列表窗内是否仍持有该行。
    return _archivedIDsNotifier.value.isNotEmpty ? 1 : 0;
  }

  void _publishViewportAnchorFromScroll() {
    if (!_feedScrollController.hasClients) {
      return;
    }
    final position = _feedScrollController.position;
    final pixels = position.pixels;
    final midSample = pixels + position.viewportDimension * 0.5;
    final throttle = ConversationPerfFlags.feedViewportAnchorThrottle;
    if (throttle > Duration.zero) {
      final last = _lastViewportAnchorPublishAt;
      final now = DateTime.now();
      if (last != null && now.difference(last) < throttle) {
        return;
      }
      _lastViewportAnchorPublishAt = now;
    }
    final virtualAnchor = _virtualFeedConversationAtSample(midSample);
    if (virtualAnchor != null) {
      ChatSessionController.instance.updateViewportAnchor(virtualAnchor.id);
      return;
    }
    if (_isVirtualScopedFeedActive) {
      return;
    }
    final visible = _getVisibleConversations();
    if (visible.isEmpty) {
      return;
    }
    final headerRows = _feedLeadingHeaderRowCount();
    final mid = midSample / _feedRowEstimateHeight;
    final index = (mid - headerRows).floor().clamp(0, visible.length - 1);
    final id = visible[index].conversationID.trim();
    if (id.isNotEmpty) {
      ChatSessionController.instance.updateViewportAnchor(id);
    }
  }

  /// [preSlideOffset] 必须是 append/软裁 **之前** 的 pixels。
  /// 布局后 Flutter 可能已把 offset 夹到近 0，不能再用「当前 offset」做 correctBy。
  bool _isFeedScrollMotionActive() {
    if (!_feedScrollController.hasClients) {
      return false;
    }
    return _feedScrollController.position.isScrollingNotifier.value;
  }

  void _applyFeedScrollTarget(double target) {
    if (!_feedScrollController.hasClients) {
      return;
    }
    final position = _feedScrollController.position;
    final clamped = target.clamp(0.0, position.maxScrollExtent);
    if ((clamped - position.pixels).abs() < 0.5) {
      _pendingFeedScrollTarget = null;
      return;
    }
    if (_isFeedScrollMotionActive()) {
      // 滚动期间：仅记录用户当前可见的锚点偏移作为补偿基线，
      // 等停滑后再判定是否仍要补偿。
      // 修复"列表回退"：之前会无条件保留 pendingTarget，
      // 滚动期间 hydrate 完成导致 anchor 变化，停滑时跳到旧锚点
      // 会让用户感觉列表回退显示已经划过的内容。
      // 现在：滚动期间不暂存新 target，停滑时按当前 offset 重新计算。
      _scheduleFeedScrollEndSettleWork();
      return;
    }
    _feedScrollController.jumpTo(clamped);
    _lastKnownFeedScrollOffset = _feedScrollController.offset;
    _pendingFeedScrollTarget = null;
  }

  void _flushPendingFeedScrollTarget() {
    final target = _pendingFeedScrollTarget;
    if (target == null || !_feedScrollController.hasClients) {
      return;
    }
    _pendingFeedScrollTarget = null;
    final position = _feedScrollController.position;
    final clamped = target.clamp(0.0, position.maxScrollExtent);
    if ((clamped - position.pixels).abs() < 0.5) {
      return;
    }
    _feedScrollController.jumpTo(clamped);
    _lastKnownFeedScrollOffset = _feedScrollController.offset;
  }

  void _restoreFeedScrollAnchorAfterSlide(
    ConversationWindowSlideResult slide, {
    required double preSlideOffset,
  }) {
    _restoreFeedScrollAnchor();
  }

  void _restoreFeedScrollAnchor() {
    // Layout already applied the compensation without interrupting the gesture.
    _feedScrollController.resolveLayoutOffset = null;
    _renderedFeedAnchor = null;
    if (_feedScrollController.hasClients) {
      _lastKnownFeedScrollOffset = _feedScrollController.offset;
    }
  }

  void _onFeedSyncStateChanged() {
    final sync = ConversationListSyncNotifier.instance;
    final syncing = sync.isSyncing;
    final folderSyncPending =
        syncing || sync.isAwaitingServerSync || !sync.hasSyncedOnce;
    final folderSyncReady = _folderSyncWasPending && !folderSyncPending;
    _folderSyncWasPending = folderSyncPending;
    if (folderSyncReady) {
      _folderSyncReadyRevision++;
      final selected = _selectedFolderId;
      if (mounted &&
          selected != null &&
          _folderSdkLookupRetryable &&
          _folderHydratingGeneration != _folderHydrateGeneration) {
        setState(() => _hydrateFolderRows(selected));
      }
    }
    final ended = _wasFeedSyncing && !syncing;
    _wasFeedSyncing = syncing;
    if (!ended || !mounted) {
      return;
    }
    if (_feedSdkPagePending) {
      _feedSdkPagePending = false;
      _scheduleFeedPageLoad();
    }
    if (_viewportFillPendingAfterSync) {
      _viewportFillPendingAfterSync = false;
      _viewportFillDone = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_maybeFillFeedViewportOnce());
        }
      });
    }
  }

  Future<void> _maybeFillFeedViewportOnce() async {
    if (!mounted || _viewportFillDone || _isFeedPagingSuppressed) {
      return;
    }
    if (!_feedScrollController.hasClients) {
      return;
    }
    if (_hasFeedLookaheadBuffer()) {
      _viewportFillDone = true;
      return;
    }
    final maxPages = ConversationPerfFlags.uiViewportFillMaxPages;
    if (maxPages <= 0) {
      _viewportFillDone = true;
      return;
    }
    while (mounted && !_viewportFillDone && _viewportFillPagesDone < maxPages) {
      if (!_feedScrollController.hasClients) {
        return;
      }
      if (_hasFeedLookaheadBuffer()) {
        _viewportFillDone = true;
        return;
      }
      final before = ChatSessionController.instance.conversations.length;
      await _loadMoreFeedConversations();
      _viewportFillPagesDone++;
      if (!mounted) {
        return;
      }
      final after = ChatSessionController.instance.conversations.length;
      if (_hasFeedLookaheadBuffer()) {
        _viewportFillDone = true;
        return;
      }
      if (after <= before) {
        {
          final type = _feedConvTypeFilter();
          final types = type == null ? const [1, 2] : [type];
          _viewportFillDone =
              types.every(ConversationTabStore.instance.finishedForType);
          // The viewport paging continuation handles filtered pages/retries;
          // legacy SQLite metadata cannot decide whether this SDK tail ends.
          return;
        }
      }
    }
    if (_viewportFillPagesDone >= maxPages) {
      _viewportFillDone = true;
    }
  }

  Future<void> _loadMoreFeedConversations({bool allowSdk = true}) async {
    if (_feedPageLoadInFlight || _isFeedPagingSuppressed) {
      return;
    }
    {
      if (!allowSdk) return;
      final identity = SessionIdentityService.instance.capture();
      _feedPageLoadInFlight = true;
      try {
        _captureFeedScrollAnchor();
        final store = ConversationTabStore.instance;
        final type = _feedConvTypeFilter();
        final types = type == null ? const [1, 2] : [type];
        var advanced = false;
        for (final convType in types) {
          advanced = await store.loadMoreForViewport(
                convType: convType,
                viewportAnchorId:
                    ChatSessionController.instance.viewportAnchorConversationId,
              ) ||
              advanced;
          if (!mounted || !SessionIdentityService.instance.isCurrent(identity))
            return;
        }
        final exhausted = types.every(store.finishedForType);
        final exhaustedChanged = exhausted != _feedBottomExhausted;
        _feedBottomExhausted = exhausted;
        if (!advanced && !_feedBottomExhausted) {
          // Network failures retain the cursor and retry after a quiet window.
          _suppressFeedPaging(const Duration(seconds: 2));
        }
        if (mounted) {
          if (exhaustedChanged) {
            setState(() {});
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _restoreFeedScrollAnchor();
          });
          _feedSkipViewportWarmOnNextSettle = true;
        }
      } catch (_) {
        _suppressFeedPaging(const Duration(seconds: 2));
      } finally {
        _feedPageLoadInFlight = false;
        _feedPageContinueTimer?.cancel();
        _feedPageContinueTimer = Timer(
          ConversationPerfFlags.feedPageContinueDelay,
          () {
            _feedPageContinueTimer = null;
            if (!mounted) return;
            if (SessionIdentityService.instance.isCurrent(identity)) {
              _continueFeedPagingIfNeeded();
            }
          },
        );
      }
      return;
    }
    // 同步中：挂起触底，结束后由 sync listener 再试（勿在此直接 return 丢请求）。
  }

  void _restoreTrimmedFeedHeadIfNeeded() {
    if (!mounted || _feedPageLoadInFlight) return;
    unawaited(_restoreNewerFeedPrefix(twoPhase: true));
  }

  void scrollFeedToTop() {
    // Explicit jump: reset each type to the newest SDK prefix. Gesture
    // restore prepends a contiguous newer page instead of resetting.
    if (!_feedScrollController.hasClients) return;
    _renderedFeedAnchor = null;
    _feedScrollController.resolveLayoutOffset = null;
    _feedScrollController.jumpTo(0);
    _lastKnownFeedScrollOffset = 0;
    if (_feedPageLoadInFlight) return;
    final store = ConversationTabStore.instance;
    final type = _feedConvTypeFilter();
    final types = type == null ? const <int>[1, 2] : <int>[type];
    final identity = SessionIdentityService.instance.capture();
    _feedPageLoadInFlight = true;
    unawaited(() async {
      try {
        for (final convType in types) {
          await store.loadFirstPage(
            convType: convType,
            count: ConversationTabStore.coldStartFirstPageSize,
          );
          if (!mounted ||
              !SessionIdentityService.instance.isCurrent(identity)) {
            return;
          }
        }
        _feedBottomExhausted = types.every(store.finishedForType);
        if (mounted) setState(() {});
      } finally {
        _feedPageLoadInFlight = false;
      }
    }());
  }

  void _syncWebGroupConversations() {
    if (!PlatformUtils().isWeb ||
        (widget.listScope != ConversationListScope.group &&
            widget.listScope != ConversationListScope.all)) {
      return;
    }
    unawaited(
      WebConversationSyncService.instance.syncJoinedGroupConversations(
        _controller,
      ),
    );
  }

  void _captureFeedScrollOffsetBeforeReload() {
    if (_feedScrollController.hasClients) {
      _pendingFeedScrollRestoreOffset = _feedScrollController.offset;
    }
  }

  @override
  void didUpdateWidget(Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listScope != oldWidget.listScope) {
      _invalidateVisibleConversationsCache();
    }
    if (widget.selectedConversation != oldWidget.selectedConversation) {
      Future.delayed(const Duration(milliseconds: 1), () {
        _controller.selectedConversation = widget.selectedConversation;
      });
    }
  }

  @override
  void dispose() {
    _folderHydrateGeneration++;
    _folderSdkRows.clear();
    _folderSdkDeletedIds.clear();
    _folderSdkIdentity = null;
    _visibleOfficialPlaceholders.clear();
    ChatCoverageRepairScheduler.instance.pause(reason: 'home_hidden');
    OpenViewportCache.instance.pause(reason: 'home_hidden');
    conversationEditingNotifier.value = false;
    conversationAllSelectedNotifier.value = false;
    conversationToggleEditModeActions.remove(widget.listScope);
    if (widget.hostEditActionBar) {
      conversationEditActionBarBuilders.remove(widget.listScope);
    }
    conversationToggleSelectAllActions.remove(widget.listScope);
    conversationScrollNextUnreadActions.remove(widget.listScope);
    conversationScrollToTopActions.remove(widget.listScope);
    PlatformOfficialAccountService.infoRevision.removeListener(
      _onOfficialInfoUpdated,
    );
    ConversationRefreshBus.instance.revision.removeListener(
      _onConversationRefreshRequested,
    );
    PeerProfileRefreshBus.instance.revision.removeListener(
      _onPeerProfileRefreshForListCache,
    );
    ConversationListSyncNotifier.instance.removeListener(
      _onFeedSyncStateChanged,
    );
    ChatSessionController.instance.removeListener(
      _scheduleFolderUnreadRefresh,
    );
    ConversationUnreadAggregate.instance.sdkUnreadRevision
        .removeListener(_scheduleFolderUnreadRefresh);
    ChatSessionController.instance.removeListener(_onSessionProjectionChanged);
    ChatSessionController.instance.sdkDeletedConversationIds
        .removeListener(_onSdkDeletedFolderRows);
    archivedConversationC2cIDsNotifier.removeListener(
      _onArchivedIdsChangedForMainList,
    );
    archivedConversationGroupIDsNotifier.removeListener(
      _onArchivedIdsChangedForMainList,
    );
    GroupMembershipSyncService.instance.joinedGroupsRevision.removeListener(
      _onJoinedGroupsRevision,
    );
    GroupLocalStore.instance.cacheHydration
        .removeListener(_onGroupCacheHydrated);
    GroupLocalStore.instance.commitListenable
        .removeListener(_onGroupStoreCommitForDisplay);
    ConversationFolderStore.instance.foldersNotifier.removeListener(
      _onFoldersChanged,
    );
    _ConversationListRefreshCoordinator.unregister(this);
    _conversationPreviewSaveTimer?.cancel();
    _patchConversationTimer?.cancel();
    _viewportWarmSettleTimer?.cancel();
    _feedScrollEndSettleTimer?.cancel();
    _feedPagingResumeTimer?.cancel();
    _feedPageContinueTimer?.cancel();
    _folderUnreadSettleTimer?.cancel();
    _folderUnreadLeaveKickTimer?.cancel();
    _feedScrollingNotifier?.removeListener(_onFeedScrollingNotifier);
    _feedScrollingNotifier = null;
    _cancelFeedScrollStableRestore();
    _feedScrollController.removeListener(_onFeedScroll);
    if (identical(
      ChatSessionController.instance.listScrollOffsetProvider,
      _currentFeedScrollOffset,
    )) {
      ChatSessionController.instance.listScrollOffsetProvider = null;
    }
    if (ChatSessionController.instance.isFeedScrolling != null) {
      ChatSessionController.instance.isFeedScrolling = null;
    }
    ConversationLocalStore.instance.isUiBusyForWriteCoalesce = null;
    GroupLocalStore.instance.isUiBusyForWrite = null;
    _feedScrollController.dispose();
    _editingNotifier.dispose();
    _selectionRevision.dispose();
    for (final notifier in _previewProjectionRowRevisions.values) {
      notifier.dispose();
    }
    _previewProjectionRowRevisions.clear();
    _pendingPreviewProjectionRows.clear();
    _previewProjectionByConversation.clear();
    super.dispose();
  }

  void scrollToNextUnreadConversation() {
    final conversationList = ChatSessionController.instance.conversations;
    final membership = GroupMembershipSyncService.instance;
    for (var element in conversationList) {
      if (!conversationMatchesScope(element, widget.listScope) ||
          !membership.shouldShowConversation(element)) {
        continue;
      }
      if ((element.unreadCount ?? 0) > 0 &&
          !jumpedConversations.contains(element.conversationID)) {
        _controller.scrollToConversation(element.conversationID);
        jumpedConversations.add(element.conversationID);
        return;
      }
    }
    jumpedConversations.clear();
    try {
      final firstInScope = conversationList.firstWhere(
        (element) =>
            conversationMatchesScope(element, widget.listScope) &&
            membership.shouldShowConversation(element),
      );
      _controller.scrollToConversation(firstInScope.conversationID);
    } catch (e) {}
  }

  Future<void> _cleanConversationUnread(
    V2TimConversation conversation, {
    bool updateUi = true,
  }) async {
    final hadUnread = (conversation.unreadCount ?? 0) > 0;
    await ConversationUnreadClearService.clearLocalForOpen(
      conversation: conversation,
      markViewModelReadLocally: _controller.model.markConversationReadLocally,
    );
    if (hadUnread) {
      unawaited(
        ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: conversation.conversationID,
          trigger: SdkUnreadCleanTrigger.open,
          hadUnread: true,
        ),
      );
    }
    if (updateUi && mounted) {
      setState(() {});
    }
  }

  Future<void> _cleanConversationUnreadQuietly(
    V2TimConversation conversation,
  ) async {
    try {
      await _cleanConversationUnread(conversation, updateUi: false);
    } catch (_) {}
  }

  String? _chatCacheConversationKey(V2TimConversation conversation) {
    final userID = TencentUtils.checkString(conversation.userID);
    if (userID != null) {
      return userID;
    }
    final groupID = TencentUtils.checkString(conversation.groupID);
    if (groupID != null) {
      return ChatIdFormat.canonicalGroupStorageId(groupID);
    }
    final conversationID = TencentUtils.checkString(
      conversation.conversationID,
    );
    if (conversationID != null &&
        conversationID.toLowerCase().startsWith('group_')) {
      return ChatIdFormat.canonicalGroupStorageId(conversationID);
    }
    return conversationID;
  }

  void _lockEntryUnreadIfNeeded(V2TimConversation conversation) {
    final unread = conversation.unreadCount ?? 0;
    if (!UnreadTonguePolicy.isEntryUnreadEnabled(conversation, unread)) {
      return;
    }
    final conversationKey = _chatCacheConversationKey(conversation);
    if (conversationKey == null || conversationKey.isEmpty) {
      return;
    }
    serviceLocator<TUIChatGlobalModel>().lockEntryUnreadForTongue(
      conversationID: conversationKey,
      unreadCount: unread,
      notify: false,
    );
  }

  String? _peekOnlineStatusText(
    V2TimConversation conversation,
    LocalSetting localSetting,
  ) {
    if (!localSetting.isShowOnlineStatus) {
      return null;
    }
    final isGroup = conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
    if (isGroup) {
      return null;
    }
    final userId = conversation.userID?.trim() ?? '';
    if (userId.isEmpty ||
        PlatformOfficialAccountService.showsVerifiedBadge(userId)) {
      return null;
    }
    final onlineStatus = _friendShipViewModel.userStatusList.firstWhere(
      (item) => item.userID == userId,
      orElse: () => V2TimUserStatus(statusType: 0),
    );
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    presence.ensure([userId]);
    presence.refresh([userId], urgent: true);
    final label = presence.listLabelFor(
      userId: userId,
      imOnline: onlineStatus.statusType == 1,
      isMutualFriend: friendCanMessage(_friendShipViewModel, userId),
    );
    return label.isEmpty ? null : label;
  }

  ConversationPeekActions _buildConversationPeekActions(
    V2TimConversation conversation,
    LocalSetting localSetting,
  ) {
    final isOfficial = PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversation.userID,
    );
    final isArchived = conversationIdInArchivedSet(
      _archivedIDsNotifier.value,
      conversation.conversationID,
    );
    return ConversationPeekActions(
      onOpenChat: () => _handleOnConvItemTaped(conversation),
      isOfficialAccount: isOfficial,
      isPinned: conversation.isPinned ?? false,
      isMuted: conversationRecvOptMuted(conversation),
      isArchived: isArchived,
      onlineStatusText: _peekOnlineStatusText(conversation, localSetting),
      onArchive: isOfficial
          ? null
          : () => _updateArchivedStatusForConversations([
                conversation,
              ], archived: !isArchived),
      onAddToFolder:
          isOfficial ? null : () => _showAddToFolderSheet(conversation),
      onTogglePin: isOfficial
          ? null
          : () async {
              await _pinConversation(conversation);
            },
      onToggleMute:
          isOfficial ? null : () => _toggleConversationDisturb(conversation),
      onDelete: () => _deleteConversation(conversation),
    );
  }

  void _showConversationPeek(V2TimConversation conversation) {
    if (_isEditing) {
      return;
    }
    final localSetting = Provider.of<LocalSetting>(context, listen: false);
    showConversationPeekForItem(
      context: context,
      conversation: conversation,
      displayName: ConversationDisplayHelper.showName(
        conversation: conversation,
        friendList: _friendShipViewModel.friendList,
      ),
      actions: _buildConversationPeekActions(conversation, localSetting),
    );
  }

  void _showDesktopConversationMenu(
    V2TimConversation conversation,
    TapDownDetails details,
  ) {
    if (_isEditing || !conversationUseDesktopContextMenu(context)) {
      return;
    }
    final i18n = AppI18n.of(context);
    final isOfficial = PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversation.userID,
    );
    final isArchived = conversationIdInArchivedSet(
      _archivedIDsNotifier.value,
      conversation.conversationID,
    );
    final isPinned = conversation.isPinned ?? false;
    final isDisturb = conversationRecvOptMuted(conversation);
    final selectedFolderId = _selectedFolderId;
    final inSelectedFolder = selectedFolderId != null &&
        (ConversationFolderStore.instance
                .folderById(selectedFolderId)
                ?.containsConversationId(conversation.conversationID) ??
            false);
    final items = <DesktopConversationMenuItem>[];
    if (!isOfficial) {
      items.add(
        DesktopConversationMenuItem(
          label: isArchived
              ? i18n.t(
                  zhHans: '取消归档',
                  zhHant: '取消封存',
                  en: 'Unarchive',
                  ja: 'アーカイブ解除',
                  ko: '보관 해제',
                )
              : i18n.t(
                  zhHans: '归档',
                  zhHant: '封存',
                  en: 'Archive',
                  ja: 'アーカイブ',
                  ko: '보관',
                ),
          onSelect: () => _updateArchivedStatusForConversations(
            [conversation],
            archived: !isArchived,
          ),
        ),
      );
      items.add(
        DesktopConversationMenuItem(
          label: inSelectedFolder
              ? i18n.t(
                  zhHans: '移出分组',
                  zhHant: '移出分組',
                  en: 'Remove',
                  ja: 'フォルダから外す',
                  ko: '폴더에서 제거',
                )
              : i18n.t(
                  zhHans: '添加至分组',
                  zhHant: '添加至分組',
                  en: 'Add to folder',
                  ja: 'フォルダに追加',
                  ko: '폴더에 추가',
                ),
          onSelect: () => inSelectedFolder
              ? _removeConversationFromSelectedFolder(conversation)
              : _showAddToFolderSheet(conversation),
        ),
      );
      items.add(
        DesktopConversationMenuItem(
          label: isPinned
              ? i18n.t(
                  zhHans: '取消置顶',
                  zhHant: '取消置頂',
                  en: 'Unpin',
                  ja: 'ピン留め解除',
                  ko: '고정 해제',
                )
              : i18n.t(
                  zhHans: '置顶',
                  zhHant: '置頂',
                  en: 'Pin',
                  ja: 'ピン留め',
                  ko: '고정',
                ),
          onSelect: () => _pinConversation(conversation),
        ),
      );
      items.add(
        DesktopConversationMenuItem(
          label: isDisturb
              ? i18n.t(
                  zhHans: '取消免打扰',
                  zhHant: '取消免打擾',
                  en: 'Unmute',
                  ja: 'ミュート解除',
                  ko: '알림 켜기',
                )
              : i18n.t(
                  zhHans: '免打扰',
                  zhHant: '免打擾',
                  en: 'Mute',
                  ja: 'ミュート',
                  ko: '알림 끄기',
                ),
          onSelect: () => _toggleConversationDisturb(conversation),
        ),
      );
    }
    items.add(
      DesktopConversationMenuItem(
        label: i18n.t(
          zhHans: '删除',
          zhHant: '刪除',
          en: 'Delete',
          ja: '削除',
          ko: '삭제',
        ),
        destructive: true,
        onSelect: () => _deleteConversation(conversation),
      ),
    );
    unawaited(
      showDesktopConversationContextMenu(
        context: context,
        globalPosition: details.globalPosition,
        items: items,
      ),
    );
  }

  Future<void> _finalizeConversationLeave(
    String conversationID, {
    required int entryUnreadCount,
  }) async {
    await ConversationUnreadClearService.finalizeConversationLeaveOnce(
      conversationID: conversationID,
      lastMessageId: _lastMessageIdForConversation(conversationID),
      entryUnreadCount: entryUnreadCount,
      markViewModelReadLocally: _controller.model.markConversationReadLocally,
    );
  }

  void _handleOnConvItemTaped(V2TimConversation? selectedConv) async {
    if (selectedConv == null) {
      return;
    }
    _lockEntryUnreadIfNeeded(selectedConv);
    final conversationID = selectedConv.conversationID;
    if (conversationID.isEmpty) {
      return;
    }
    // 移动端一次只允许一个 chat open 进入导航栈。旧实现只拦同一会话，
    // 冷开 prepare 期间快速点另一行可能产生两条竞争的 Chat route。
    if (_openingConversationID != null) {
      return;
    }
    _openingConversationID = conversationID;
    final openCacheKey =
        _chatCacheConversationKey(selectedConv) ?? conversationID;
    ChatOpenPerfLog.beginOpen(conversationID: openCacheKey,
        phase: 'conv_item_tap', extras: <String, Object?>{
          'source': widget.onConversationChanged == null ? 'list' : 'embedded',
        });
    final openTrace = ChatOpenPerfLog.captureCurrent(conversationKey: openCacheKey);
    unawaited(
      ConversationSyncService.instance.retainOpenedGroupConversation(
        selectedConv,
      ),
    );

    final pushChatRoute = widget.onConversationChanged == null;
    ChatCoverageRepairScheduler.instance.pause(reason: 'conv_item_tap');
    OpenViewportCache.instance.pause(reason: 'conv_item_tap');
    if (pushChatRoute) {
      ConversationSyncService.instance.beginChatTransition();
    }

    final entryUnreadCount = selectedConv.unreadCount ?? 0;
    // Pipeline [1] - conv_item_tap：建立 t0 锚点（跨页面跨文件）
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: selectedConv.conversationID,
      userId: selectedConv.userID,
      groupId: selectedConv.groupID,
    );
    ChatPipelineClock.instance
      ..start(pipelineKey)
      ..trace(pipelineKey, 'conv_item_tap',
          elapsedMs: 0,
          extras: <String, Object?>{
            'entryUnread': entryUnreadCount,
            'embedded': widget.onConversationChanged != null,
          });
    ConversationUnreadTrace.log(
      'conv_item_tap',
      conversationID: conversationID,
      unreadBefore: entryUnreadCount,
      extras: <String, Object?>{
        'embedded': widget.onConversationChanged != null,
      },
    );
    await ChatOpenPerfLog.measure('entry_local_unread_clear', () =>
        ConversationUnreadClearService.clearLocalForOpenFast(
      conversation: selectedConv,
      markViewModelReadLocally: _controller.model.markConversationReadLocally,
    ), trace: openTrace, source: 'list');

    ConversationHistoryWarmScheduler.instance.touchMemoryWarm(openCacheKey);
    final isGroup = selectedConv.type == 2 ||
        (selectedConv.groupID?.trim().isNotEmpty ?? false);
    ChatOpenPerfLog.mark('entry_local_ready',
      conversationID: openCacheKey,
      trace: openTrace,
      extras: <String, Object?>{
        'rawConvID': conversationID,
        'isGroup': isGroup,
        'entryUnread': entryUnreadCount,
        'pushRoute': pushChatRoute,
        'warmReady': ConversationPreviewHistorySync.isWarmWindowReadyForOpen(
          globalModel: serviceLocator<TUIChatGlobalModel>(),
          conversationKey: openCacheKey,
          preview: selectedConv.lastMessage,
        ),
        'rawCount': serviceLocator<TUIChatGlobalModel>().rawMessageCount(
          openCacheKey,
        ),
        'initialLoaded': serviceLocator<TUIChatGlobalModel>()
            .hasInitialHistoryLoaded(openCacheKey),
      },
    );
    final embeddedChat = widget.onConversationChanged != null;
    if (embeddedChat) {
      final previous = _embeddedActiveConversationID;
      if (previous != null &&
          !MessageConversationId.sameConversation(previous, conversationID)) {
        final previousUnread = _embeddedEntryUnreadById[previous] ?? 0;
        unawaited(
          _finalizeConversationLeave(
            previous,
            entryUnreadCount: previousUnread,
          ),
        );
      }
      _embeddedActiveConversationID = conversationID;
      _embeddedEntryUnreadById[conversationID] = entryUnreadCount;
    }
    _controller.model.assignSelectedConversation(
      selectedConv,
      notify: embeddedChat,
    );

    if (!mounted) {
      if (pushChatRoute) {
        ConversationSyncService.instance.cancelChatTransition();
      }
      _openingConversationID = null;
      return;
    }
    DeviceSyncService.instance.prepareForChatNavigation();
    try {
      if (mounted) {
        unawaited(
          AvatarImageWarm.warmSources(
            <AvatarImageWarmSource>[
              _conversationAvatarWarmSource(selectedConv),
            ],
            context: context,
            logicalSize: 40,
          ),
        );
      }
      if (widget.onConversationChanged != null) {
        ChatOpenPerfLog.mark('embedded_chat_switch');
        widget.onConversationChanged!(selectedConv);
      } else {
        ChatOpenPerfLog.mark('open_prewarm_begin');
        // Telegram-style open: start the local-only snapshot, but never make
        // the route transition wait for a native SDK/database read. The Chat
        // page reuses this flight after mounting and renders the result when
        // it arrives.
        unawaited(() async {
          try {
            final coordinator = ChatOpenViewportCoordinator.instance;
            final prepareTask = ChatOpenPerfLog.withTrace(openTrace, () => coordinator.prepareOpenViewport(
              conversation: selectedConv,
              source: 'list',
            ));
            final listRequestId = coordinator.currentRequestId;
            final snap = await prepareTask;
            if (!coordinator.isCurrent(
              listRequestId,
              snap.conversationKey,
            )) {
              final work = coordinator.snapshotFor(listRequestId);
              ChatOpenPerfLog.mark(
                'viewport_prepare_ignored',
                extras: <String, Object?>{
                  'key': snap.conversationKey,
                  'coverage': snap.coverageState.name,
                  'requestId': listRequestId,
                  'prepareId': listRequestId,
                  'currentRequestId': coordinator.currentRequestId,
                  'source': 'list',
                  'owned': work?.owned ?? false,
                  'joined': work?.joined ?? false,
                  'dbRead': work?.dbRead ?? false,
                  'sdkRead': work?.sdkRead ?? false,
                  'committed': work?.committed ?? false,
                  'ignoredReason': 'requestIdMismatch',
                },
                trace: openTrace,
              );
              return;
            }
            ChatOpenPerfLog.mark(
              'open_prewarm_end',
              extras: <String, Object?>{
                'complete': snap.isViewportReady,
                'rawCount': snap.continuousCount,
                'coverage': snap.coverageState.name,
                'source': snap.source.name,
                'requestId': listRequestId,
                'localReadyBeforePush': false,
                'background': false,
              },
              trace: openTrace,
            );
          } catch (error) {
            ChatOpenPerfLog.mark(
              'open_prewarm_error',
              extras: <String, Object?>{'error': '$error'},
              trace: openTrace,
            );
          }
        }());
        ChatOpenViewportCoordinator.instance.markTransitioning(
          openCacheKey,
        );
        ChatOpenPerfLog.mark('navigator_push_begin', trace: openTrace);
        await openOrReuseAppChat(
          context,
          selectedConv,
          entryUnreadCount: entryUnreadCount,
          openTrace: openTrace,
          openSource: 'list',
        );
        ChatOpenPerfLog.mark('navigator_pop_back', trace: openTrace);
        ConversationDraftLeaveTrace.stage(
          'conversation_list_resume',
          conversationId: conversationID,
          draftText: ConversationTabStore.instance
              .conversationForId(conversationID)
              ?.draftText,
        );
        ChatOpenPerfLog.emitOpenTraceSummary(phase: 'pop', trace: openTrace);
        if (!mounted) {
          return;
        }
        // Chat.dispose 也会启动同一 finalize。这里必须等待它的 single-flight
        // 本地提交完成后再强制 hydrate，否则会从 SQLite 读回旧 unread。
        await _finalizeConversationLeave(
          conversationID,
          entryUnreadCount: entryUnreadCount,
        );
        if (!mounted) {
          return;
        }
        // 从聊天返回：预热当前会话头像，降低列表行闪动。
        unawaited(
          AvatarImageWarm.warmSources(
            <AvatarImageWarmSource>[
              _conversationAvatarWarmSource(selectedConv),
            ],
            context: context,
            logicalSize: 52,
          ),
        );
      }
    } finally {
      if (_openingConversationID == conversationID) {
        _openingConversationID = null;
      }
      if (pushChatRoute &&
          ConversationSyncService.instance.hasActiveChatTransition) {
        ConversationSyncService.instance.cancelChatTransition();
      }
    }
  }

  Future<void> _pinConversation(V2TimConversation conversation) async {
    final prevPinned = ConversationPinSyncService.instance
        .isPinnedConversationId(conversation.conversationID);
    // 必须从本页 ScrollController 取值并向下传；全局 provider 会被其它 Tab 写成 0。
    final listScroll = _feedScrollController.hasClients
        ? _feedScrollController.offset
        : _lastKnownFeedScrollOffset;
    ConversationPinFlickerLog.log(
      'ui_pin_tap',
      conversationID: conversation.conversationID,
      extras: <String, Object?>{
        'prevPinned': prevPinned,
        'scope': widget.listScope.name,
        'listScroll': listScroll?.toStringAsFixed(1) ?? 'na',
      },
    );
    // 列表由 ChatSessionController projection 即时刷新；勿再 setState，避免二次整树重建抖动。
    try {
      final result = await ConversationPinService.instance.togglePinned(
        conversation: conversation,
        source: 'conversation_list',
        listScrollOffset: listScroll,
      );
      ConversationPinFlickerLog.log(
        'ui_pin_tap_done',
        conversationID: conversation.conversationID,
        extras: <String, Object?>{
          'applied': result.applied,
          'pinned': result.isPinned,
          'prevPinned': prevPinned,
        },
      );
      if (!result.applied && mounted) {
        ToastUtils.toast(
          AppI18n.of(context).t(
            zhHans: '设置失败',
            zhHant: '設置失敗',
            en: 'Failed to update',
            ja: '設定に失敗しました',
            ko: '설정에 실패했습니다',
          ),
        );
      }
    } on ConversationPinLimitExceededException {
      if (!mounted) {
        return;
      }
      ToastUtils.toast(
        AppI18n.of(context).t(
          zhHans: '置顶已达上限（最多 100 个）',
          zhHant: '置頂已達上限（最多 100 個）',
          en: 'Pin limit reached (max 100)',
          ja: 'ピン留め上限です（最大100）',
          ko: '고정 한도에 도달했습니다(최대 100)',
        ),
      );
    }
  }

  Future<void> _clearConversationHistoryQuietly(
    V2TimConversation conversation,
  ) async {
    final convType = conversation.type;
    final convID = convType == 1 ? conversation.userID : conversation.groupID;
    if (convType == null || convID == null || convID.trim().isEmpty) {
      return;
    }
    try {
      await _controller.clearHistoryMessage(conversation: conversation);
    } catch (_) {}
  }

  Future<void> _deleteConversation(V2TimConversation conversation) async {
    final identity = SessionIdentityService.instance.capture();
    final confirmed = await _confirmDeleteConversation();
    if (confirmed != true) return;
    if (PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversation.userID,
    )) {
      await PlatformOfficialAccountService.dismissFromConversationList(
        userId: conversation.userID,
      );
    }
    await _cleanConversationUnreadQuietly(conversation);
    await _clearConversationHistoryQuietly(conversation);
    final result = await _controller.deleteConversation(
      conversationID: conversation.conversationID,
    );
    if (result?.code == 0) {
      _forgetDeletedFolderRow(conversation.conversationID, identity);
    }
    _notifyHostIfDeletedOpenConversation(conversation.conversationID);
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_deleted',
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _notifyHostIfDeletedOpenConversation(String conversationID) {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    final selectedId = _controller.model.selectedConversation?.conversationID ??
        _embeddedActiveConversationID;
    if (selectedId == null ||
        !MessageConversationId.sameConversation(selectedId, id)) {
      return;
    }
    _embeddedActiveConversationID = null;
    widget.onConversationChanged?.call(null);
  }

  Future<bool?> _confirmDeleteConversation({int count = 1}) {
    final i18n = AppI18n.of(context);
    final isBatch = count > 1;
    return AppDialog.confirm(
      title: i18n.t(
        zhHans: isBatch ? '删除会话' : '删除此会话',
        zhHant: isBatch ? '刪除會話' : '刪除此會話',
        en: isBatch ? 'Delete conversations' : 'Delete conversation',
        ja: isBatch ? '会話を削除' : 'この会話を削除',
        ko: isBatch ? '대화 삭제' : '이 대화 삭제',
      ),
      message: i18n.t(
        zhHans: '将从列表移除该会话，并清空您的聊天记录。确定继续吗？',
        zhHant: '將從列表移除該會話，並清空您的聊天記錄。確定繼續嗎？',
        en: 'This removes the conversation from your list and clears chat history on your side only. Continue?',
        ja: 'リストから会話を削除し、あなた側のチャット履歴を消去します（相手には影響しません）。続行しますか？',
        ko: '목록에서 대화를 제거하고 내 기기의 채팅 기록을 삭제합니다(상대방에게는 영향 없음). 계속할까요?',
      ),
      confirmText: i18n.t(
        zhHans: '删除',
        zhHant: '刪除',
        en: 'Delete',
        ja: '削除',
        ko: '삭제',
      ),
      destructive: true,
    );
  }

  Future<void> _toggleConversationDisturb(
    V2TimConversation conversation,
  ) async {
    final isDisturb = conversationRecvOptMuted(conversation);
    final targetOpt = isDisturb
        ? ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE
        : ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE;
    final prevOpt = conversation.recvOpt ?? 0;
    final targetIndex = targetOpt.index;

    final groupID = conversation.groupID?.trim() ?? '';
    var userID = conversation.userID?.trim() ?? '';
    if (userID.isEmpty && groupID.isEmpty) {
      userID = MessageConversationId.normalizeComparableKey(
        conversation.conversationID,
      );
    }

    void applyLocal(int recvOpt) {
      // 072 phase-6 allowlist: this is a transient pending projection only.
      // The successful value is published from the Coordinator commit below;
      // this helper is also used to roll back an SDK failure.
      conversation.recvOpt = recvOpt;
      ChatSessionController.instance.applyRecvOptLocally(
        conversationID: conversation.conversationID,
        recvOpt: recvOpt,
        snapshot: conversation,
      );
    }

    final optimistic = ConversationPerfFlags.recvOptOptimisticUiEnabled;
    if (optimistic) {
      // 列表行有指纹缓存：先刷 UI，再等 SDK。
      applyLocal(targetIndex);
    }

    final result = groupID.isNotEmpty
        ? await ImGroupReceiveOpt.setGroupReceiveMessageOpt(
            messageService: _messageService,
            groupID: groupID,
            opt: targetOpt,
          )
        : userID.isEmpty
            ? null
            : await _c2cDisturbViaService(
                messageService: _messageService,
                userID: userID,
                opt: targetOpt,
              );

    if (result != null && result.code == 0) {
      String resolvedGroup = '';
      if (groupID.isNotEmpty) {
        try {
          resolvedGroup =
              await GroupLocalStore.instance.resolveImGroupId(groupID);
        } catch (_) {}
      }
      if (resolvedGroup.isNotEmpty &&
          ChatIdFormat.isCustomCommunityId(resolvedGroup) &&
          conversation.groupID?.trim() != resolvedGroup) {
        conversation.groupID = resolvedGroup;
      }
      // SDK 成功后的正式持久化只走 Coordinator；UI 乐观态保留在上方。
      try {
        await ConversationSyncService.instance.applyConversationMuteLocally(
          conversationID: conversation.conversationID,
          recvOpt: targetIndex,
          snapshot: conversation,
        );
      } catch (e) {
        debugPrint('Conversation disturb upsert fail: $e');
      }
    } else {
      if (optimistic) {
        applyLocal(prevOpt);
      }
      if (result != null) {
        debugPrint(
          'Conversation disturb fail code=${result.code} desc=${result.desc}',
        );
      }
    }
  }

  /// IM-09 ADR §10.1: c2c 免打扰收敛到 C2cReceiveOptService,
  /// 在异步链入口处 capture() 拿到 SessionIdentity,跨账号 fence 生效.
  /// 任何 [MessageService.setC2CReceiveMessageOpt] 直调都必须收敛到本方法.
  Future<dynamic> _c2cDisturbViaService({
    required MessageService messageService,
    required String userID,
    required ReceiveMsgOptEnum opt,
  }) async {
    final captured = SessionIdentityService.instance.capture();
    final key = AccountScopedConversationKey.tryParse(
      ownerUserId: captured.ownerUserId,
      conversationType: ImConversationType.c2c,
      conversationId: userID,
    );
    if (key == null) {
      debugPrint(
        '_c2cDisturbViaService: invalid c2c key userID=$userID',
      );
      return V2TimCallback(code: -1, desc: 'invalid_c2c_key');
    }
    return await C2cReceiveOptService.setOpt(
      messageService: messageService,
      key: key,
      opt: opt,
      capturedIdentity: captured,
    );
  }

  void _syncEditingStateNotifiers() {
    _stripGroupNoticeSelectionIfHidden();
    conversationEditingNotifier.value = _isEditing;
    conversationAllSelectedNotifier.value = _isAllSelected(
      _getVisibleConversations(),
    );
  }

  bool _isGroupNoticeEntryVisibleForSelection() {
    if (widget.listScope != ConversationListScope.group) {
      return false;
    }
    if (_selectedFolderId != null) {
      return false;
    }
    return shouldShowGroupNoticeEntry(
      GroupJoinApplicationService.instance.applications,
      GroupSystemNoticeService.instance.notices,
      dismissWatermarkMs:
          GroupNoticeEntrySettingsService.instance.dismissWatermarkMs,
    );
  }

  void _stripGroupNoticeSelectionIfHidden() {
    if (_isGroupNoticeEntryVisibleForSelection()) {
      return;
    }
    if (_selectedConversationIDs.remove(kGroupNoticeSelectionId)) {
      _bumpSelectionLocalUi();
    }
  }

  void _toggleGroupNoticeSelected() {
    _toggleSelectedConversation(kGroupNoticeSelectionId);
  }

  void _applyEditingLocalUi({required bool editing}) {
    _isEditing = editing;
    if (_editingNotifier.value != editing) {
      _editingNotifier.value = editing;
    }
    _selectionRevision.value++;
  }

  void _bumpSelectionLocalUi() {
    _selectionRevision.value++;
  }

  bool _isConversationArchivedInEitherScope(String conversationID) {
    return conversationIdInArchivedSet(
          archivedConversationIDsNotifierFor(
            ConversationArchiveScope.c2c,
          ).value,
          conversationID,
        ) ||
        conversationIdInArchivedSet(
          archivedConversationIDsNotifierFor(
            ConversationArchiveScope.group,
          ).value,
          conversationID,
        );
  }

  bool _isConversationArchived(String conversationID) {
    // 分组内混显单聊+群聊时，需同时看两套归档集合。
    if (_selectedFolderId != null) {
      return _isConversationArchivedInEitherScope(conversationID);
    }
    return conversationIdInArchivedSet(
      _archivedIDsNotifier.value,
      conversationID,
    );
  }

  List<V2TimConversation> _cacheVisibleConversationView(
    List<V2TimConversation> rows, {
    bool retainVisibleIds = false,
    bool readOnly = false,
  }) {
    // A revision-bound, read-only projection; every mutable row is owned by
    // TabStore or the selected folder's bounded SDK lookup.
    if (!retainVisibleIds) {
      final ids =
          rows.map((row) => row.conversationID.trim()).toList(growable: false);
      _cachedVisibleConversationIds = ids;
      _cachedVisibleIds = ids.toSet();
      _visiblePositions
        ..clear()
        ..addEntries(ids.indexed.map((entry) => MapEntry(entry.$2, entry.$1)));
    }
    _visibleCacheContentRevision =
        ConversationTabStore.instance.contentRevision;
    _visibleCacheVisibilityRevision = _visibilityRevision;
    _visibleCacheIdentity = SessionIdentityService.instance.capture();
    _visibleUsesFullStoreView = identical(
      rows,
      ConversationTabStore.instance.conversations,
    );
    _visibleConversationView = _visibleUsesFullStoreView || readOnly
        ? rows
        : List<V2TimConversation>.unmodifiable(rows);
    return _visibleConversationView!;
  }

  List<V2TimConversation> _getVisibleConversations() {
    final store = ConversationTabStore.instance;
    store.flushRealtimePatches();
    final identity = _visibleCacheIdentity;
    if (identity != null &&
        !SessionIdentityService.instance.isCurrent(identity)) {
      _folderHydrateGeneration++;
      _folderSdkRows.clear();
      _folderSdkDeletedIds.clear();
      _folderSdkMemberIds = const <String>{};
      _folderSdkIdentity = null;
      _invalidateVisibleConversationsCache();
    }
    final folderIdentity = _folderSdkIdentity;
    if (folderIdentity != null &&
        !SessionIdentityService.instance.isCurrent(folderIdentity)) {
      _folderHydrateGeneration++;
      _folderSdkRows.clear();
      _folderSdkDeletedIds.clear();
      _folderSdkMemberIds = const <String>{};
      _folderSdkIdentity = null;
      _invalidateVisibleConversationsCache();
    }
    final structureRevision = ChatSessionController.instance.structureRevision;
    final cached = _cachedVisibleConversationIds;
    if (cached != null &&
        _visibleCacheStructureRevision == structureRevision &&
        _visibleCacheVisibilityRevision == _visibilityRevision) {
      ConversationFeedPerf.increment('visible_projection_cache_hit');
      if (_visibleCacheContentRevision == store.contentRevision) {
        return _visibleConversationView!;
      }
      if (_visibleUsesFullStoreView) {
        return _cacheVisibleConversationView(store.conversations,
            retainVisibleIds: true);
      }
      final changedIds = store.contentChangesSince(_visibleCacheContentRevision);
      if (changedIds != null) {
        final patched = patchConversationContents(
          current: _visibleConversationView!,
          positions: _visiblePositions,
          changedIds: changedIds,
          lookup: store.displayConversationForId,
        );
        if (patched != null) {
          ConversationFeedPerf.increment('visible_projection_content_patch');
          return _cacheVisibleConversationView(patched,
              retainVisibleIds: true, readOnly: true);
        }
      }
      // Resolve once per Store revision, so replacements are never masked by
      // a cached row. Repeated consumers in the same frame reuse this view.
      final refreshed = <V2TimConversation>[];
      for (final id in cached) {
        var row = store.displayConversationForId(id);
        if (row == null) {
          final key = ConversationIdCanonical.forStorage(id);
          row = _folderSdkRows[key] ?? _visibleOfficialPlaceholders[key];
        }
        if (row != null) refreshed.add(row);
      }
      return _cacheVisibleConversationView(refreshed,
          retainVisibleIds: refreshed.length == cached.length);
    }
    // Structure changes include the Store's committed order. Keep that order
    // even during scrolling or deferred pin sorting.
    if (cached != null &&
        _selectedFolderId == null &&
        _visibleOfficialPlaceholders.isEmpty &&
        !_visibleConversationView!.any((row) =>
            PlatformOfficialAccountService.matchesOfficialConversation(row) &&
            row.lastMessage == null &&
            row.isPinned != true) &&
        _visibleCacheVisibilityRevision == _visibilityRevision) {
      final current = ChatSessionController.instance.conversations;
      final refreshed = patchVisibleConversationsInSourceOrder(
        current: current,
        cachedVisibleIds: _cachedVisibleIds,
        cachedVisibleCount: cached.length,
        cachedSourceLength: _visibleCacheSourceLength,
        cachedSourceIds: _visibleCacheSourceIds,
      );
      if (refreshed != null) {
        _visibleCacheSourceLength = current.length;
        _visibleCacheStructureRevision = structureRevision;
        ConversationFeedPerf.increment('visible_projection_order_patch');
        return _cacheVisibleConversationView(refreshed);
      }
      final loginUserId = ContactSocialCacheStore.safeLoginUserId();
      final membership = GroupMembershipSyncService.instance;
      final appended = appendVisibleConversationsIfSourceGrewAtTail(
        current: current,
        cachedVisibleIds: _cachedVisibleIds,
        cachedVisibleCount: cached.length,
        cachedSourceLength: _visibleCacheSourceLength,
        cachedSourceIds: _visibleCacheSourceIds,
        suffixVisiblePredicate: (conversation) {
          if (!conversationMatchesScope(conversation, widget.listScope)) {
            return false;
          }
          if (conversation.userID == '10000' ||
              MessageConversationId.isSelfC2CConversation(
                conversation.conversationID,
                loginUserId,
              ) ||
              PlatformOfficialAccountService.shouldHideConversation(
                conversation,
              ) ||
              _isConversationArchived(conversation.conversationID) ||
              !membership.shouldShowConversation(conversation)) {
            return false;
          }
          return true;
        },
      );
      if (appended != null) {
        _visibleCacheSourceLength = current.length;
        _visibleCacheSourceIds =
            current.map((row) => row.conversationID.trim()).toSet();
        _visibleCacheStructureRevision = structureRevision;
        ConversationFeedPerf.increment('visible_projection_tail_append');
        return _cacheVisibleConversationView(appended);
      }
    }
    ConversationFeedPerf.increment('visible_projection_full_filter');
    _visibleCacheStructureRevision = structureRevision;
    final sourceRows = ChatSessionController.instance.conversations;
    _visibleCacheSourceLength = sourceRows.length;
    _visibleCacheSourceIds =
        sourceRows.map((row) => row.conversationID.trim()).toSet();
    _visibleOfficialPlaceholders.clear();
    PlatformOfficialAccountService.reconcileDismissedWithSdkConversations(
      sourceRows,
    );
    final loginUserId = ContactSocialCacheStore.safeLoginUserId();
    final membership = GroupMembershipSyncService.instance;
    final folderId = _selectedFolderId;
    final folder = folderId == null
        ? null
        : ConversationFolderStore.instance.folderById(folderId);
    final folderFilterActive = folderId != null;
    final folderMembers = <String>{
      if (folder != null)
        for (final id in folder.members.keys)
          if (ConversationFolder.folderConversationIdentity(id)
              case final String key)
            key,
    };
    bool isVisible(V2TimConversation conversation) {
      // Scope is cheap and stable. Do not resolve archive aliases and group
      // membership for every row belonging to the other ordinary tab.
      if (!folderFilterActive &&
          !conversationMatchesScope(conversation, widget.listScope)) {
        return false;
      }
      // Resolve membership once per projection, rather than scanning every
      // folder member for each row in a several-thousand-conversation feed.
      if (folderFilterActive &&
          !folderMembers.contains(ConversationFolder.folderConversationIdentity(
              conversation.conversationID))) {
        return false;
      }
      if (conversation.userID == '10000' ||
          MessageConversationId.isSelfC2CConversation(
            conversation.conversationID,
            loginUserId,
          ) ||
          PlatformOfficialAccountService.shouldHideConversation(conversation) ||
          _isConversationArchived(conversation.conversationID) ||
          !membership.shouldShowConversation(conversation)) {
        return false;
      }
      return true;
    }

    bool isEmptyOfficial(V2TimConversation row) =>
        PlatformOfficialAccountService.matchesOfficialConversation(row) &&
        row.lastMessage == null &&
        row.isPinned != true;
    int compareVisibleConversations(V2TimConversation a, V2TimConversation b) {
      final aEmptyOfficial = isEmptyOfficial(a);
      final bEmptyOfficial = isEmptyOfficial(b);
      if (aEmptyOfficial != bEmptyOfficial) return aEmptyOfficial ? 1 : -1;
      return ConversationLocalStore.compareConversationsForUi(a, b);
    }

    final selectedRows = sourceRows.where(isVisible).toList();
    List<V2TimConversation> filtered =
        selectedRows.length == sourceRows.length ? sourceRows : selectedRows;
    // Empty official shells are business placeholders; preserve every real
    // source row's relative order while placing these shells at the bottom.
    if (filtered.any(isEmptyOfficial)) {
      filtered = <V2TimConversation>[
        ...filtered.where((row) => !isEmptyOfficial(row)),
        ...filtered.where(isEmptyOfficial),
      ];
    }
    if (folderFilterActive) {
      filtered = mergeConversationFeedSupplementsInSourceOrder(
        source: filtered,
        supplements: _folderSdkRows.values.where(isVisible),
        compare: compareVisibleConversations,
      );
    }
    final syncState = ConversationListSyncNotifier.instance;
    if (!syncState.hasSyncedOnce &&
        filtered.isNotEmpty &&
        filtered.every((row) =>
            PlatformOfficialAccountService.matchesOfficialConversation(row) &&
            row.lastMessage == null)) {
      return _cacheVisibleConversationView(const <V2TimConversation>[]);
    }
    if (folderFilterActive || widget.listScope == ConversationListScope.group) {
      return _cacheVisibleConversationView(filtered);
    }
    final injected = PlatformOfficialAccountService.conversationsIfMissingFrom(
      filtered,
    );
    for (final row in injected) {
      _visibleOfficialPlaceholders[
          ConversationIdCanonical.forStorage(row.conversationID)] = row;
    }
    return _cacheVisibleConversationView(
      mergeConversationFeedSupplementsInSourceOrder(
        source: filtered,
        supplements: injected,
        compare: compareVisibleConversations,
      ),
    );
  }

  int _unreadForFolder(ConversationFolder folder) {
    final cached = _folderUnreadById[folder.folderId];
    if (cached != null) {
      return cached;
    }
    var sum = 0;
    for (final conversation in ChatSessionController.instance.conversations) {
      if (!folder.containsConversationId(conversation.conversationID)) {
        continue;
      }
      if (_isConversationArchivedInEitherScope(conversation.conversationID)) {
        continue;
      }
      sum += conversation.unreadCount ?? 0;
    }
    return sum;
  }

  String? _folderEmptyMessage() {
    if (_selectedFolderId == null) {
      return null;
    }
    return AppI18n.of(context).t(
      zhHans: '暂无会话，可将会话添加到分组',
      zhHant: '暫無會話，可將會話添加到分組',
      en: 'No chats in this folder yet',
      ja: 'このフォルダに会話はまだありません',
      ko: '이 폴더에 대화가 없습니다',
    );
  }

  Future<String?> _promptFolderName({
    required String title,
    String initialName = '',
  }) async {
    final controller = TextEditingController(text: initialName);
    final result = await showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              maxLength: 16,
              placeholder: AppI18n.of(context).t(
                zhHans: '分组名称',
                zhHant: '分組名稱',
                en: 'Folder name',
                ja: 'フォルダ名',
                ko: '폴더 이름',
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                AppI18n.of(context).t(
                  zhHans: '取消',
                  zhHant: '取消',
                  en: 'Cancel',
                  ja: 'キャンセル',
                  ko: '취소',
                ),
              ),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(name);
              },
              child: Text(
                AppI18n.of(
                  context,
                ).t(zhHans: '确定', zhHant: '確定', en: 'OK', ja: 'OK', ko: '확인'),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final name = result?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  Future<void> _createFolderAndMaybeSelect() async {
    final name = await _promptFolderName(
      title: AppI18n.of(context).t(
        zhHans: '新建分组',
        zhHant: '新建分組',
        en: 'New folder',
        ja: '新しいフォルダ',
        ko: '새 폴더',
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    if (!_ensureFolderNameAvailable(name)) {
      return;
    }
    try {
      final folder = await ConversationFolderSyncService.instance.createFolder(
        name: name,
      );
      if (!mounted) {
        return;
      }
      _selectFolder(folder.folderId);
    } on DuplicateConversationFolderNameException {
      _toastDuplicateFolderName();
    }
  }

  Future<void> _renameFolder(ConversationFolder folder) async {
    final name = await _promptFolderName(
      title: AppI18n.of(context).t(
        zhHans: '重命名分组',
        zhHant: '重新命名分組',
        en: 'Rename folder',
        ja: 'フォルダ名を変更',
        ko: '폴더 이름 변경',
      ),
      initialName: folder.name,
    );
    if (name == null) {
      return;
    }
    if (!_ensureFolderNameAvailable(name, excludingFolderId: folder.folderId)) {
      return;
    }
    try {
      await ConversationFolderSyncService.instance.renameFolder(
        folderId: folder.folderId,
        name: name,
      );
    } on DuplicateConversationFolderNameException {
      _toastDuplicateFolderName();
    }
  }

  bool _ensureFolderNameAvailable(String name, {String? excludingFolderId}) {
    if (!ConversationFolderStore.instance.isNameTaken(
      name,
      excludingFolderId: excludingFolderId,
    )) {
      return true;
    }
    _toastDuplicateFolderName();
    return false;
  }

  void _toastDuplicateFolderName() {
    ToastUtils.toast(
      AppI18n.of(context).t(
        zhHans: '分组名称已存在',
        zhHant: '分組名稱已存在',
        en: 'Folder name already exists',
        ja: '同じ名前のフォルダがあります',
        ko: '이미 있는 폴더 이름입니다',
      ),
    );
  }

  Future<void> _deleteFolder(ConversationFolder folder) async {
    final confirmed = await AppDialog.confirm(
      title: AppI18n.of(context).t(
        zhHans: '删除分组',
        zhHant: '刪除分組',
        en: 'Delete folder',
        ja: 'フォルダを削除',
        ko: '폴더 삭제',
      ),
      message: AppI18n.of(context).t(
        zhHans: '删除后会话会回到「全部」列表，不会删除聊天记录。',
        zhHant: '刪除後會話會回到「全部」列表，不會刪除聊天記錄。',
        en: 'Chats return to All. Messages are kept.',
        ja: '会話は「すべて」に戻ります。メッセージは残ります。',
        ko: '대화는 전체 목록으로 돌아가며 메시지는 유지됩니다.',
      ),
      confirmText: AppI18n.of(
        context,
      ).t(zhHans: '删除', zhHant: '刪除', en: 'Delete', ja: '削除', ko: '삭제'),
      destructive: true,
    );
    if (confirmed != true) {
      return;
    }
    final deletingSelected = _selectedFolderId == folder.folderId;
    await ConversationFolderSyncService.instance.deleteFolder(folder.folderId);
    if (!mounted) {
      return;
    }
    final foldersEmpty = ConversationFolderStore.instance.folders.isEmpty;
    if (deletingSelected) {
      setState(() {
        _invalidateVisibleConversationsCache();
        _selectedFolderId = null;
      });
    }
    if (foldersEmpty && _folderReorderEditing) {
      _exitFolderReorderEditing();
    }
  }

  void _exitFolderReorderEditing() {
    if (!_folderReorderEditing) {
      return;
    }
    setState(() {
      _folderReorderEditing = false;
    });
    unawaited(
      ConversationFolderSyncService.instance.flushPendingReorderToServer(),
    );
  }

  Future<void> _onFolderChipLongPress(ConversationFolder folder) async {
    final action = await AppDialog.actionSheet<String>(
      title: folder.name,
      actions: [
        AppActionSheetItem(
          text: AppI18n.of(context).t(
            zhHans: '重命名',
            zhHant: '重新命名',
            en: 'Rename',
            ja: '名前を変更',
            ko: '이름 변경',
          ),
          value: 'rename',
        ),
        AppActionSheetItem(
          text: AppI18n.of(context).t(
            zhHans: '删除分组',
            zhHant: '刪除分組',
            en: 'Delete folder',
            ja: 'フォルダを削除',
            ko: '폴더 삭제',
          ),
          value: 'delete',
          destructive: true,
        ),
        AppActionSheetItem(
          text: AppI18n.of(context).t(
            zhHans: '重新排序',
            zhHant: '重新排序',
            en: 'Reorder',
            ja: '並べ替え',
            ko: '재정렬',
          ),
          value: 'reorder',
        ),
      ],
      cancelText: AppI18n.of(
        context,
      ).t(zhHans: '取消', zhHant: '取消', en: 'Cancel', ja: 'キャンセル', ko: '취소'),
    );
    if (!mounted) {
      return;
    }
    if (action == 'rename') {
      await _renameFolder(folder);
    } else if (action == 'delete') {
      await _deleteFolder(folder);
    } else if (action == 'reorder') {
      setState(() {
        _folderReorderEditing = true;
      });
    }
  }

  Future<void> _showAddToFolderSheet(V2TimConversation conversation) async {
    final folders = ConversationFolderStore.instance.folders;
    final currentFolder = ConversationFolderStore.instance.folderContaining(
      conversation.conversationID,
    );
    final action = await AppDialog.actionSheet<String>(
      title: AppI18n.of(context).t(
        zhHans: '添加到分组',
        zhHant: '添加到分組',
        en: 'Add to folder',
        ja: 'フォルダに追加',
        ko: '폴더에 추가',
      ),
      actions: [
        for (final folder in folders)
          AppActionSheetItem(
            text: folder.name,
            value: folder.folderId,
            subtitle: folder.folderId == currentFolder?.folderId
                ? AppI18n.of(context).t(
                    zhHans: '已在此分组',
                    zhHant: '已在此分組',
                    en: 'Already in folder',
                    ja: '追加済み',
                    ko: '이미 추가됨',
                  )
                : currentFolder == null
                    ? null
                    : AppI18n.of(context).t(
                        zhHans: '将从「${currentFolder.name}」移入',
                        zhHant: '將從「${currentFolder.name}」移入',
                        en: 'Move from "${currentFolder.name}"',
                        ja: '「${currentFolder.name}」から移動',
                        ko: '"${currentFolder.name}"에서 이동',
                      ),
          ),
        AppActionSheetItem(
          text: AppI18n.of(context).t(
            zhHans: '新建分组',
            zhHant: '新建分組',
            en: 'New folder',
            ja: '新しいフォルダ',
            ko: '새 폴더',
          ),
          value: '__create__',
        ),
      ],
      cancelText: AppI18n.of(
        context,
      ).t(zhHans: '取消', zhHant: '取消', en: 'Cancel', ja: 'キャンセル', ko: '취소'),
    );
    if (action == null || !mounted) {
      return;
    }
    if (action == '__create__') {
      final name = await _promptFolderName(
        title: AppI18n.of(context).t(
          zhHans: '新建分组',
          zhHant: '新建分組',
          en: 'New folder',
          ja: '新しいフォルダ',
          ko: '새 폴더',
        ),
      );
      if (name == null || !mounted) {
        return;
      }
      if (!_ensureFolderNameAvailable(name)) {
        return;
      }
      try {
        final folder = await ConversationFolderSyncService.instance
            .createFolder(name: name);
        await ConversationFolderSyncService.instance.addConversationsToFolder(
          folderId: folder.folderId,
          conversations: [conversation],
        );
      } on DuplicateConversationFolderNameException {
        _toastDuplicateFolderName();
      }
      return;
    }
    await ConversationFolderSyncService.instance.addConversationsToFolder(
      folderId: action,
      conversations: [conversation],
    );
  }

  Future<void> _removeConversationFromSelectedFolder(
    V2TimConversation conversation,
  ) async {
    final folderId = _selectedFolderId;
    if (folderId == null) {
      return;
    }
    await ConversationFolderSyncService.instance.removeConversationsFromFolder(
      folderId: folderId,
      conversations: [conversation],
    );
  }

  String? _lastMessageIdForConversation(String conversationID) {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final conversation in ChatSessionController.instance.conversations) {
      if (!MessageConversationId.sameConversation(
        conversation.conversationID,
        id,
      )) {
        continue;
      }
      final msgId = conversation.lastMessage?.msgID?.trim() ?? '';
      return msgId.isEmpty ? null : msgId;
    }
    return null;
  }

  void toggleEditMode() {
    final nextEditing = !_isEditing;
    if (!nextEditing) {
      _selectedConversationIDs.clear();
    }
    _applyEditingLocalUi(editing: nextEditing);
    _syncEditingStateNotifiers();
  }

  void toggleSelectAll() {
    final visibleConversations = _getVisibleConversations();
    final noticeVisible = _isGroupNoticeEntryVisibleForSelection();
    final visibleIds = visibleConversations.map((c) => c.conversationID);
    if (_isAllSelected(visibleConversations)) {
      _selectedConversationIDs.clear();
    } else {
      _selectedConversationIDs = selectAllIds(
        visibleConvIds: visibleIds,
        noticeVisible: noticeVisible,
      );
    }
    _bumpSelectionLocalUi();
    _syncEditingStateNotifiers();
  }

  void _toggleSelectedConversation(String conversationID) {
    if (_selectedConversationIDs.contains(conversationID)) {
      _selectedConversationIDs.remove(conversationID);
    } else {
      _selectedConversationIDs.add(conversationID);
    }
    _bumpSelectionLocalUi();
    _syncEditingStateNotifiers();
  }

  bool _isAllSelected(List<V2TimConversation> conversations) {
    return isAllSelectedWithGroupNotice(
      visibleConvIds: conversations.map((c) => c.conversationID),
      selected: _selectedConversationIDs,
      noticeVisible: _isGroupNoticeEntryVisibleForSelection(),
    );
  }

  List<V2TimConversation> _getSelectedConversations(
    List<V2TimConversation> conversations,
  ) {
    return conversations
        .where(
          (conversation) =>
              _selectedConversationIDs.contains(conversation.conversationID),
        )
        .toList();
  }

  Future<void> _updateArchivedStatusForConversations(
    List<V2TimConversation> conversations, {
    required bool archived,
  }) async {
    final scopedConversations = conversations
        .where(
          (conversation) =>
              conversationMatchesScope(conversation, widget.listScope),
        )
        .toList();
    if (scopedConversations.isEmpty) {
      return;
    }
    final syncIds = scopedConversations
        .map((c) => c.conversationID.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    await ArchivedConversationSyncService.instance.setArchivedForConversations(
      scopedConversations,
      archived: archived,
    );
    // 取消归档必须等主列表回灌完成，否则返回列表时虚拟 hydrate 还没有该行。
    await ChatSessionController.instance.syncMainListAfterArchiveChange(
      removedIds: archived ? syncIds : const [],
      restoredIds: archived ? const [] : syncIds,
      reason: archived ? 'main_archive' : 'main_unarchive',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _markSelectedAsRead() async {
    final hasManualSelection = _selectedConversationIDs.isNotEmpty;
    final mode = hasManualSelection
        ? MarkReadEditMode.selected
        : MarkReadEditMode.scopeAll;
    final selectedIds = selectionIdsWithoutGroupNotice(
      Set<String>.from(_selectedConversationIDs),
    );
    final archivedIds = allArchivedConversationIds();
    final listScope = markReadListScopeOf(widget.listScope);
    final preview =
        await ConversationUnreadClearService.previewMarkReadForEditAction(
      mode: mode,
      listScope: listScope,
      selectedIds: selectedIds,
      archivedIds: archivedIds,
    );
    final hasGroupNotice = hasManualSelection
        ? _selectedConversationIDs.contains(kGroupNoticeSelectionId)
        : widget.listScope == ConversationListScope.group;
    if (preview.isEmpty && !hasGroupNotice) {
      MarkSelectedReadLog.log('mark_selected_skip_no_unread', {
        'scope': widget.listScope.name,
        'mode': mode.name,
      });
      if (mounted) {
        _selectedConversationIDs.clear();
        _applyEditingLocalUi(editing: false);
      }
      _syncEditingStateNotifiers();
      return;
    }
    if (preview.unreadSumBefore >=
            ConversationUnreadClearService.confirmUnreadSumThreshold &&
        mounted) {
      final confirmed = await confirmMarkReadAllDialog(
        context,
        conversationCount: preview.conversationCount,
        unreadSum: preview.unreadSumBefore,
      );
      if (!confirmed) {
        return;
      }
    }
    final result = await ConversationUnreadClearService.markReadForEditAction(
      mode: mode,
      listScope: listScope,
      selectedIds: selectedIds,
      archivedIds: archivedIds,
      markViewModelReadLocally: _controller.model.markConversationReadLocally,
    );
    if (hasGroupNotice) {
      await GroupNoticeUnreadService.instance.markReadUpToLatest();
    }
    MarkSelectedReadLog.log('mark_selected_ui_exit_edit', {
      'scope': widget.listScope.name,
      'mode': mode.name,
      'cleared': result.conversationCount,
      'sdkPath': result.sdkPath,
      'durationMs': result.durationMs,
    });
    if (mounted) {
      _selectedConversationIDs.clear();
      _applyEditingLocalUi(editing: false);
    }
    _syncEditingStateNotifiers();
  }

  Future<void> _archiveSelected() async {
    // 哨兵群通知 ID 不会出现在 _getSelectedConversations 结果中，归档时悄悄跳过。
    final selectedConversations = _getSelectedConversations(
      _getVisibleConversations(),
    );
    await _updateArchivedStatusForConversations(
      selectedConversations,
      archived: true,
    );
    if (mounted) {
      _selectedConversationIDs.clear();
      _applyEditingLocalUi(editing: false);
    }
    _syncEditingStateNotifiers();
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_archive',
    );
  }

  Future<void> _deleteSelected() async {
    final identity = SessionIdentityService.instance.capture();
    final selectedConversations = _getSelectedConversations(
      _getVisibleConversations(),
    );
    final hasGroupNotice =
        _selectedConversationIDs.contains(kGroupNoticeSelectionId);
    if (selectedConversations.isEmpty && !hasGroupNotice) {
      return;
    }
    if (selectedConversations.isNotEmpty) {
      final confirmed = await _confirmDeleteConversation(
        count: selectedConversations.length,
      );
      if (confirmed != true) return;
      for (final conversation in selectedConversations) {
        await _cleanConversationUnreadQuietly(conversation);
        await _clearConversationHistoryQuietly(conversation);
        final result = await _controller.deleteConversation(
          conversationID: conversation.conversationID,
        );
        if (result?.code == 0) {
          _forgetDeletedFolderRow(conversation.conversationID, identity);
        }
        _notifyHostIfDeletedOpenConversation(conversation.conversationID);
      }
    }
    if (hasGroupNotice) {
      await _deleteGroupNoticeEntry();
    }
    if (mounted) {
      _selectedConversationIDs.clear();
      _applyEditingLocalUi(editing: false);
    }
    _syncEditingStateNotifiers();
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_delete_selected',
    );
  }

  List<V2TimConversation> _getArchivedConversations(Set<String> archivedIDs) {
    final loginUserId = ContactSocialCacheStore.safeLoginUserId();
    final membership = GroupMembershipSyncService.instance;
    return ChatSessionController.instance.conversations
        .where(
          (conversation) =>
              conversation.userID != "10000" &&
              !MessageConversationId.isSelfC2CConversation(
                conversation.conversationID,
                loginUserId,
              ) &&
              conversationIdInArchivedSet(
                archivedIDs,
                conversation.conversationID,
              ) &&
              conversationMatchesScope(conversation, widget.listScope) &&
              membership.shouldShowConversation(conversation),
        )
        .toList();
  }

  Future<void> _openArchivedConversations() async {
    if (DesktopModalLayout.isDesktop(context)) {
      DesktopArchiveHost.open(
        widget.listScope == ConversationListScope.group
            ? DesktopArchiveScope.group
            : DesktopArchiveScope.c2c,
      );
      return;
    }
    await context.pushAppPage(
      ArchivedConversationPage(
        controller: _controller,
        listScope: widget.listScope,
        onTapConversation: _handleOnConvItemTaped,
        lastMessageAbstractBuilder: conversationListLastMessageAbstract,
      ),
    );
  }

  int _normalizeTimestampToMilliseconds(int? timestamp) {
    if (timestamp == null || timestamp <= 0) {
      return 0;
    }
    return timestamp < 1000000000000 ? timestamp * 1000 : timestamp;
  }

  Future<void> _openAllGroupApplications() async {
    unawaited(GroupNoticeUnreadService.instance.markRead());
    if (DesktopModalLayout.isDesktop(context)) {
      DesktopGroupNoticeHost.open();
      return;
    }
    await Navigator.push(
      context,
      AppMaterialPageRoute(
        builder: (context) => const AllGroupApplicationListPage(),
      ),
    );
  }

  Future<void> _pinGroupNoticeEntry() async {
    await GroupNoticeEntrySettingsService.instance.togglePinned();
  }

  Future<void> _toggleGroupNoticeEntryMute() async {
    await GroupNoticeEntrySettingsService.instance.toggleMuted();
  }

  Future<void> _deleteGroupNoticeEntry() async {
    await GroupNoticeUnreadService.instance.markReadUpToLatest();
    final latestMs = latestGroupNoticeTimestampMs(
      GroupJoinApplicationService.instance.applications,
      GroupSystemNoticeService.instance.notices,
    );
    await GroupNoticeEntrySettingsService.instance.dismissEntry(
      latestNoticeMs: latestMs,
    );
  }

  Widget _buildActiveConversationFeed(
    BuildContext context,
    TUITheme theme,
    LocalSetting localSetting,
  ) {
    return ConversationFeedBody(
      workEnabled: _conversationWorkEnabled,
      isGroupTab: widget.listScope == ConversationListScope.group,
      previewCacheScopeKey: _previewCacheScopeKey,
      archiveScope: _archiveScope,
      theme: theme,
      feedScrollController: _feedScrollController,
      scrollPhysics: conversationFeedScrollPhysics(context),
      controller: _controller,
      getVisibleConversations: _getVisibleConversations,
      getArchivedConversations: () =>
          _getArchivedConversations(_archivedIDsNotifier.value),
      conversationTimestampMs: _getConversationTimestampMs,
      buildConversationRow: _buildConversationRowBound,
      resolveConversationAvatarUrl: _conversationAvatarWarmSource,
      onArchivedTap: () {
        if (_isEditing) {
          return;
        }
        unawaited(_openArchivedConversations());
      },
      onGroupNoticeTap: () {
        if (_isEditing) {
          return;
        }
        unawaited(_openAllGroupApplications());
      },
      onGroupNoticePin: _pinGroupNoticeEntry,
      onGroupNoticeToggleMute: _toggleGroupNoticeEntryMute,
      onGroupNoticeDelete: _deleteGroupNoticeEntry,
      editingSelectionListenable: Listenable.merge([
        _editingNotifier,
        _selectionRevision,
      ]),
      isEditingGetter: () => _isEditing,
      isGroupNoticeSelectedGetter: () =>
          _selectedConversationIDs.contains(kGroupNoticeSelectionId),
      onGroupNoticeToggleSelect: _toggleGroupNoticeSelected,
      onEnsureScopeHydrated: () {
        unawaited(_ensureScopeConversationsHydrated());
      },
      onScheduleFeedPageLoad: _scheduleFeedPageLoad,
      scopeHydrationFinished: _scopeHydrationFinished,
      folderFilterActive: _selectedFolderId != null,
      folderEmptyMessage: _folderEmptyMessage(),
      folderLoading: _folderHydratingGeneration == _folderHydrateGeneration &&
          _folderSdkIdentity != null &&
          SessionIdentityService.instance.isCurrent(_folderSdkIdentity!),
      folderLoadFailed: _folderSdkLookupRetryable &&
          _folderSdkIdentity != null &&
          SessionIdentityService.instance.isCurrent(_folderSdkIdentity!),
      onRetryFolderLoad: () {
        final folderId = _selectedFolderId;
        if (folderId != null) setState(() => _hydrateFolderRows(folderId));
      },
      feedBottomExhausted: _feedBottomExhausted,
    );
  }

  Widget _buildActiveConversationFeedForGate(BuildContext context) {
    final theme = _feedRowTheme;
    final localSetting = _feedRowLocalSetting;
    if (theme == null || localSetting == null) {
      return const SizedBox.shrink();
    }
    return _buildActiveConversationFeed(context, theme, localSetting);
  }

  Widget _buildConversationRowBound(V2TimConversation conversation) {
    final context = _feedRowBuildContext;
    final theme = _feedRowTheme;
    final localSetting = _feedRowLocalSetting;
    if (context == null || theme == null || localSetting == null) {
      return const SizedBox.shrink();
    }
    // 行内监听编辑/勾选：feed 行槽会缓存 child，须靠局部状态刷新勾选 UI。
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        ChatSessionController.instance
            .rowRevisionOf(conversation.conversationID),
        ConversationTabStore.instance
            .rowViewListenable(conversation.conversationID),
        _previewProjectionRevisionOf(conversation.conversationID),
      ]),
      builder: (context, __) {
        final latest = ChatSessionController.instance
                .currentConversationById(conversation.conversationID) ??
            conversation;
        return AnimatedBuilder(
          animation: Listenable.merge([_editingNotifier, _selectionRevision]),
          builder: (context, _) {
            if (!_isEditing) {
              return _buildConversationRow(
                context,
                latest,
                theme,
                localSetting,
              );
            }
            final onlineStatus = _friendShipViewModel.userStatusList.firstWhere(
              (item) => item.userID == conversation.userID,
              orElse: () => V2TimUserStatus(statusType: 0),
            );
            return _buildEditingConversationItem(
              latest,
              onlineStatus,
              theme,
              localSetting.isShowOnlineStatus,
            );
          },
        );
      },
    );
  }

  int _getConversationTimestampMs(V2TimConversation conversation) {
    return ConversationLocalStore.displayTimestampMs(conversation);
  }

  int? _conversationLastActiveTimestampSec(V2TimConversation conversation) {
    return ConversationLocalStore.displayTimestampSec(conversation);
  }

  String _buildConversationPreviewSubtitle(V2TimConversation conversation) {
    final draftText = conversation.draftText?.trim() ?? "";
    if (draftText.isNotEmpty) {
      return "[${AppI18n.of(context).t(zhHans: '草稿', zhHant: '草稿', en: 'Draft', ja: '下書き', ko: '임시저장')}]$draftText";
    }
    final lastMessage = conversation.lastMessage;
    if (lastMessage == null) {
      return '';
    }
    if (isRevokedMessage(lastMessage)) {
      return buildRevokedMessagePreviewLabel(lastMessage);
    }
    final groupTipPreview = GroupTipsMessageHelper.messagePreviewAbstract(
      lastMessage,
    );
    if (GroupTipsMessageHelper.isDeprecatedLocalMemberTip(lastMessage) ||
        GroupTipsMessageHelper.isImNativeAdminRoleTip(lastMessage)) {
      return '';
    }
    if (groupTipPreview != null && groupTipPreview.isNotEmpty) {
      return _prefixGroupConversationSender(lastMessage, groupTipPreview);
    }
    if (GroupTipsMessageHelper.isPendingAdministratorMemberTip(lastMessage)) {
      return '';
    }
    if (lastMessage.elemType == MessageElemType.V2TIM_ELEM_TYPE_CUSTOM) {
      final preview = buildConversationLastCustomMessagePreview(lastMessage);
      return _prefixGroupConversationSender(lastMessage, preview);
    }
    final preview = MessageUtils.getAbstractMessageAsync(lastMessage, []);
    return _prefixGroupConversationSender(lastMessage, preview);
  }

  String _prefixGroupConversationSender(V2TimMessage message, String preview) {
    final text = preview.trim();
    if (text.isEmpty || (message.groupID?.trim().isEmpty ?? true)) {
      return text;
    }
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS) {
      return text;
    }
    final senderName = MessageUtils.getDisplayName(message).trim();
    if (senderName.isEmpty) {
      return text;
    }
    return '$senderName: $text';
  }

  Widget _buildConversationFeedOrLoading(
    BuildContext context,
    TUITheme theme,
  ) {
    final session = ChatSessionController.instance;
    final hasRows = session.hasLocalData ||
        session.totalCountForType(1) > 0 ||
        session.totalCountForType(2) > 0;
    if (hasRows) {
      return _buildActiveConversationFeed(
        context,
        theme,
        Provider.of<LocalSetting>(context),
      );
    }
    return _buildConversationLoadingPlaceholder(theme);
  }

  String _conversationShowName(
    V2TimConversation conversation, {
    bool allowAliasFallback = true,
  }) {
    final groupId = conversation.groupID?.trim() ?? '';
    final localName = groupId.isEmpty
        ? null
        : GroupLocalStore.instance.readCached(groupId: groupId)?.groupName;
    return FriendDisplayName.resolveConversation(
      conversation: conversation,
      friendList: _friendShipViewModel.friendList,
      groupList: _friendShipViewModel.groupList,
      localGroupName: localName,
      allowAliasFallback: allowAliasFallback,
    );
  }

  String _conversationFaceUrl(V2TimConversation conversation) {
    return ConversationFaceUrl.resolve(
      userId: conversation.userID,
      conversationFaceUrl: conversation.faceUrl,
      isGroup: conversationMatchesScope(
        conversation,
        ConversationListScope.group,
      ),
      friendList: _friendShipViewModel.friendList,
      groupList: _friendShipViewModel.groupList,
      groupId: conversation.groupID,
    );
  }

  AvatarImageWarmSource _conversationAvatarWarmSource(
    V2TimConversation conversation,
  ) {
    final isGroup = conversationMatchesScope(
      conversation,
      ConversationListScope.group,
    );
    final ownerId = isGroup
        ? ((conversation.groupID?.trim().isNotEmpty ?? false)
            ? conversation.groupID!.trim()
            : conversation.conversationID.replaceFirst('group_', '').trim())
        : (ChatIdFormat.rawUserUid(conversation.userID ?? '').isNotEmpty
            ? ChatIdFormat.rawUserUid(conversation.userID ?? '')
            : ChatIdFormat.rawUserUid(
                conversation.conversationID.replaceFirst('c2c_', ''),
              ));
    if (isGroup) {
      return GroupAvatarSource.fromCached(
        groupId: ownerId,
        fallbackUrl: _conversationFaceUrl(conversation),
      ).warmSource(size: conversationFeedAvatarSize(context));
    }
    final avatarVersion =
        UserProfileLocalService.instance.readCached(ownerId)?.avatarVersion;
    return AvatarImageWarmSource(
      url: _conversationFaceUrl(conversation),
      cacheKey: UserAvatarHelper.cacheKey(
        ownerId: ownerId,
        avatarVersion: avatarVersion,
        isGroup: isGroup,
        variant: 'thumb',
      ),
    );
  }

  Widget _conversationAvatarWidget(
    BuildContext context, {
    required String conversationID,
    required String faceUrl,
    required String showName,
    required bool isGroup,
    V2TimUserStatus? onlineStatus,
    String? groupId,
  }) {
    final avatarSize = conversationFeedAvatarSize(context);
    final ownerId = isGroup
        ? (groupId?.trim() ?? '')
        : ChatIdFormat.rawUserUid(conversationID.replaceFirst('c2c_', ''));
    final avatarVersion = isGroup
        ? null
        : UserProfileLocalService.instance.readCached(ownerId)?.avatarVersion;
    final avatar = SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isGroup)
            AppGroupAvatar(
              key: ValueKey<String>('conversation_avatar_$conversationID'),
              groupId: ownerId.isEmpty ? conversationID : ownerId,
              faceUrl: faceUrl,
              showName: showName,
              size: avatarSize,
            )
          else
            AppUserAvatar(
              key: ValueKey<String>(
                'conversation_avatar_$conversationID',
              ),
              faceUrl: faceUrl,
              showName: showName,
              size: avatarSize,
              type: 1,
              preferRasterPlaceholder: true,
              ownerId: ownerId.isEmpty ? null : ownerId,
              avatarVersion: avatarVersion,
            ),
          if (onlineStatus?.statusType == 1)
            Positioned(
              right: -1.5,
              bottom: -1.5,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.listScope == ConversationListScope.group &&
        isGroup &&
        (groupId?.trim().isNotEmpty ?? false)) {
      return GroupLiveConversationListAvatarWrap(
        groupId: groupId!,
        child: avatar,
      );
    }
    return avatar;
  }

  Map<String, V2TimUserStatus>? _userStatusById;
  List<V2TimUserStatus>? _userStatusIndexSource;

  void _ensureUserStatusIndex() {
    final list = _friendShipViewModel.userStatusList;
    if (identical(list, _userStatusIndexSource) && _userStatusById != null) {
      return;
    }
    _userStatusIndexSource = list;
    final map = <String, V2TimUserStatus>{};
    for (final status in list ?? const <V2TimUserStatus>[]) {
      final id = status.userID?.trim() ?? '';
      if (id.isNotEmpty) {
        map[id] = status;
      }
    }
    _userStatusById = map;
  }

  V2TimUserStatus _onlineStatusForUser(String? userId) {
    final id = userId?.trim() ?? '';
    if (id.isEmpty) {
      return V2TimUserStatus(statusType: 0);
    }
    _ensureUserStatusIndex();
    return _userStatusById![id] ?? V2TimUserStatus(statusType: 0);
  }

  Widget _buildConversationRow(
    BuildContext context,
    V2TimConversation conversationItem,
    TUITheme theme,
    LocalSetting localSetting,
  ) {
    final showName = _conversationShowName(conversationItem);
    final faceUrl = _conversationFaceUrl(conversationItem);
    final isGroup = conversationItem.type == 2 ||
        (conversationItem.groupID?.trim().isNotEmpty ?? false);
    final onlineStatus = _onlineStatusForUser(conversationItem.userID);
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final resolvedOnlineStatus = presence.resolveAvatarOnlineStatus(
      conversationItem.userID ?? '',
      onlineStatus,
      isMutualFriend: friendCanMessage(
        _friendShipViewModel,
        conversationItem.userID ?? '',
      ),
    );
    final displayedOnlineStatus = localSetting.isShowOnlineStatus &&
            conversationItem.userID != null &&
            conversationItem.userID!.isNotEmpty
        ? (PlatformOfficialAccountService.showsVerifiedBadge(
            conversationItem.userID,
          )
            ? V2TimUserStatus(userID: conversationItem.userID, statusType: 1)
            : resolvedOnlineStatus)
        : null;
    final isCurrent = conversationItem.conversationID ==
        _controller.model.selectedConversation?.conversationID;
    final isPinned = conversationItem.isPinned ?? false;
    final previewLastMessage = _previewLastMessageFor(conversationItem);
    final rowExtent = conversationFeedRowExtent(context);
    final avatarSize = conversationFeedAvatarSize(context);

    Widget conversationLineItem() {
      if (ConversationDraftLeaveTrace.isFocused(
        conversationItem.conversationID,
      )) {
        ConversationDraftLeaveTrace.stage(
          'row_build_draft',
          conversationId: conversationItem.conversationID,
          draftText: conversationItem.draftText,
        );
      }
      final background = _conversationItemBackground(theme, pinned: isPinned);
      // 虚拟列表槽位高度与行高助手保持一致，避免相邻置顶中间露白缝。
      return buildConversationListRowBackground(
        color: background,
        animDuration: conversationListRowPinAnimDuration(),
        height: rowExtent,
        animationKey: ValueKey<String>(
          'conv_pin_bg_${conversationItem.conversationID}',
        ),
        child: SizedBox(
          width: double.infinity,
          height: rowExtent,
          child: AppListPressable(
            color: Colors.transparent,
            onTap: () => _handleOnConvItemTaped(conversationItem),
            onTapDown: (_) => _warmConversationOnPress(conversationItem),
            onLongPress: () => _showConversationPeek(conversationItem),
            onSecondaryTapDown: (details) =>
                _showDesktopConversationMenu(conversationItem, details),
            child: Align(
              alignment: Alignment.topCenter,
              child: TIMUIKitConversationItem(
                isCurrent: isCurrent,
                conversationID: conversationItem.conversationID,
                lastMessageAbstractBuilder: conversationListLastMessageAbstract,
                faceUrl: faceUrl,
                avatarWidget: _conversationAvatarWidget(
                  context,
                  conversationID: conversationItem.conversationID,
                  faceUrl: faceUrl,
                  showName: showName,
                  isGroup: isGroup,
                  onlineStatus: displayedOnlineStatus,
                  groupId: conversationItem.groupID,
                ),
                nickName: showName,
                nickNameWidget: _buildConversationNickNameWidget(
                  conversation: conversationItem,
                  showName: showName,
                  fallbackTitleColor: theme.conversationItemTitleTextColor,
                  fontSize: conversationFeedTitleFontSize(context),
                ),
                avatarBorderRadius: BorderRadius.circular(999),
                avatarSize: avatarSize,
                titleFontSize: conversationFeedTitleFontSize(context),
                subtitleFontSize: conversationFeedSubtitleFontSize(context),
                timestampFontSize: conversationFeedTimestampFontSize(context),
                isDisturb: conversationShouldShowMuteIcon(conversationItem),
                lastMsg: previewLastMessage,
                lastActiveTimestamp: previewLastMessage?.timestamp ??
                    _conversationLastActiveTimestampSec(conversationItem),
                isPined: isPinned,
                groupAtInfoList: conversationItem.groupAtInfoList ?? [],
                unreadCount: conversationItem.unreadCount ?? 0,
                draftText: conversationItem.draftText,
                draftTimestamp: conversationItem.draftTimestamp,
                customEmojiStickerList: _previewEmojiList,
                onlineStatus: displayedOnlineStatus,
                convType: conversationItem.type,
              ),
            ),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>(
        'slide|${conversationItem.conversationID}|'
        '${isPinned ? 1 : 0}|${conversationItem.recvOpt ?? 0}',
      ),
      child: lazyConversationSlidable(
        context: context,
        child: conversationLineItem(),
        buildStartActions: () {
          final startSlideActions = _itemStartSlidableBuilder(conversationItem);
          if (startSlideActions == null) {
            return null;
          }
          return startSlideActions;
        },
        buildEndActions: () => _itemEndSlidableBuilder(conversationItem),
      ),
    );
  }

  List<ConversationItemSlidePanel>? _itemStartSlidableBuilder(
    V2TimConversation conversationItem,
  ) {
    if (PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversationItem.userID,
    )) {
      return null;
    }
    final selectedFolderId = _selectedFolderId;
    final inSelectedFolder = selectedFolderId != null &&
        (ConversationFolderStore.instance
                .folderById(selectedFolderId)
                ?.containsConversationId(conversationItem.conversationID) ??
            false);
    return [
      ConversationItemSlidePanel(
        onPressed: (context) {
          _updateArchivedStatusForConversations([
            conversationItem,
          ], archived: true);
        },
        backgroundColor: const Color(0xFFF5A623),
        foregroundColor: Colors.white,
        label: AppI18n.of(
          context,
        ).t(zhHans: '归档', zhHant: '封存', en: 'Archive', ja: 'アーカイブ', ko: '보관'),
        padding: EdgeInsets.zero,
      ),
      if (inSelectedFolder)
        ConversationItemSlidePanel(
          onPressed: (context) {
            Slidable.of(context)?.close();
            unawaited(_removeConversationFromSelectedFolder(conversationItem));
          },
          backgroundColor: const Color(0xFF8E8E93),
          foregroundColor: Colors.white,
          label: AppI18n.of(context).t(
            zhHans: '移出分组',
            zhHant: '移出分組',
            en: 'Remove',
            ja: 'フォルダから外す',
            ko: '폴더에서 제거',
          ),
          padding: EdgeInsets.zero,
        )
      else
        ConversationItemSlidePanel(
          onPressed: (context) {
            Slidable.of(context)?.close();
            unawaited(_showAddToFolderSheet(conversationItem));
          },
          backgroundColor: const Color(0xFF32ADE6),
          foregroundColor: Colors.white,
          label: AppI18n.of(
            context,
          ).t(zhHans: '分组', zhHant: '分組', en: 'Folder', ja: 'フォルダ', ko: '폴더'),
          padding: EdgeInsets.zero,
        ),
    ];
  }

  Widget _buildConversationLoadingPlaceholder(TUITheme theme) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) {
        return buildConversationFeedRowSkeleton(
          context,
          theme,
          variance: index,
          height: conversationFeedRowExtent(context),
        );
      },
    );
  }

  List<ConversationItemSlidePanel> _itemEndSlidableBuilder(
    V2TimConversation conversationItem,
  ) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    if (PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversationItem.userID,
    )) {
      return [
        ConversationItemSlidePanel(
          onPressed: (context) {
            Slidable.of(context)?.close();
            _deleteConversation(conversationItem);
          },
          backgroundColor: const Color(0xFFFF584C),
          foregroundColor: Colors.white,
          label: AppI18n.of(
            context,
          ).t(zhHans: '删除', zhHant: '刪除', en: 'Delete', ja: '削除', ko: '삭제'),
          padding: EdgeInsets.zero,
        ),
      ];
    }
    final isPinned = conversationItem.isPinned ?? false;
    final pinLabel = isPinned
        ? AppI18n.of(context).t(
            zhHans: '取消置顶',
            zhHant: '取消置頂',
            en: 'Unpin',
            ja: 'ピン留め解除',
            ko: '고정 해제',
          )
        : AppI18n.of(
            context,
          ).t(zhHans: '置顶', zhHant: '置頂', en: 'Pin', ja: 'ピン留め', ko: '고정');
    final isDisturb = conversationRecvOptMuted(conversationItem);
    final disturbLabel = isDisturb
        ? AppI18n.of(context).t(
            zhHans: '取消免打扰',
            zhHant: '取消免打擾',
            en: 'Unmute',
            ja: 'ミュート解除',
            ko: '알림 켜기',
          )
        : AppI18n.of(context).t(
            zhHans: '免打扰',
            zhHant: '免打擾',
            en: 'Mute',
            ja: 'ミュート',
            ko: '알림 끄기',
          );
    return [
      ConversationItemSlidePanel(
        onPressed: (context) {
          Slidable.of(context)?.close();
          _pinConversation(conversationItem);
        },
        backgroundColor: const Color(0xFFF5A623),
        foregroundColor: Colors.white,
        label: pinLabel,
        padding: EdgeInsets.zero,
      ),
      ConversationItemSlidePanel(
        onPressed: (context) {
          Slidable.of(context)?.close();
          unawaited(_toggleConversationDisturb(conversationItem));
        },
        backgroundColor: theme.primaryColor ?? hexToColor("006EFF"),
        foregroundColor: Colors.white,
        label: disturbLabel,
        padding: EdgeInsets.zero,
      ),
      ConversationItemSlidePanel(
        onPressed: (context) {
          Slidable.of(context)?.close();
          _deleteConversation(conversationItem);
        },
        backgroundColor: const Color(0xFFFF584C),
        foregroundColor: Colors.white,
        label: AppI18n.of(
          context,
        ).t(zhHans: '删除', zhHant: '刪除', en: 'Delete', ja: '削除', ko: '삭제'),
        padding: EdgeInsets.zero,
      ),
    ];
  }

  Widget _buildEditingConversationItem(
    V2TimConversation conversation,
    V2TimUserStatus? onlineStatus,
    TUITheme theme,
    bool isShowOnlineStatus,
  ) {
    final showName = _conversationShowName(conversation);
    final faceUrl = _conversationFaceUrl(conversation);
    final isGroup = conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
    final isPinned = conversation.isPinned ?? false;
    final previewLastMessage = _previewLastMessageFor(conversation);
    final isSelected = _selectedConversationIDs.contains(
      conversation.conversationID,
    );
    final avatarSize = conversationFeedAvatarSize(context);
    if (ConversationDraftLeaveTrace.isFocused(conversation.conversationID)) {
      ConversationDraftLeaveTrace.stage(
        'row_build_draft',
        conversationId: conversation.conversationID,
        draftText: conversation.draftText,
        extras: const <String, Object?>{'editing': 1},
      );
    }
    return Material(
      color: isPinned
          ? theme.conversationItemPinedBgColor
          : theme.conversationItemBgColor,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: GestureDetector(
              onTap: () =>
                  _toggleSelectedConversation(conversation.conversationID),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? (theme.primaryColor ?? const Color(0xFF1E90FF))
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? (theme.primaryColor ?? const Color(0xFF1E90FF))
                        : (theme.weakTextColor ?? const Color(0xFFBDBDBD)),
                    width: 1.8,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  _toggleSelectedConversation(conversation.conversationID),
              child: TIMUIKitConversationItem(
                isCurrent: false,
                conversationID: conversation.conversationID,
                lastMessageAbstractBuilder: conversationListLastMessageAbstract,
                faceUrl: faceUrl,
                avatarWidget: _conversationAvatarWidget(
                  context,
                  conversationID: conversation.conversationID,
                  faceUrl: faceUrl,
                  showName: showName,
                  isGroup: isGroup,
                  groupId: conversation.groupID,
                ),
                nickName: showName,
                nickNameWidget: _buildConversationNickNameWidget(
                  conversation: conversation,
                  showName: showName,
                  fallbackTitleColor: theme.conversationItemTitleTextColor,
                  fontSize: conversationFeedTitleFontSize(context),
                ),
                avatarBorderRadius: BorderRadius.circular(999),
                avatarSize: avatarSize,
                titleFontSize: conversationFeedTitleFontSize(context),
                subtitleFontSize: conversationFeedSubtitleFontSize(context),
                timestampFontSize: conversationFeedTimestampFontSize(context),
                isDisturb: conversationShouldShowMuteIcon(conversation),
                lastMsg: previewLastMessage,
                lastActiveTimestamp: previewLastMessage?.timestamp ??
                    ConversationLocalStore.displayTimestampSec(conversation),
                isPined: isPinned,
                groupAtInfoList: conversation.groupAtInfoList ?? [],
                unreadCount: conversation.unreadCount ?? 0,
                draftText: conversation.draftText,
                draftTimestamp: conversation.draftTimestamp,
                customEmojiStickerList: _previewEmojiList,
                onlineStatus: isShowOnlineStatus &&
                        conversation.userID != null &&
                        conversation.userID!.isNotEmpty
                    ? onlineStatus
                    : null,
                convType: conversation.type,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditBottomActionBar(TUITheme theme) {
    return SafeArea(
      top: false,
      child: Container(
        height: kBottomNavigationBarHeight,
        decoration: BoxDecoration(
          color: _conversationItemBackground(theme, pinned: false),
          border: Border(
            top: BorderSide(
              color: theme.weakDividerColor ?? hexToColor("E5E6E9"),
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                // 无勾选 = 全部已读；有勾选 = 标记已读（只清选中）。始终可点。
                onPressed: _markSelectedAsRead,
                child: Text(
                  markReadActionLabel(
                    context,
                    hasSelection: _selectedConversationIDs.isNotEmpty,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed:
                    _selectedConversationIDs.isEmpty ? null : _archiveSelected,
                child: Text(
                  AppI18n.of(context).t(
                    zhHans: '归档',
                    zhHant: '封存',
                    en: 'Archive',
                    ja: 'アーカイブ',
                    ko: '보관',
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed:
                    _selectedConversationIDs.isEmpty ? null : _deleteSelected,
                child: Text(
                  AppI18n.of(context).t(
                    zhHans: '删除',
                    zhHant: '刪除',
                    en: 'Delete',
                    ja: '削除',
                    ko: '삭제',
                  ),
                  style: const TextStyle(color: Color(0xFFEF3B36)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeVisible = RouteVisibility.isRouteVisible(context);
    final tabActive = HomeTabActivity.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    final workEnabled = tabActive && routeVisible;
    final becameActive = workEnabled && !_conversationWorkEnabled;
    _conversationWorkEnabled = workEnabled;
    if (becameActive) {
      _invalidateVisibleConversationsCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _conversationWorkEnabled) {
          _invalidateVisibleConversationsCache();
          _queueVisiblePreviewProjections();
          if (_folderUnreadRefreshDeferred) {
            _scheduleFolderUnreadRefresh();
          }
        }
      });
    }
    // Keep this owner mounted across tab changes. Replacing Consumer2 with
    // its body disposes the feed's scroll state and row caches on every switch.
    return Consumer2<LocalSetting, DefaultThemeData>(
      builder: (context, localSetting, themeModel, _) {
        return _buildConversationBody(
          context,
          routeVisible: routeVisible,
          tabActive: workEnabled,
          localSetting: localSetting,
          theme: themeModel.theme,
        );
      },
    );
  }

  Widget _buildConversationBody(
    BuildContext context, {
    required bool routeVisible,
    required bool tabActive,
    required LocalSetting localSetting,
    required TUITheme theme,
  }) {
    if (widget.listScope == ConversationListScope.group) {
      if (tabActive && routeVisible) {
        _scheduleGroupBootstrapWhenActive();
      } else if (!tabActive) {
        GroupLiveIndexSyncService.instance.onGroupTabHidden();
        _groupBootstrapQueued = false;
      }
    }
    _scheduleDesktopLoginBannerRefreshOnVisible(tabActive && routeVisible);
    _feedRowBuildContext = context;
    _feedRowTheme = theme;
    _feedRowLocalSetting = localSetting;
    if (tabActive && routeVisible) {
      judgeGuide('conversation', context);
    }
    return TickerMode(
      enabled: tabActive && routeVisible,
      child: Scaffold(
        backgroundColor: theme.weakBackgroundColor ?? Colors.white,
        body: Column(
          children: [
            SearchEntry(
              conversationController: widget.conversationController,
              plusType: PlusType.create,
              onClickSearch: widget.onClickSearch,
              listScope: widget.listScope,
              directToChat: (conversation) {
                _handleOnConvItemTaped(conversation);
              },
            ),
            if (_hostsDesktopLoginBanner)
              ValueListenableBuilder<List<UserDevice>>(
                valueListenable: DesktopLoginSessionService.instance.devices,
                builder: (context, devices, _) {
                  final text = DesktopLoginSessionService.instance.bannerText;
                  if (text == null || text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return DesktopLoginBanner(
                    text: text,
                    onTap: () async {
                      await DesktopLoginSessionsPage.open(context);
                      if (!mounted) {
                        return;
                      }
                      unawaited(
                        _refreshDesktopLoginBanner(
                          reason: 'detail_closed',
                          force: true,
                        ),
                      );
                    },
                  );
                },
              ),
            ValueListenableBuilder<List<ConversationFolder>>(
              valueListenable: ConversationFolderStore.instance.foldersNotifier,
              builder: (context, folders, _) {
                if (folders.isEmpty) {
                  if (_folderReorderEditing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_folderReorderEditing) {
                        return;
                      }
                      _exitFolderReorderEditing();
                    });
                  }
                  return const SizedBox.shrink();
                }
                return ConversationFolderChipBar(
                  folders: folders,
                  selectedFolderId: _selectedFolderId,
                  unreadForFolder: _unreadForFolder,
                  reorderEditing: _folderReorderEditing,
                  onExitReorderEditing: _exitFolderReorderEditing,
                  onDeleteFolder: _deleteFolder,
                  onSelectAll: () {
                    _selectFolder(null);
                  },
                  onSelectFolder: (folderId) {
                    _selectFolder(folderId);
                  },
                  onCreateFolder: () {
                    unawaited(_createFolderAndMaybeSelect());
                  },
                  onFolderLongPress: (folder) {
                    unawaited(_onFolderChipLongPress(folder));
                  },
                  onReorderFolders: (oldIndex, newIndex) {
                    unawaited(
                      ConversationFolderSyncService.instance.reorderFolders(
                        oldIndex: oldIndex,
                        newIndex: newIndex,
                      ),
                    );
                  },
                );
              },
            ),
            // E3（v15/v16）：Rebase banner——本端离线期间出现大量积压消息时，
            // 向用户提示「已跳过 X 条，点击可前往查看」。
            // 30s TTL 后自动消失，避免长期打扰。
            RebaseBannersList(
              onTapConversation: (convId) {
                // 当前实现：仅做 dismiss。后续可扩展为导航到 chat 页。
                ConversationRebasePolicy.instance.dismissBanner(convId);
              },
            ),
            Expanded(
              child: ConversationFolderSwipeRegion(
                enabled: ConversationFolderStore.instance.folders.isNotEmpty &&
                    !_folderReorderEditing &&
                    !_isEditing,
                onSwipe: _selectAdjacentFolderFromSwipe,
                child: ConversationFeedSyncGate(
                  workEnabled: _conversationWorkEnabled,
                  theme: theme,
                  feedScrollController: _feedScrollController,
                  cachedFeedBuilder: _buildConversationFeedOrLoading,
                  feedBuilder: _buildActiveConversationFeedForGate,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedBuilder(
          animation: Listenable.merge([_editingNotifier, _selectionRevision]),
          builder: (context, _) {
            if (!_isEditing || widget.hostEditActionBar) {
              return const SizedBox.shrink();
            }
            return _buildEditBottomActionBar(theme);
          },
        ),
      ),
    );
  }
}

class _ConversationPreviewProjectionEntry {
  _ConversationPreviewProjectionEntry({
    required this.token,
    required this.message,
    String? capturedFingerprint,
  }) : messageFingerprint = capturedFingerprint ?? conversationPreviewFingerprint(message);

  final int token;
  final V2TimMessage? message;
  final String messageFingerprint;
}

class ArchivedConversationPage extends StatefulWidget {
  final TIMUIKitConversationController controller;
  final ConversationListScope listScope;
  final ValueChanged<V2TimConversation?> onTapConversation;
  final LastMessageAbstractBuilder? lastMessageAbstractBuilder;

  /// 嵌在主壳左侧：返回关闭归档列表，右侧继续显示当前聊天。
  final bool shellEmbedded;
  final VoidCallback? onClose;

  const ArchivedConversationPage({
    Key? key,
    required this.controller,
    required this.listScope,
    required this.onTapConversation,
    this.lastMessageAbstractBuilder,
    this.shellEmbedded = false,
    this.onClose,
  }) : super(key: key);

  @override
  State<ArchivedConversationPage> createState() =>
      _ArchivedConversationPageState();
}

class _ArchivedConversationPageState extends State<ArchivedConversationPage> {
  late final SessionIdentity _archiveIdentity;
  bool get _archiveSessionCurrent =>
      mounted && SessionIdentityService.instance.isCurrent(_archiveIdentity);
  bool _isEditing = false;
  Set<String> _selectedConversationIDs = <String>{};
  final TUIFriendShipViewModel _friendShipViewModel =
      serviceLocator<TUIFriendShipViewModel>();

  final ScrollController _archiveScrollController = ScrollController();
  List<V2TimConversation> _archiveItems = <V2TimConversation>[];
  final Set<String> _displayedIds = <String>{};
  List<String> _missingArchivedIds = <String>[];
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _archivePageError = false;
  bool _hasMore = true;
  bool _pageLoadScheduled = false;
  int? _cursorActiveTime;
  String? _cursorConversationId;
  int _loadGeneration = 0;
  bool _coldScanScheduled = false;
  bool _coldScanPending = false;
  bool _localArchiveExhausted = false;
  Timer? _archiveReloadDebounce;
  StreamSubscription<List<V2TimConversation>>? _archiveSdkSubscription;
  final Map<String, V2TimMessage?> _archivePreviewByConversation =
      <String, V2TimMessage?>{};
  final Map<String, V2TimConversation> _pendingArchivePreviewRows =
      <String, V2TimConversation>{};
  bool _archivePreviewDrainScheduled = false;

  static const int _archivePreviewRowsPerFrame = 6;

  ConversationArchiveScope get _archiveScope =>
      archiveScopeForListScope(widget.listScope);

  ValueNotifier<Set<String>> get _archivedIDsNotifier =>
      archivedConversationIDsNotifierFor(_archiveScope);

  int? _archiveConvTypeFilter() {
    switch (widget.listScope) {
      case ConversationListScope.c2c:
        return 1;
      case ConversationListScope.group:
        return 2;
      case ConversationListScope.all:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _archiveIdentity = SessionIdentityService.instance.capture();
    _archiveScrollController.addListener(_onArchiveScroll);
    _archivedIDsNotifier.addListener(_onArchivedIdsChanged);
    widget.controller.model.addListener(_onArchiveModelChanged);
    _archiveSdkSubscription = ConversationSyncService
        .instance.archivedSdkChanges
        .listen(_applyArchiveSdkChanges);
    unawaited(_reloadArchiveFirstPage());
  }

  @override
  void dispose() {
    _archiveReloadDebounce?.cancel();
    _archiveSdkSubscription?.cancel();
    widget.controller.model.removeListener(_onArchiveModelChanged);
    _archivedIDsNotifier.removeListener(_onArchivedIdsChanged);
    _archiveScrollController.removeListener(_onArchiveScroll);
    _archiveScrollController.dispose();
    _pendingArchivePreviewRows.clear();
    _archivePreviewByConversation.clear();
    super.dispose();
  }

  void _onArchiveModelChanged() {
    for (final conversation in _archiveItems) {
      _queueArchivePreviewProjection(conversation);
    }
  }

  void _applyArchiveSdkChanges(List<V2TimConversation> rows) {
    if (!_archiveSessionCurrent || _archiveItems.isEmpty) return;
    final byId = <String, V2TimConversation>{
      for (final row in rows)
        ConversationIdCanonical.forStorage(row.conversationID): row,
    };
    var changed = false;
    for (var i = 0; i < _archiveItems.length; i++) {
      final row = byId[
          ConversationIdCanonical.forStorage(_archiveItems[i].conversationID)];
      if (row == null) continue;
      _archiveItems[i] = row;
      _queueArchivePreviewProjection(row);
      changed = true;
    }
    // Keep the current reading position. A subsequent page entry obtains the
    // activity order from the small archive index.
    if (changed) setState(() {});
  }

  void _queueArchivePreviewProjection(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    if (id.isEmpty) return;
    _pendingArchivePreviewRows[id] = conversation;
    if (_archivePreviewDrainScheduled) return;
    _archivePreviewDrainScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _archivePreviewDrainScheduled = false;
      if (!mounted) return;
      _drainArchivePreviewProjection();
    });
  }

  void _drainArchivePreviewProjection() {
    if (!mounted || _pendingArchivePreviewRows.isEmpty) return;
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final ids = _pendingArchivePreviewRows.keys
        .take(_archivePreviewRowsPerFrame)
        .toList(growable: false);
    var needsPaint = false;
    for (final id in ids) {
      final conversation = _pendingArchivePreviewRows.remove(id);
      if (conversation == null) continue;
      final previous = _archivePreviewByConversation.containsKey(id)
          ? _archivePreviewByConversation[id]
          : conversation.lastMessage;
      final resolved =
          ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
        globalModel: globalModel,
        conversation: conversation,
      );
      _archivePreviewByConversation[id] = resolved;
      needsPaint = needsPaint ||
          previous?.msgID != resolved?.msgID ||
          previous?.id != resolved?.id ||
          previous?.timestamp != resolved?.timestamp ||
          previous?.status != resolved?.status;
    }
    if (needsPaint) setState(() {});
    if (_pendingArchivePreviewRows.isNotEmpty) {
      final next = _pendingArchivePreviewRows.values.first;
      _queueArchivePreviewProjection(next);
    }
  }

  V2TimMessage? _archivePreviewFor(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    return _archivePreviewByConversation.containsKey(id)
        ? _archivePreviewByConversation[id]
        : conversation.lastMessage;
  }

  void _onArchivedIdsChanged() {
    if (!ConversationPerfFlags.archivePageForbidReloadFirstWhilePaging) {
      unawaited(_reloadArchiveFirstPage());
      return;
    }
    // 分页/已有列表：禁止立刻整表 first（日志连续 prepare+first 生涩）。
    if (_loadingMore || _initialLoading) {
      ConversationPerfGateLog.log(
        'archive_page_reload_first_deferred',
        extras: <String, Object?>{
          'items': _archiveItems.length,
          'loadingMore': _loadingMore ? 1 : 0,
          'initial': _initialLoading ? 1 : 0,
        },
      );
      return;
    }
    if (_archiveItems.isNotEmpty) {
      _archiveReloadDebounce?.cancel();
      _archiveReloadDebounce = Timer(const Duration(seconds: 2), () {
        _archiveReloadDebounce = null;
        if (!mounted || _loadingMore || _initialLoading) {
          return;
        }
        unawaited(_reloadArchiveFirstPage());
      });
      ConversationPerfGateLog.log(
        'archive_page_reload_first_deferred',
        extras: <String, Object?>{
          'items': _archiveItems.length,
          'debounceMs': 2000,
        },
      );
      return;
    }
    unawaited(_reloadArchiveFirstPage());
  }

  void _onArchiveScroll() {
    if (!_archiveScrollController.hasClients ||
        _loadingMore ||
        _initialLoading ||
        !_hasMore) {
      return;
    }
    final position = _archiveScrollController.position;
    if (position.maxScrollExtent <= 0) {
      if (!_archivePageError) _scheduleArchivePageLoad();
      return;
    }
    if (position.pixels >= position.maxScrollExtent - 240) {
      _scheduleArchivePageLoad();
    }
  }

  void _scheduleArchivePageLoad() {
    if (_pageLoadScheduled || _loadingMore || !_hasMore) {
      return;
    }
    _pageLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageLoadScheduled = false;
      if (!mounted || _loadingMore || !_hasMore) {
        return;
      }
      unawaited(_loadMoreArchived());
    });
  }

  List<V2TimConversation> _filterVisible(List<V2TimConversation> input) {
    final loginUserId = ContactSocialCacheStore.safeLoginUserId();
    final membership = GroupMembershipSyncService.instance;
    return input
        .where(
          (conversation) =>
              conversation.userID != '10000' &&
              !MessageConversationId.isSelfC2CConversation(
                conversation.conversationID,
                loginUserId,
              ) &&
              conversationMatchesScope(conversation, widget.listScope) &&
              membership.shouldShowConversation(conversation),
        )
        .toList(growable: false);
  }

  /// 兼容旧调用：编辑全选等仍用当前已加载列表。
  List<V2TimConversation> _getArchivedConversations(Set<String> archivedIDs) {
    if (_archiveItems.isNotEmpty || !_initialLoading) {
      return List<V2TimConversation>.from(_archiveItems);
    }
    final loginUserId = ContactSocialCacheStore.safeLoginUserId();
    final membership = GroupMembershipSyncService.instance;
    return ChatSessionController.instance.conversations
        .where(
          (conversation) =>
              conversation.userID != "10000" &&
              !MessageConversationId.isSelfC2CConversation(
                conversation.conversationID,
                loginUserId,
              ) &&
              conversationIdInArchivedSet(
                archivedIDs,
                conversation.conversationID,
              ) &&
              conversationMatchesScope(conversation, widget.listScope) &&
              membership.shouldShowConversation(conversation),
        )
        .toList();
  }

  Future<void> _probeMissingArchivedIds(Set<String> archivedIds) async {
    if (archivedIds.isEmpty) {
      _missingArchivedIds = <String>[];
      return;
    }
    final existing = await ConversationLocalStore.instance.conversationsByIds(
      archivedIds.toList(growable: false),
      caller: 'archive_probe',
    );
    final found = <String>{};
    for (final conversation in existing) {
      final id = conversation.conversationID.trim();
      if (id.isNotEmpty) {
        found.add(id);
      }
    }
    _missingArchivedIds = archivedIds
        .where(
          (id) =>
              !found.any((f) => MessageConversationId.sameConversation(f, id)),
        )
        .toList(growable: true);
  }

  void _scheduleColdArchiveScan(int generation, Set<String> archivedIds) {
    if (_coldScanScheduled) {
      return;
    }
    _coldScanScheduled = true;
    _coldScanPending = true;
    unawaited(() async {
      try {
        final cold = await ConversationLocalStore.instance.listColdArchivedIds(
          originalArchivedIds: archivedIds,
        );
        if (!_archiveSessionCurrent || generation != _loadGeneration) {
          return;
        }
        _missingArchivedIds = List<String>.from(cold);
        if (!mounted) {
          return;
        }
        setState(() {
          _coldScanPending = false;
          if (_hitArchiveEmergencyCap()) {
            _hasMore = false;
          } else if (_missingArchivedIds.isNotEmpty) {
            _hasMore = true;
          } else if (_localArchiveExhausted) {
            _hasMore = false;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_archiveSessionCurrent && generation == _loadGeneration)
            _onArchiveScroll();
        });
      } catch (error) {
        if (_archiveSessionCurrent && generation == _loadGeneration) {
          setState(() {
            _archivePageError = true;
            _coldScanPending = false;
          });
        }
      } finally {
        if (generation == _loadGeneration) {
          _coldScanScheduled = false;
          _coldScanPending = false;
        }
      }
    }());
  }

  bool _hitArchiveEmergencyCap() {
    final cap = ConversationPerfFlags.archiveListEmergencyCap;
    return cap > 0 && _archiveItems.length >= cap;
  }

  Future<List<V2TimConversation>> _loadArchivePage({
    required Set<String> archivedIds,
    int? beforeActiveTime,
    String? beforeConversationId,
  }) async {
    final pageSize = ConversationPerfFlags.uiScrollPageSize;
    if (ConversationPerfFlags.archiveTruePageEnabled) {
      return ConversationLocalStore.instance.loadOlderAmongPreparedArchiveIds(
        beforeActiveTime: beforeActiveTime,
        beforeConversationId: beforeConversationId,
        limit: pageSize,
        convType: _archiveConvTypeFilter(),
      );
    }
    return ConversationLocalStore.instance.loadOlderAmongIds(
      conversationIds: archivedIds,
      beforeActiveTime: beforeActiveTime,
      beforeConversationId: beforeConversationId,
      limit: pageSize,
      convType: _archiveConvTypeFilter(),
    );
  }

  Future<List<V2TimConversation>> _fetchColdHydrateBatch(int budget) async {
    if (budget <= 0 || _missingArchivedIds.isEmpty) {
      return const [];
    }
    final take = budget > _missingArchivedIds.length
        ? _missingArchivedIds.length
        : budget;
    final batch = _missingArchivedIds.sublist(0, take);
    final generation = _loadGeneration;
    final identity = SessionIdentityService.instance.capture();
    final result =
        await ConversationTabStore.instance.readSdkConversationsByIds(batch);
    if (!mounted ||
        generation != _loadGeneration ||
        !SessionIdentityService.instance.isCurrent(identity)) return const [];
    if (result.code != 0) {
      // Do not consume IDs on a transient SDK failure; scrolling can retry.
      throw StateError('Archive SDK hydration failed: ${result.code}');
    }
    final hydrated = await ConversationSyncService.instance
        .commitSdkHydratedConversations(result.conversationList,
            expectedIdentity: identity);
    if (!mounted ||
        generation != _loadGeneration ||
        !SessionIdentityService.instance.isCurrent(identity)) return const [];
    _missingArchivedIds.removeWhere(batch.contains);
    if (hydrated.isEmpty) {
      return const [];
    }
    if (ConversationPerfFlags.archiveTruePageEnabled) {
      await ConversationLocalStore.instance.addArchiveJoinConversationIds(
        hydrated.map((c) => c.conversationID),
      );
    }
    final sorted = List<V2TimConversation>.of(hydrated)
      ..sort(ConversationLocalStore.compareConversationsForUi);
    return sorted;
  }

  void _appendArchiveItems(List<V2TimConversation> next) {
    final visible = _filterVisible(next);
    for (final conversation in visible) {
      final id = conversation.conversationID.trim();
      if (id.isEmpty || _displayedIds.contains(id)) {
        continue;
      }
      if (_displayedIds.any(
        (d) => MessageConversationId.sameConversation(d, id),
      )) {
        continue;
      }
      _displayedIds.add(id);
      _archiveItems.add(conversation);
      _queueArchivePreviewProjection(conversation);
    }
    if (_archiveItems.isNotEmpty) {
      final last = _archiveItems.last;
      _cursorActiveTime = ConversationLocalStore.activeTimeMs(last);
      _cursorConversationId = last.conversationID.trim();
    }
  }

  bool _computeArchiveHasMore({
    required int lastPageCount,
    required int pageSize,
  }) {
    if (_hitArchiveEmergencyCap()) {
      return false;
    }
    if (lastPageCount >= pageSize) {
      return true;
    }
    if (!_localArchiveExhausted) {
      return true;
    }
    if (_coldScanPending) {
      return true;
    }
    return _missingArchivedIds.isNotEmpty;
  }

  Future<void> _reloadArchiveFirstPage() async {
    final generation = ++_loadGeneration;
    final archivedIds = Set<String>.from(_archivedIDsNotifier.value);
    _coldScanScheduled = false;
    _coldScanPending = false;
    _localArchiveExhausted = false;
    if (mounted) {
      setState(() {
        _initialLoading = true;
        _loadingMore = false;
        _archivePageError = false;
        _hasMore = true;
        _archiveItems = <V2TimConversation>[];
        _displayedIds.clear();
        _cursorActiveTime = null;
        _cursorConversationId = null;
        _missingArchivedIds = <String>[];
      });
    }
    try {
      final pageSize = ConversationPerfFlags.uiScrollPageSize;
      final useTruePage = ConversationPerfFlags.archiveTruePageEnabled;
      final deferProbe = ConversationPerfFlags.archiveDeferFullMissingProbe;

      if (useTruePage) {
        await ConversationLocalStore.instance.prepareArchiveIdSet(
          conversationIds: archivedIds,
        );
      } else if (!deferProbe) {
        await _probeMissingArchivedIds(archivedIds);
      }
      if (!_archiveSessionCurrent || generation != _loadGeneration) {
        return;
      }

      var page = await _loadArchivePage(archivedIds: archivedIds);
      if (!_archiveSessionCurrent || generation != _loadGeneration) {
        return;
      }

      if (!deferProbe &&
          page.length < pageSize &&
          _missingArchivedIds.isNotEmpty) {
        final hydrated = await _fetchColdHydrateBatch(pageSize - page.length);
        if (hydrated.isNotEmpty) {
          page = [...page, ...hydrated];
          page.sort(ConversationLocalStore.compareConversationsForUi);
        }
      }

      if (!_archiveSessionCurrent || generation != _loadGeneration) {
        return;
      }

      _localArchiveExhausted = page.length < pageSize;
      if (useTruePage || deferProbe) {
        _coldScanPending = true;
      }
      setState(() {
        _archiveItems = <V2TimConversation>[];
        _displayedIds.clear();
        _appendArchiveItems(page);
        _hasMore = _computeArchiveHasMore(
          lastPageCount: page.length,
          pageSize: pageSize,
        );
        _initialLoading = false;
      });

      if (useTruePage || deferProbe) {
        _scheduleColdArchiveScan(generation, archivedIds);
      }

      if (ConversationPerfFlags.archivePagePhaseLogEnabled) {
        ConversationPerfGateLog.log(
          'archive_page_first',
          extras: <String, Object?>{
            'gen': generation,
            'pageCount': page.length,
            'idSetSize': archivedIds.length,
            'truePage': useTruePage ? 1 : 0,
          },
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _onArchiveScroll();
      });
    } catch (e, st) {
      debugPrint('archive first page failed: $e\n$st');
      if (_archiveSessionCurrent && generation == _loadGeneration) {
        setState(() {
          _initialLoading = false;
          _archivePageError = true;
          _hasMore = _missingArchivedIds.isNotEmpty;
        });
      }
    }
  }

  Future<void> _loadMoreArchived() async {
    if (_loadingMore || !_hasMore || _initialLoading) {
      return;
    }
    if (_hitArchiveEmergencyCap()) {
      setState(() => _hasMore = false);
      return;
    }
    final generation = _loadGeneration;
    final archivedIds = Set<String>.from(_archivedIDsNotifier.value);
    if (archivedIds.isEmpty) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() {
      _loadingMore = true;
      _archivePageError = false;
    });
    try {
      final pageSize = ConversationPerfFlags.uiScrollPageSize;
      var page = <V2TimConversation>[];

      if (!_localArchiveExhausted) {
        page = await _loadArchivePage(
          archivedIds: archivedIds,
          beforeActiveTime: _cursorActiveTime,
          beforeConversationId: _cursorConversationId,
        );
        if (!_archiveSessionCurrent || generation != _loadGeneration) {
          return;
        }
        if (page.length < pageSize) {
          _localArchiveExhausted = true;
        }
      }

      if (page.isEmpty && _missingArchivedIds.isNotEmpty) {
        final budget = ConversationPerfFlags.archiveColdHydrateBatchSize > 0
            ? ConversationPerfFlags.archiveColdHydrateBatchSize
            : pageSize;
        page = await _fetchColdHydrateBatch(budget);
      } else if (page.length < pageSize && _missingArchivedIds.isNotEmpty) {
        final need = pageSize - page.length;
        final cap = ConversationPerfFlags.archiveColdHydrateBatchSize > 0
            ? ConversationPerfFlags.archiveColdHydrateBatchSize
            : need;
        final hydrated = await _fetchColdHydrateBatch(need > cap ? cap : need);
        if (hydrated.isNotEmpty) {
          page = [...page, ...hydrated];
          page.sort(ConversationLocalStore.compareConversationsForUi);
        }
      }

      if (!_archiveSessionCurrent || generation != _loadGeneration) {
        return;
      }
      setState(() {
        final beforeCount = _archiveItems.length;
        _appendArchiveItems(page);
        final added = _archiveItems.length - beforeCount;
        if (added == 0 &&
            _localArchiveExhausted &&
            _missingArchivedIds.isEmpty) {
          _hasMore = false;
        } else {
          _hasMore = _computeArchiveHasMore(
            lastPageCount: added > 0 ? page.length : 0,
            pageSize: pageSize,
          );
        }
        if (_hitArchiveEmergencyCap()) {
          _hasMore = false;
        }
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_archiveSessionCurrent && generation == _loadGeneration)
          _onArchiveScroll();
      });
    } catch (e, st) {
      debugPrint('archive load more failed: $e\n$st');
      if (_archiveSessionCurrent && generation == _loadGeneration) {
        setState(() {
          _loadingMore = false;
          _archivePageError = true;
        });
      }
    }
  }

  Future<void> _clearConversationHistoryQuietly(
    V2TimConversation conversation,
  ) async {
    final convType = conversation.type;
    final convID = convType == 1 ? conversation.userID : conversation.groupID;
    if (convType == null || convID == null || convID.trim().isEmpty) {
      return;
    }
    try {
      await widget.controller.clearHistoryMessage(conversation: conversation);
    } catch (_) {}
  }

  Future<void> _deleteArchivedConversation(
    V2TimConversation conversation,
  ) async {
    final confirmed = await _confirmDeleteConversation();
    if (confirmed != true) return;
    await _cleanConversationUnreadQuietly(conversation);
    await _clearConversationHistoryQuietly(conversation);
    await widget.controller.deleteConversation(
      conversationID: conversation.conversationID,
    );
    // 保留归档标记：删除只清本端记录与会话实体，会话再次活跃时仍回归档，
    // 不落回主消息列表。
    final deletedId = conversation.conversationID.trim();
    if (deletedId.isNotEmpty) {
      _archiveItems.removeWhere(
        (c) =>
            MessageConversationId.sameConversation(c.conversationID, deletedId),
      );
      _displayedIds.removeWhere(
        (id) => MessageConversationId.sameConversation(id, deletedId),
      );
    }
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_archive_deleted',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool?> _confirmDeleteConversation({int count = 1}) {
    final i18n = AppI18n.of(context);
    final isBatch = count > 1;
    return AppDialog.confirm(
      title: i18n.t(
        zhHans: isBatch ? '删除会话' : '删除此会话',
        zhHant: isBatch ? '刪除會話' : '刪除此會話',
        en: isBatch ? 'Delete conversations' : 'Delete conversation',
        ja: isBatch ? '会話を削除' : 'この会話を削除',
        ko: isBatch ? '대화 삭제' : '이 대화 삭제',
      ),
      message: i18n.t(
        zhHans: '将从列表移除该会话，并清空您在本端的聊天记录（对方不受影响）。确定继续吗？',
        zhHant: '將從列表移除該會話，並清空您在本端的聊天記錄（對方不受影響）。確定繼續嗎？',
        en: 'This removes the conversation from your list and clears chat history on your side only. Continue?',
        ja: 'リストから会話を削除し、あなた側のチャット履歴を消去します（相手には影響しません）。続行しますか？',
        ko: '목록에서 대화를 제거하고 내 기기의 채팅 기록을 삭제합니다(상대방에게는 영향 없음). 계속할까요?',
      ),
      confirmText: i18n.t(
        zhHans: '删除',
        zhHant: '刪除',
        en: 'Delete',
        ja: '削除',
        ko: '삭제',
      ),
      destructive: true,
    );
  }

  Future<void> _pinArchivedConversation(V2TimConversation conversation) async {
    await ConversationPinService.instance.togglePinned(
      conversation: conversation,
      source: 'archived_list',
    );
  }

  Future<void> _toggleArchivedConversationDisturb(
    V2TimConversation conversation,
  ) async {
    final messageService = serviceLocator<MessageService>();
    final isDisturb = conversationRecvOptMuted(conversation);
    final targetOpt = isDisturb
        ? ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE
        : ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE;
    final prevOpt = conversation.recvOpt ?? 0;
    final targetIndex = targetOpt.index;

    final groupID = conversation.groupID?.trim() ?? '';
    var userID = conversation.userID?.trim() ?? '';
    if (userID.isEmpty && groupID.isEmpty) {
      userID = MessageConversationId.normalizeComparableKey(
        conversation.conversationID,
      );
    }

    void applyLocal(int recvOpt) {
      // 072 phase-6 allowlist: this is a transient pending projection only.
      // The successful value is published from the Coordinator commit below;
      // this helper is also used to roll back an SDK failure.
      conversation.recvOpt = recvOpt;
      ChatSessionController.instance.applyRecvOptLocally(
        conversationID: conversation.conversationID,
        recvOpt: recvOpt,
        snapshot: conversation,
      );
    }

    final optimistic = ConversationPerfFlags.recvOptOptimisticUiEnabled;
    if (optimistic) {
      applyLocal(targetIndex);
    }

    final result = groupID.isNotEmpty
        ? await ImGroupReceiveOpt.setGroupReceiveMessageOpt(
            messageService: messageService,
            groupID: groupID,
            opt: targetOpt,
          )
        : userID.isEmpty
            ? null
            : await _c2cDisturbViaService(
                messageService: messageService,
                userID: userID,
                opt: targetOpt,
              );

    if (result != null && result.code == 0) {
      String resolvedGroup = '';
      if (groupID.isNotEmpty) {
        try {
          resolvedGroup =
              await GroupLocalStore.instance.resolveImGroupId(groupID);
        } catch (_) {}
      }
      if (resolvedGroup.isNotEmpty &&
          ChatIdFormat.isCustomCommunityId(resolvedGroup) &&
          conversation.groupID?.trim() != resolvedGroup) {
        conversation.groupID = resolvedGroup;
      }
      try {
        await ConversationSyncService.instance.applyConversationMuteLocally(
          conversationID: conversation.conversationID,
          recvOpt: targetIndex,
          snapshot: conversation,
        );
      } catch (_) {}
    } else if (optimistic) {
      applyLocal(prevOpt);
    }
  }

  /// IM-09 ADR §10.1: c2c 免打扰收敛到 C2cReceiveOptService,
  /// 在异步链入口处 capture() 拿到 SessionIdentity,跨账号 fence 生效.
  /// 任何 [MessageService.setC2CReceiveMessageOpt] 直调都必须收敛到本方法.
  Future<dynamic> _c2cDisturbViaService({
    required MessageService messageService,
    required String userID,
    required ReceiveMsgOptEnum opt,
  }) async {
    final captured = SessionIdentityService.instance.capture();
    final key = AccountScopedConversationKey.tryParse(
      ownerUserId: captured.ownerUserId,
      conversationType: ImConversationType.c2c,
      conversationId: userID,
    );
    if (key == null) {
      debugPrint(
        '_c2cDisturbViaService: invalid c2c key userID=$userID',
      );
      return V2TimCallback(code: -1, desc: 'invalid_c2c_key');
    }
    return await C2cReceiveOptService.setOpt(
      messageService: messageService,
      key: key,
      opt: opt,
      capturedIdentity: captured,
    );
  }

  void _showConversationPeek(V2TimConversation conversation) {
    if (_isEditing) {
      return;
    }
    final isOfficial = PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversation.userID,
    );
    showConversationPeekForItem(
      context: context,
      conversation: conversation,
      displayName: ConversationDisplayHelper.showName(
        conversation: conversation,
        friendList: _friendShipViewModel.friendList,
      ),
      actions: ConversationPeekActions(
        onOpenChat: () => widget.onTapConversation(conversation),
        isOfficialAccount: isOfficial,
        isPinned: conversation.isPinned ?? false,
        isMuted: conversationRecvOptMuted(conversation),
        isArchived: true,
        onArchive: isOfficial
            ? null
            : () => _updateArchivedStatus(conversation, archived: false),
        onTogglePin: isOfficial
            ? null
            : () async {
                await _pinArchivedConversation(conversation);
              },
        onToggleMute: isOfficial
            ? null
            : () => _toggleArchivedConversationDisturb(conversation),
        onDelete: () => _deleteArchivedConversation(conversation),
      ),
    );
  }

  void _showDesktopConversationMenu(
    V2TimConversation conversation,
    TapDownDetails details,
  ) {
    if (_isEditing || !conversationUseDesktopContextMenu(context)) {
      return;
    }
    final i18n = AppI18n.of(context);
    final isOfficial = PlatformOfficialAccountService.isPlatformOfficialAccount(
      conversation.userID,
    );
    final isPinned = conversation.isPinned ?? false;
    final items = <DesktopConversationMenuItem>[];
    if (!isOfficial) {
      items.add(
        DesktopConversationMenuItem(
          label: isPinned
              ? i18n.t(
                  zhHans: '取消置顶',
                  zhHant: '取消置頂',
                  en: 'Unpin',
                  ja: 'ピン留め解除',
                  ko: '고정 해제',
                )
              : i18n.t(
                  zhHans: '置顶',
                  zhHant: '置頂',
                  en: 'Pin',
                  ja: 'ピン留め',
                  ko: '고정',
                ),
          onSelect: () => _pinArchivedConversation(conversation),
        ),
      );
      items.add(
        DesktopConversationMenuItem(
          label: i18n.t(
            zhHans: '取消归档',
            zhHant: '取消封存',
            en: 'Unarchive',
            ja: 'アーカイブ解除',
            ko: '보관 해제',
          ),
          onSelect: () => _updateArchivedStatus(conversation, archived: false),
        ),
      );
    }
    items.add(
      DesktopConversationMenuItem(
        label: i18n.t(
          zhHans: '删除',
          zhHant: '刪除',
          en: 'Delete',
          ja: '削除',
          ko: '삭제',
        ),
        destructive: true,
        onSelect: () => _deleteArchivedConversation(conversation),
      ),
    );
    unawaited(
      showDesktopConversationContextMenu(
        context: context,
        globalPosition: details.globalPosition,
        items: items,
      ),
    );
  }

  String _conversationShowName(
    V2TimConversation conversation, {
    bool allowAliasFallback = true,
  }) {
    final groupId = conversation.groupID?.trim() ?? '';
    final localName = groupId.isEmpty
        ? null
        : GroupLocalStore.instance.readCached(groupId: groupId)?.groupName;
    return FriendDisplayName.resolveConversation(
      conversation: conversation,
      friendList: _friendShipViewModel.friendList,
      groupList: _friendShipViewModel.groupList,
      localGroupName: localName,
      allowAliasFallback: allowAliasFallback,
    );
  }

  String _conversationFaceUrl(V2TimConversation conversation) {
    return ConversationFaceUrl.resolve(
      userId: conversation.userID,
      conversationFaceUrl: conversation.faceUrl,
      isGroup: conversationMatchesScope(
        conversation,
        ConversationListScope.group,
      ),
      friendList: _friendShipViewModel.friendList,
      groupList: _friendShipViewModel.groupList,
      groupId: conversation.groupID,
    );
  }

  Widget? _conversationAvatarWidget(V2TimConversation conversation) {
    final faceUrl = _conversationFaceUrl(conversation);
    if (faceUrl != ConversationFaceUrl.defaultGroupFaceAsset) {
      return null;
    }
    return ClipOval(
      child: SvgPicture.asset(
        ConversationFaceUrl.defaultGroupFaceAsset,
        fit: BoxFit.cover,
      ),
    );
  }

  Future<void> _updateArchivedStatusForConversations(
    List<V2TimConversation> conversations, {
    required bool archived,
  }) async {
    final scopedConversations = conversations
        .where(
          (conversation) =>
              conversationMatchesScope(conversation, widget.listScope),
        )
        .toList();
    if (scopedConversations.isEmpty) {
      return;
    }
    final syncIds = scopedConversations
        .map((c) => c.conversationID.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    await ArchivedConversationSyncService.instance.setArchivedForConversations(
      scopedConversations,
      archived: archived,
    );
    if (!archived) {
      final removeIds = syncIds.toSet();
      _archiveItems.removeWhere(
        (c) => removeIds.any(
          (id) => MessageConversationId.sameConversation(c.conversationID, id),
        ),
      );
      _displayedIds.removeWhere(
        (id) =>
            removeIds.any((r) => MessageConversationId.sameConversation(id, r)),
      );
      await ChatSessionController.instance.syncMainListAfterArchiveChange(
        restoredIds: syncIds,
        reason: 'archive_page_unarchive',
      );
    } else {
      await ChatSessionController.instance.syncMainListAfterArchiveChange(
        removedIds: syncIds,
        reason: 'archive_page_archive',
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateArchivedStatus(
    V2TimConversation conversation, {
    required bool archived,
  }) async {
    await _updateArchivedStatusForConversations([
      conversation,
    ], archived: archived);
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _selectedConversationIDs.clear();
      }
    });
  }

  void _toggleSelectedConversation(String conversationID) {
    setState(() {
      if (_selectedConversationIDs.contains(conversationID)) {
        _selectedConversationIDs.remove(conversationID);
      } else {
        _selectedConversationIDs.add(conversationID);
      }
    });
  }

  List<V2TimConversation> _getSelectedConversations(
    List<V2TimConversation> archivedConversations,
  ) {
    return archivedConversations
        .where(
          (conversation) =>
              _selectedConversationIDs.contains(conversation.conversationID),
        )
        .toList();
  }

  Future<void> _cleanConversationUnread(
    V2TimConversation conversation, {
    bool updateUi = true,
  }) async {
    final hadUnread = (conversation.unreadCount ?? 0) > 0;
    await ConversationUnreadClearService.clearLocalForOpen(
      conversation: conversation,
      markViewModelReadLocally:
          widget.controller.model.markConversationReadLocally,
    );
    if (hadUnread) {
      unawaited(
        ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: conversation.conversationID,
          trigger: SdkUnreadCleanTrigger.open,
          hadUnread: true,
        ),
      );
    }
    if (updateUi && mounted) {
      setState(() {});
    }
  }

  Future<void> _cleanConversationUnreadQuietly(
    V2TimConversation conversation,
  ) async {
    try {
      await _cleanConversationUnread(conversation, updateUi: false);
    } catch (_) {}
  }

  Future<void> _markSelectedAsRead(
    List<V2TimConversation> archivedConversations,
  ) async {
    final selectedConversations = _getSelectedConversations(
      archivedConversations,
    );
    final hasManualSelection = selectedConversations.isNotEmpty;
    final mode = hasManualSelection
        ? MarkReadEditMode.selected
        : MarkReadEditMode.archivedAll;
    final selectedIds = selectedConversations
        .map((c) => c.conversationID.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final archivedIds = archivedConversationIdsForListScope(widget.listScope);
    final listScope = markReadListScopeOf(widget.listScope);
    final preview =
        await ConversationUnreadClearService.previewMarkReadForEditAction(
      mode: mode,
      listScope: listScope,
      selectedIds: selectedIds,
      archivedIds: archivedIds,
    );
    if (preview.isEmpty) {
      MarkSelectedReadLog.log('mark_selected_archive_skip_no_unread', {
        'scope': widget.listScope.name,
        'mode': mode.name,
      });
      if (mounted) {
        setState(() {
          _selectedConversationIDs.clear();
          _isEditing = false;
        });
      }
      return;
    }
    if (preview.unreadSumBefore >=
            ConversationUnreadClearService.confirmUnreadSumThreshold &&
        mounted) {
      final confirmed = await confirmMarkReadAllDialog(
        context,
        conversationCount: preview.conversationCount,
        unreadSum: preview.unreadSumBefore,
      );
      if (!confirmed) {
        return;
      }
    }
    final result = await ConversationUnreadClearService.markReadForEditAction(
      mode: mode,
      listScope: listScope,
      selectedIds: selectedIds,
      archivedIds: archivedIds,
      markViewModelReadLocally:
          widget.controller.model.markConversationReadLocally,
    );
    MarkSelectedReadLog.log('mark_selected_archive_ui_exit_edit', {
      'scope': widget.listScope.name,
      'mode': mode.name,
      'cleared': result.conversationCount,
      'sdkPath': result.sdkPath,
      'durationMs': result.durationMs,
    });
    if (mounted) {
      setState(() {
        _selectedConversationIDs.clear();
        _isEditing = false;
      });
    }
  }

  Future<void> _unarchiveSelected(
    List<V2TimConversation> archivedConversations,
  ) async {
    final selectedConversations = _getSelectedConversations(
      archivedConversations,
    );
    await _updateArchivedStatusForConversations(
      selectedConversations,
      archived: false,
    );
    if (mounted) {
      setState(() {
        _selectedConversationIDs.clear();
        _isEditing = false;
      });
    }
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_unarchive',
    );
  }

  Future<void> _deleteSelected(
    List<V2TimConversation> archivedConversations,
  ) async {
    final selectedConversations = _getSelectedConversations(
      archivedConversations,
    );
    if (selectedConversations.isEmpty) return;
    final confirmed = await _confirmDeleteConversation(
      count: selectedConversations.length,
    );
    if (confirmed != true) return;
    for (final conversation in selectedConversations) {
      await _cleanConversationUnreadQuietly(conversation);
      await _clearConversationHistoryQuietly(conversation);
      await widget.controller.deleteConversation(
        conversationID: conversation.conversationID,
      );
      final deletedId = conversation.conversationID.trim();
      if (deletedId.isNotEmpty) {
        _archiveItems.removeWhere(
          (c) => MessageConversationId.sameConversation(
            c.conversationID,
            deletedId,
          ),
        );
        _displayedIds.removeWhere(
          (id) => MessageConversationId.sameConversation(id, deletedId),
        );
      }
    }
    // 保留归档标记：删除只清本端记录与会话实体，会话再次活跃时仍回归档。
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'conversation_archive_delete_selected',
    );
    if (mounted) {
      setState(() {
        _selectedConversationIDs.clear();
        _isEditing = false;
      });
    }
  }

  Future<void> _showArchivedMoreActionsSheet(
    BuildContext context,
    V2TimConversation conversation,
  ) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(context).pop();
                await _pinArchivedConversation(conversation);
              },
              child: Text(
                conversation.isPinned == true
                    ? AppI18n.of(context).t(
                        zhHans: '取消置顶',
                        zhHant: '取消置頂',
                        en: 'Unpin',
                        ja: 'ピン留め解除',
                        ko: '고정 해제',
                      )
                    : AppI18n.of(context).t(
                        zhHans: '置顶',
                        zhHant: '置頂',
                        en: 'Pin',
                        ja: 'ピン留め',
                        ko: '고정',
                      ),
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.of(context).pop();
                await _updateArchivedStatus(conversation, archived: false);
              },
              child: Text(
                AppI18n.of(context).t(
                  zhHans: '取消归档',
                  zhHant: '取消封存',
                  en: 'Unarchive',
                  ja: 'アーカイブ解除',
                  ko: '보관 해제',
                ),
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              AppI18n.of(context).t(
                zhHans: '取消',
                zhHant: '取消',
                en: 'Cancel',
                ja: 'キャンセル',
                ko: '취소',
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final page = Scaffold(
      backgroundColor: theme.weakBackgroundColor ?? Colors.white,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.appbarBgColor ?? Colors.white,
        foregroundColor: theme.primaryColor ?? const Color(0xFF1E90FF),
        iconTheme: IconThemeData(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
        titleSpacing: 4,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: AppBackButton(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
          onPressed: () {
            if (widget.shellEmbedded && widget.onClose != null) {
              widget.onClose!();
              return;
            }
            Navigator.of(context).maybePop();
          },
        ),
        title: Text(
          AppI18n.of(context).t(
            zhHans: '已归档',
            zhHant: '已封存',
            en: 'Archived',
            ja: 'アーカイブ済み',
            ko: '보관됨',
          ),
          style: TextStyle(color: theme.appbarTextColor ?? Colors.black),
        ),
        actions: _isEditing
            ? [
                // 编辑态只允许手动勾选，不再提供「全选」。
                TextButton(
                  onPressed: _toggleEditMode,
                  child: Text(
                    AppI18n.of(context).t(
                      zhHans: '完成',
                      zhHant: '完成',
                      en: 'Done',
                      ja: '完了',
                      ko: '완료',
                    ),
                    style: TextStyle(
                      color: theme.primaryColor ?? const Color(0xFF1E90FF),
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  onPressed: _toggleEditMode,
                  icon: SvgPicture.string(
                    archivedEditIconSvg,
                    width: 24,
                    height: 24,
                  ),
                ),
              ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller.model,
          _archivedIDsNotifier,
          _friendShipViewModel,
        ]),
        builder: (context, child) {
          final archivedConversations = _filterVisible(_archiveItems);
          if (_initialLoading && archivedConversations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (archivedConversations.isEmpty && _archivePageError) {
            return Center(
                child: TextButton(
                    onPressed: _reloadArchiveFirstPage,
                    child: Text(AppI18n.of(context).t(
                        zhHans: '重试',
                        zhHant: '重試',
                        en: 'Retry',
                        ja: '再試行',
                        ko: '다시 시도'))));
          }
          if (archivedConversations.isEmpty &&
              (_coldScanPending || _loadingMore || _hasMore)) {
            if (!_coldScanPending && !_loadingMore) _scheduleArchivePageLoad();
            return const Center(child: CircularProgressIndicator());
          }
          if (archivedConversations.isEmpty) {
            return Center(
              child: Text(
                widget.listScope == ConversationListScope.group
                    ? AppI18n.of(context).t(
                        zhHans: '暂无归档群聊',
                        zhHant: '暫無封存群聊',
                        en: 'No archived groups',
                        ja: 'アーカイブしたグループはありません',
                        ko: '보관된 그룹 없음',
                      )
                    : AppI18n.of(context).t(
                        zhHans: '暂无归档会话',
                        zhHant: '暫無封存會話',
                        en: 'No archived chats',
                        ja: 'アーカイブした会話はありません',
                        ko: '보관된 대화 없음',
                      ),
                style: TextStyle(color: theme.weakTextColor, fontSize: 14),
              ),
            );
          }
          final showFooter = _loadingMore;
          return ListView.builder(
            controller: _archiveScrollController,
            itemCount: archivedConversations.length + (showFooter ? 1 : 0),
            itemBuilder: (context, index) {
              if (showFooter && index >= archivedConversations.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.primaryColor ?? const Color(0xFF1E90FF),
                      ),
                    ),
                  ),
                );
              }
              final conversation = archivedConversations[index];
              final isPinned = conversation.isPinned ?? false;
              final previewLastMessage = _archivePreviewFor(conversation);
              final isSelected = _selectedConversationIDs.contains(
                conversation.conversationID,
              );
              final item = Material(
                color: isPinned
                    ? theme.conversationItemPinedBgColor
                    : theme.conversationItemBgColor,
                child: Row(
                  children: [
                    if (_isEditing)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: GestureDetector(
                          onTap: () => _toggleSelectedConversation(
                            conversation.conversationID,
                          ),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? (theme.primaryColor ??
                                      const Color(0xFF1E90FF))
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? (theme.primaryColor ??
                                        const Color(0xFF1E90FF))
                                    : (theme.weakTextColor ??
                                        const Color(0xFFBDBDBD)),
                                width: 1.8,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    Expanded(
                      child: AppListPressable(
                        onTap: () {
                          if (_isEditing) {
                            _toggleSelectedConversation(
                              conversation.conversationID,
                            );
                          } else {
                            widget.onTapConversation(conversation);
                          }
                        },
                        onLongPress: () => _showConversationPeek(conversation),
                        onSecondaryTapDown: (details) =>
                            _showDesktopConversationMenu(conversation, details),
                        child: TIMUIKitConversationItem(
                          isCurrent: false,
                          conversationID: conversation.conversationID,
                          lastMessageAbstractBuilder:
                              widget.lastMessageAbstractBuilder,
                          faceUrl: _conversationFaceUrl(conversation),
                          avatarWidget: _conversationAvatarWidget(conversation),
                          nickName: _conversationShowName(conversation),
                          nickNameWidget:
                              widget.listScope == ConversationListScope.group
                                  ? buildGroupConversationListNickName(
                                      userId: conversation.userID,
                                      name: _conversationShowName(conversation),
                                      fallbackTitleColor:
                                          theme.conversationItemTitleTextColor,
                                      groupType: conversation.groupType,
                                      groupId: conversation.groupID,
                                    )
                                  : buildConversationListNickName(
                                      userId: conversation.userID,
                                      name: _conversationShowName(conversation),
                                      fallbackTitleColor:
                                          theme.conversationItemTitleTextColor,
                                      groupType: conversation.groupType,
                                    ),
                          avatarBorderRadius: BorderRadius.circular(999),
                          avatarSize: conversationFeedAvatarSize(context),
                          titleFontSize: conversationFeedTitleFontSize(context),
                          subtitleFontSize:
                              conversationFeedSubtitleFontSize(context),
                          timestampFontSize:
                              conversationFeedTimestampFontSize(context),
                          isDisturb: conversationShouldShowMuteIcon(
                            conversation,
                          ),
                          lastMsg: previewLastMessage,
                          lastActiveTimestamp: previewLastMessage?.timestamp ??
                              ConversationLocalStore.displayTimestampSec(
                                conversation,
                              ),
                          isPined: isPinned,
                          groupAtInfoList: conversation.groupAtInfoList ?? [],
                          unreadCount: conversation.unreadCount ?? 0,
                          draftText: conversation.draftText,
                          draftTimestamp: conversation.draftTimestamp,
                          customEmojiStickerList:
                              _conversationPreviewEmojiList(context),
                          onlineStatus: null,
                          convType: conversation.type,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              if (_isEditing ||
                  PlatformUtils().isWeb ||
                  conversationUseDesktopContextMenu(context)) {
                return item;
              }
              return Slidable(
                groupTag: 'archived-conversation-list',
                child: item,
                endActionPane: ActionPane(
                  extentRatio: 0.5,
                  motion: const DrawerMotion(),
                  children: [
                    ConversationItemSlidePanel(
                      onPressed: (context) {
                        _showArchivedMoreActionsSheet(context, conversation);
                      },
                      flex: 1,
                      backgroundColor: const Color(0xFFF5A623),
                      foregroundColor: theme.conversationItemSliderTextColor,
                      label: AppI18n.of(context).t(
                        zhHans: '更多',
                        zhHant: '更多',
                        en: 'More',
                        ja: 'その他',
                        ko: '더보기',
                      ),
                      spacing: 0,
                      autoClose: true,
                      padding: EdgeInsets.zero,
                    ),
                    ConversationItemSlidePanel(
                      onPressed: (context) async {
                        await _updateArchivedStatus(
                          conversation,
                          archived: false,
                        );
                      },
                      flex: 1,
                      backgroundColor:
                          theme.primaryColor ?? const Color(0xFF1E90FF),
                      foregroundColor: theme.conversationItemSliderTextColor,
                      label: AppI18n.of(context).t(
                        zhHans: '取消归档',
                        zhHant: '取消封存',
                        en: 'Unarchive',
                        ja: 'アーカイブ解除',
                        ko: '보관 해제',
                      ),
                      spacing: 0,
                      autoClose: true,
                      padding: EdgeInsets.zero,
                    ),
                    ConversationItemSlidePanel(
                      onPressed: (context) async {
                        Slidable.of(context)?.close();
                        await _deleteArchivedConversation(conversation);
                      },
                      flex: 1,
                      backgroundColor: const Color(0xFFEF3B36),
                      foregroundColor: theme.conversationItemSliderTextColor,
                      label: AppI18n.of(context).t(
                        zhHans: '删除',
                        zhHant: '刪除',
                        en: 'Delete',
                        ja: '削除',
                        ko: '삭제',
                      ),
                      spacing: 0,
                      autoClose: true,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _isEditing
          ? SafeArea(
              top: false,
              child: Container(
                height: kBottomNavigationBarHeight,
                decoration: BoxDecoration(
                  color: _conversationItemBackground(theme, pinned: false),
                  border: Border(
                    top: BorderSide(
                      color: theme.weakDividerColor ?? hexToColor("E5E6E9"),
                      width: 0.6,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        // 无勾选 = 全部已读；有勾选 = 标记已读（只清选中）。始终可点。
                        onPressed: () => _markSelectedAsRead(
                          _getArchivedConversations(
                            _archivedIDsNotifier.value,
                          ),
                        ),
                        child: Text(
                          markReadActionLabel(
                            context,
                            hasSelection: _selectedConversationIDs.isNotEmpty,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _selectedConversationIDs.isEmpty
                            ? null
                            : () => _unarchiveSelected(
                                  _getArchivedConversations(
                                    _archivedIDsNotifier.value,
                                  ),
                                ),
                        child: Text(
                          AppI18n.of(context).t(
                            zhHans: '取消归档',
                            zhHant: '取消封存',
                            en: 'Unarchive',
                            ja: 'アーカイブ解除',
                            ko: '보관 해제',
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _selectedConversationIDs.isEmpty
                            ? null
                            : () => _deleteSelected(
                                  _getArchivedConversations(
                                    _archivedIDsNotifier.value,
                                  ),
                                ),
                        child: Text(
                          AppI18n.of(context).t(
                            zhHans: '删除',
                            zhHant: '刪除',
                            en: 'Delete',
                            ja: '削除',
                            ko: '삭제',
                          ),
                          style: const TextStyle(color: Color(0xFFEF3B36)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
    if (widget.shellEmbedded) {
      return page;
    }
    return PageIosBackGestureScope(child: page);
  }
}
