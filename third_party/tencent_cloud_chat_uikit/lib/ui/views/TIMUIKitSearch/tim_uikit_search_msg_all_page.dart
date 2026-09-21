import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_result_entrance.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/search_result_cursor.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_search_msg.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';

/// 全局搜索「聊天记录」独立页：滚动加载更多，不在首页原地展开。
class TIMUIKitSearchMsgAllPage extends StatefulWidget {
  final String keyword;
  final Function(V2TimConversation, String) onEnterConversation;

  const TIMUIKitSearchMsgAllPage({
    Key? key,
    required this.keyword,
    required this.onEnterConversation,
  }) : super(key: key);

  @override
  State<TIMUIKitSearchMsgAllPage> createState() =>
      _TIMUIKitSearchMsgAllPageState();
}

class _TIMUIKitSearchMsgAllPageState
    extends TIMUIKitState<TIMUIKitSearchMsgAllPage> {
  static const double _itemExtent = 64;
  static const double _cacheExtent = 400;

  final TUISearchViewModel _model = serviceLocator<TUISearchViewModel>();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _seenKeys = <String>{};
  int _seenGeneration = -1;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModel);
    _scrollController.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeLoadMore();
      }
    });
  }

  @override
  void dispose() {
    _model.removeListener(_onModel);
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _onModel() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeLoadMore();
      }
    });
  }

  List<V2TimMessageSearchResultItem> _validItems() {
    final list = _model.msgList ?? const <V2TimMessageSearchResultItem>[];
    return list
        .whereType<V2TimMessageSearchResultItem>()
        .where((item) => (item.conversationID?.trim() ?? '').isNotEmpty)
        .toList(growable: false);
  }

  Map<String, V2TimConversation> _conversationById() {
    final map = <String, V2TimConversation>{};
    for (final conversation in _model.conversationList) {
      final id = conversation?.conversationID?.trim() ?? '';
      if (id.isNotEmpty && conversation != null) {
        map[id] = conversation;
      }
    }
    return map;
  }

  Set<String> _newlyVisible(Iterable<String> visibleKeys) {
    final generation = _model.globalSearchGeneration;
    if (generation != _seenGeneration) {
      _seenKeys.clear();
      _seenGeneration = generation;
      _seeded = false;
    }
    if (!_seeded) {
      _seenKeys.addAll(visibleKeys);
      _seeded = true;
      return <String>{};
    }
    final newly = <String>{};
    for (final key in visibleKeys) {
      if (_seenKeys.add(key)) {
        newly.add(key);
      }
    }
    return newly;
  }

  void _maybeLoadMore() {
    if (widget.keyword.trim().isEmpty) {
      return;
    }
    if (!_model.hasMoreGlobalMessageResults) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!shouldLoadMoreByScroll(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      itemExtent: _itemExtent,
    )) {
      return;
    }
    _model.loadMoreGlobalMessageSearch(widget.keyword);
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;
    final bg = theme.conversationItemBgColor ??
        theme.wideBackgroundColor ??
        Colors.white;
    final items = _validItems();
    final conversationById = _conversationById();
    final friends = _model.friendList ?? const <V2TimFriendInfoResult>[];
    final groups = _model.groupList ?? const <V2TimGroupInfo>[];
    final visibleKeys = items
        .map((item) => item.conversationID?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final newlyVisible = _newlyVisible(visibleKeys);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.chatHeaderBgColor ?? bg,
        leading: TIMUIKitBackButton(
          color: theme.appbarTextColor ?? theme.darkTextColor,
        ),
        title: Text(
          TIM_t("聊天记录"),
          style: TextStyle(
            color: theme.appbarTextColor ?? theme.darkTextColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(
          color: theme.appbarTextColor ?? theme.darkTextColor,
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                TIM_t("无搜索结果"),
                style: TextStyle(
                    color: theme.weakTextColor ?? hexToColor("999999")),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemExtent: _itemExtent,
              cacheExtent: _cacheExtent,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final conversationId = item.conversationID?.trim() ?? '';
                return SearchResultEntrance(
                  key: ValueKey(conversationId),
                  generation: _model.globalSearchGeneration,
                  animate: newlyVisible.contains(conversationId),
                  child: buildSearchHistoryConversationTile(
                    item: item,
                    keyword: widget.keyword,
                    conversationById: conversationById,
                    friends: friends,
                    groups: groups,
                    onEnterConversation: widget.onEnterConversation,
                  ),
                );
              },
            ),
    );
  }
}
