import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/tim_uikit_conversation_last_msg.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_user_filter.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/tim_uikit_conversation_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/radio_button.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class RecentForwardList extends StatefulWidget {
  final bool isMultiSelect;
  final Function(List<V2TimConversation> conversationList)? onChanged;
  final String keyword;
  final String sectionTitle;
  final bool showSectionHeader;
  final LastMessageBuilder? lastMessageBuilder;
  final LastMessageAbstractBuilder? lastMessageAbstractBuilder;

  const RecentForwardList({
    Key? key,
    this.isMultiSelect = true,
    this.onChanged,
    this.keyword = "",
    this.sectionTitle = "",
    this.showSectionHeader = true,
    this.lastMessageBuilder,
    this.lastMessageAbstractBuilder,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _RecentForwardListState();
}

class _RecentForwardListState extends TIMUIKitState<RecentForwardList> {
  final TUIConversationViewModel _conversationViewModel =
      serviceLocator<TUIConversationViewModel>();
  final List<V2TimConversation> _selectedConversation = [];

  List<V2TimConversation?> _recentConversations() {
    TUIChatGlobalModel.ensureAppExtensionsRegistered();
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final appItems = globalModel.appForwardRecentConversations?.call() ??
        const <V2TimConversation>[];
    final sdkItems = _conversationViewModel.conversationList;
    final merged = <V2TimConversation?>[];
    final seen = <String>{};
    for (final item in <V2TimConversation?>[...appItems, ...sdkItems]) {
      if (item == null) continue;
      final id = item.conversationID.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      merged.add(item);
    }
    return merged;
  }

  List<ISuspensionBeanImpl<V2TimConversation?>> _buildMemberList(
    List<V2TimConversation?> conversationList,
  ) {
    final keyword = widget.keyword.trim().toLowerCase();
    final List<ISuspensionBeanImpl<V2TimConversation?>> showList = [];
    for (final item in conversationList) {
      if (item == null) {
        continue;
      }
      if (shouldHideConversationFromPickers(item)) {
        continue;
      }
      final showName = (item.showName ?? "").trim();
      if (keyword.isNotEmpty && !showName.toLowerCase().contains(keyword)) {
        continue;
      }
      showList.add(ISuspensionBeanImpl(memberInfo: item, tagIndex: "#"));
    }
    return showList;
  }

  Widget _buildSectionHeader(String title, TUITheme theme) {
    final sectionBackgroundColor = theme.selectPanelBgColor ??
        theme.weakDividerColor ??
        const Color(0xFFF5F5F5);
    return Container(
      height: DirectoryListStyle.sectionHeight(context),
      width: double.infinity,
      padding: const EdgeInsets.only(left: 16.0),
      color: sectionBackgroundColor,
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        softWrap: true,
        style: TextStyle(
          fontSize: 12,
          color: theme.weakTextColor,
        ),
      ),
    );
  }

  Widget _buildConversationItem(V2TimConversation conversation, TUITheme theme) {
    void handleTap() {
      if (widget.isMultiSelect) {
        final isSelected = _selectedConversation
            .any((item) => item.conversationID == conversation.conversationID);
        if (isSelected) {
          _selectedConversation.removeWhere(
              (item) => item.conversationID == conversation.conversationID);
        } else {
          _selectedConversation.add(conversation);
        }
        if (widget.onChanged != null) {
          widget.onChanged!(_selectedConversation);
        }
        setState(() {});
      } else if (widget.onChanged != null) {
        widget.onChanged!([conversation]);
      }
    }

    final message = conversation.lastMessage;
    final customPreview =
        widget.lastMessageAbstractBuilder == null && message != null
            ? widget.lastMessageBuilder?.call(message, const [])
            : null;
    final preview = customPreview ??
        (message == null
            ? null
            : TIMUIKitLastMsg(
                conversationID: conversation.conversationID,
                fontSize: DirectoryListStyle.subtitleSize,
                groupAtInfoList: const [],
                lastMsg: message,
                isDisturb: false,
                unreadCount: 0,
                context: context,
                draftText: '',
                lastMessageAbstractBuilder: widget.lastMessageAbstractBuilder,
              ));
    return Material(
      color: theme.conversationItemBgColor ?? theme.wideBackgroundColor,
      child: InkWell(
        onTap: handleTap,
        child: DirectoryListRow(
          leading: !widget.isMultiSelect
              ? null
              : CheckBoxButton(
                  isChecked: _selectedConversation.any((item) =>
                      item.conversationID == conversation.conversationID),
                  onChanged: (_) => handleTap(),
                ),
          avatar: Avatar(
              faceUrl: conversation.faceUrl ?? '',
              showName: conversation.showName ?? '',
              type: conversation.type == 2 ? 2 : 1,
              borderRadius: BorderRadius.circular(999),
              isShowBigWhenClick: false),
          title: Text(conversation.showName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.darkTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.25)),
          subtitle: preview == null
              ? null
              : DefaultTextStyle.merge(
                  style: TextStyle(
                      color: theme.weakTextColor, fontSize: 13, height: 1.25),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: preview,
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    if (!widget.isMultiSelect) {
      _selectedConversation.clear();
    }
    TUIChatGlobalModel.ensureAppExtensionsRegistered();
    final appListenable = serviceLocator<TUIChatGlobalModel>()
        .appForwardRecentConversationsListenable;
    final listenables = <Listenable>[_conversationViewModel];
    if (appListenable != null &&
        !identical(appListenable, _conversationViewModel)) {
      listenables.add(appListenable);
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _conversationViewModel),
      ],
      builder: (context, w) => AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (context, child) {
          final showList = _buildMemberList(_recentConversations());
          final listBackgroundColor = theme.conversationItemBgColor ??
              theme.weakBackgroundColor ??
              Colors.white;

          return Container(
            color: listBackgroundColor,
            child: Column(
              children: [
                if (widget.showSectionHeader)
                  _buildSectionHeader(
                    widget.sectionTitle.isNotEmpty
                        ? widget.sectionTitle
                        : TIM_t("最近"),
                    theme,
                  ),
                Expanded(
                  child: AZListViewContainer(
                    memberList: showList,
                    isShowIndexBar: false,
                    susItemBuilder: (context, index) => Container(),
                    itemBuilder: (context, index) {
                      final conversation = showList[index].memberInfo;
                      if (conversation != null) {
                        return _buildConversationItem(conversation, theme);
                      }
                      return Container();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
