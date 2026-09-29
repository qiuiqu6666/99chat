// ignore_for_file: must_be_immutable, unused_import

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/search_display_resolvers.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_folder.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_result_entrance.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_search_msg_detail.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_showAll.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';

V2TimFriendInfo? _friendHintFor(
  String conversationId,
  List<V2TimFriendInfoResult> friends,
) {
  final userId = conversationId.toLowerCase().startsWith('c2c_')
      ? conversationId.substring(4).trim()
      : '';
  if (userId.isEmpty) {
    return null;
  }
  for (final item in friends) {
    final friend = item.friendInfo;
    if (friend != null && friend.userID.trim() == userId) {
      return friend;
    }
  }
  return null;
}

V2TimGroupInfo? _groupHintFor(
  String conversationId,
  List<V2TimGroupInfo> groups,
) {
  if (!isGroupConversationId(conversationId)) {
    return null;
  }
  final groupId = groupIdFromConversationId(conversationId) ??
      searchStripConversationPrefix(conversationId);
  for (final group in groups) {
    if (searchGroupIdsEquivalent(group.groupID, groupId)) {
      return group;
    }
  }
  return null;
}

Widget buildSearchHistoryConversationTile({
  Key? key,
  required V2TimMessageSearchResultItem item,
  required String keyword,
  required Map<String, V2TimConversation> conversationById,
  required List<V2TimFriendInfoResult> friends,
  required List<V2TimGroupInfo> groups,
  required Function(V2TimConversation, String) onEnterConversation,
}) {
  final conversationId = item.conversationID?.trim() ?? '';
  if (conversationId.isEmpty) {
    return const SizedBox.shrink();
  }
  final display = resolveSearchConversationDisplay(
    conversationId: conversationId,
    friendHint: _friendHintFor(conversationId, friends),
    groupHint: _groupHintFor(conversationId, groups),
  );
  final conversation = overlaySearchConversationDisplay(
    source: resolveSearchConversationById(
      conversationId: conversationId,
      conversationById: conversationById,
    ),
    display: display,
  );
  final option1 = item.messageCount;
  return TIMUIKitSearchItem(
    key: key,
    onClick: () async {
      onEnterConversation(conversation, keyword);
    },
    faceUrl: display.faceUrl,
    showName: display.showName,
    avatarType: display.isGroup ? 2 : 1,
    lineOne: display.showName,
    lineTwo: TIM_t_para("{{option1}}条相关聊天记录", "$option1条相关聊天记录")(
        option1: option1),
  );
}

class TIMUIKitSearchMsg extends StatefulWidget {
  List<V2TimMessageSearchResultItem?> msgList;
  int totalMsgCount;
  String keyword;
  final int generation;
  final Function(V2TimConversation, V2TimMessage?) onTapConversation;
  final Function(V2TimConversation, String) onEnterConversation;
  final VoidCallback? onShowAll;
  final int defaultShowLines;

  TIMUIKitSearchMsg(
      {required this.msgList,
      required this.keyword,
      required this.totalMsgCount,
      required this.generation,
      Key? key,
      required this.onTapConversation,
      required this.onEnterConversation,
      this.onShowAll,
      this.defaultShowLines = 5})
      : super(key: key);

  @override
  State<TIMUIKitSearchMsg> createState() => _TIMUIKitSearchMsgState();
}

class _TIMUIKitSearchMsgState extends TIMUIKitState<TIMUIKitSearchMsg> {
  final TUISearchViewModel _model = serviceLocator<TUISearchViewModel>();
  final Set<String> _seenKeys = <String>{};
  int _seenGeneration = -1;

  Set<String> _newlyVisible(Iterable<String> visibleKeys) {
    if (widget.generation != _seenGeneration) {
      _seenKeys.clear();
      _seenGeneration = widget.generation;
    }
    final newly = <String>{};
    for (final key in visibleKeys) {
      if (_seenKeys.add(key)) {
        newly.add(key);
      }
    }
    return newly;
  }

  Widget _renderShowALl() {
    final showMore = widget.onShowAll != null &&
        (_model.hasMoreGlobalMessageResults ||
            widget.msgList.length > widget.defaultShowLines);
    if (!showMore) {
      return Container();
    }
    return TIMUIKitSearchShowALl(
      textShow: TIM_t("更多聊天记录"),
      onClick: widget.onShowAll,
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final searchModel = Provider.of<TUISearchViewModel>(
      context,
      listen: false,
    );
    final conversationList = searchModel.conversationList;
    final conversationById = <String, V2TimConversation>{};
    for (final conversation in conversationList) {
      final id = conversation?.conversationID?.trim() ?? '';
      if (id.isNotEmpty && conversation != null) {
        conversationById[id] = conversation;
      }
    }
    final friends =
        searchModel.friendList ?? const <V2TimFriendInfoResult>[];
    final groups = searchModel.groupList ?? const <V2TimGroupInfo>[];
    final previewList = takeSearchHomePreview(
      widget.msgList,
      limit: widget.defaultShowLines,
    );
    final visibleKeys = previewList
        .whereType<V2TimMessageSearchResultItem>()
        .map((item) => item.conversationID?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final newlyVisible = _newlyVisible(visibleKeys);

    if (widget.msgList.isNotEmpty) {
      return TIMUIKitSearchFolder(
          folderName: TIM_t("聊天记录"),
          children: [
            ...previewList.map((conv) {
              if (conv == null) {
                return const SizedBox.shrink();
              }
              final conversationId = conv.conversationID?.trim() ?? '';
              return SearchResultEntrance(
                key: ValueKey(conversationId),
                generation: widget.generation,
                animate: newlyVisible.contains(conversationId),
                child: buildSearchHistoryConversationTile(
                  item: conv,
                  keyword: widget.keyword,
                  conversationById: conversationById,
                  friends: friends,
                  groups: groups,
                  onEnterConversation: widget.onEnterConversation,
                ),
              );
            }).toList(),
            _renderShowALl()
          ]);
    } else {
      return Container();
    }
  }
}
