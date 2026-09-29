import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_wide_modal_operation_key.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_style_entry_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/recent_conversation_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/ui/components/app_search_bar.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/forward_pick_pages.dart';

/// 分享内容时选择的会话目标（单聊或群聊）。
class ConversationShareTarget {
  final String userID;
  final String groupID;

  const ConversationShareTarget({
    this.userID = '',
    this.groupID = '',
  });

  factory ConversationShareTarget.fromConversation(
      V2TimConversation conversation) {
    final isC2C = conversation.type == 1;
    return ConversationShareTarget(
      userID: isC2C ? (conversation.userID ?? '') : '',
      groupID: isC2C ? '' : (conversation.groupID ?? ''),
    );
  }
}

/// 选择朋友 / 群聊 / 最近会话，用于分享文本。
class ConversationSharePickerPage extends StatefulWidget {
  final TUITheme theme;
  final bool embedded;
  final bool hideAppBar;
  final ValueChanged<ConversationShareTarget>? onPicked;
  final bool Function(V2TimGroupInfo?)? groupCollector;

  const ConversationSharePickerPage({
    super.key,
    required this.theme,
    this.embedded = false,
    this.hideAppBar = false,
    this.onPicked,
    this.groupCollector,
  });

  static Future<ConversationShareTarget?> open(
    BuildContext context, {
    required TUITheme theme,
    bool Function(V2TimGroupInfo?)? groupCollector,
  }) async {
    Widget page({
      required bool hideAppBar,
      ValueChanged<ConversationShareTarget>? onPicked,
    }) {
      return ConversationSharePickerPage(
        theme: theme,
        hideAppBar: hideAppBar,
        onPicked: onPicked,
        groupCollector: groupCollector,
      );
    }

    if (!DesktopModalLayout.isDesktop(context)) {
      return Navigator.of(context).push<ConversationShareTarget>(
        AppFullscreenDialogRoute(
          builder: (_) => page(hideAppBar: false),
        ),
      );
    }

    if (TUIKitWidePopup.isShow) {
      return Navigator.of(context).push<ConversationShareTarget>(
        MaterialPageRoute(
          builder: (_) => page(hideAppBar: false),
        ),
      );
    }

    ConversationShareTarget? picked;
    final size = DesktopModalLayout.large(context);
    final i18n = AppI18n.of(context);
    await TUIKitWidePopup.showPopupWindow(
      operationKey: TUIKitWideModalOperationKey.custom,
      context: context,
      width: size.width,
      height: size.height,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      title: i18n.t(
        zhHans: '选择会话',
        zhHant: '選擇會話',
        en: 'Select Chat',
        ja: '会話を選択',
        ko: '대화 선택',
      ),
      child: (closeFunc) => Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => page(
              hideAppBar: true,
              onPicked: (target) {
                picked = target;
                closeFunc();
              },
            ),
          );
        },
      ),
    );
    return picked;
  }

  @override
  State<ConversationSharePickerPage> createState() =>
      _ConversationSharePickerPageState();
}

class _ConversationSharePickerPageState
    extends State<ConversationSharePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _inPopup {
    return TUIKitWidePopup.isShow ||
        TUIKitWidePopupScope.maybeOf(context) != null;
  }

  void _complete(ConversationShareTarget target) {
    final onPicked = widget.onPicked;
    if (onPicked != null) {
      onPicked(target);
      return;
    }
    Navigator.pop(context, target);
  }

  Route<ConversationShareTarget> _subpageRoute({
    required WidgetBuilder builder,
  }) {
    if (_inPopup) {
      return MaterialPageRoute<ConversationShareTarget>(builder: builder);
    }
    return AppMaterialPageRoute<ConversationShareTarget>(builder: builder);
  }

  Future<void> _openFriendPicker() async {
    final target = await Navigator.push<ConversationShareTarget>(
      context,
      _subpageRoute(
        builder: (context) => ForwardSelectFriendPage(
          onTapItem: (item) async {
            final conversationID = 'c2c_${item.userID}';
            final res = await TIMUIKitCore.getSDKInstance()
                .getConversationManager()
                .getConversation(conversationID: conversationID);
            final conversation = res.data ??
                V2TimConversation(
                  conversationID: conversationID,
                  type: 1,
                  userID: item.userID,
                  showName: item.userProfile?.nickName ?? item.userID,
                  faceUrl: item.userProfile?.faceUrl,
                );
            if (!context.mounted) return;
            Navigator.pop(
              context,
              ConversationShareTarget.fromConversation(conversation),
            );
          },
        ),
      ),
    );
    if (!mounted || target == null) return;
    _complete(target);
  }

  Future<void> _openGroupPicker() async {
    final target = await Navigator.push<ConversationShareTarget>(
      context,
      _subpageRoute(
        builder: (context) => ForwardSelectGroupPage(
          onTapItem: (groupInfo, conversation) {
            Navigator.pop(
              context,
              ConversationShareTarget.fromConversation(conversation),
            );
          },
          groupCollector: widget.groupCollector,
        ),
      ),
    );
    if (!mounted || target == null) return;
    _complete(target);
  }

  Widget _buildSearchBar(TUITheme theme) {
    return buildAppSearchBarInset(
      minHeight: 44,
      fontSize: 15,
      context: context,
      controller: _searchController,
      onChanged: (value) => setState(() => _keyword = value.trim()),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final i18n = AppI18n.of(context);
    final backgroundColor =
        theme.weakBackgroundColor ?? theme.wideBackgroundColor ?? Colors.white;
    final appBarColor = theme.appbarBgColor ?? backgroundColor;
    final titleColor = theme.appbarTextColor ?? theme.darkTextColor;
    final hideScaffoldAppBar = widget.embedded ||
        widget.hideAppBar ||
        (TUIKitWidePopupScope.hidesInnerAppBar(context) &&
            (ModalRoute.of(context)?.isFirst ?? true));
    final body = Column(
      children: [
        _buildSearchBar(theme),
        if (!widget.embedded) ...[
          ContactStyleEntryItem(
            icon: contactStyleEntryIcon(
              context,
              theme,
              entryId: 'friend',
            ),
            title: i18n.t(
              zhHans: '选择朋友',
              zhHant: '選擇朋友',
              en: 'Select Friend',
              ja: '友達を選択',
              ko: '친구 선택',
            ),
            onTap: _openFriendPicker,
          ),
          ContactStyleEntryItem(
            icon: contactStyleEntryIcon(
              context,
              theme,
              entryId: 'group',
            ),
            title: i18n.t(
              zhHans: '选择群聊',
              zhHant: '選擇群聊',
              en: 'Select Group',
              ja: 'グループを選択',
              ko: '그룹 선택',
            ),
            onTap: _openGroupPicker,
            showDivider: false,
          ),
        ],
        Expanded(
          child: RecentForwardList(
            isMultiSelect: false,
            keyword: _keyword,
            sectionTitle: i18n.t(
              zhHans: '最近',
              zhHant: '最近',
              en: 'Recent',
              ja: '最近',
              ko: '최근',
            ),
            showSectionHeader: true,
            onChanged: (conversationList) {
              if (conversationList.isNotEmpty) {
                _complete(
                  ConversationShareTarget.fromConversation(
                    conversationList.first,
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
    if (hideScaffoldAppBar) {
      return Material(
        color: backgroundColor,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: appBarColor,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, color: titleColor),
        ),
        title: Text(
          i18n.t(
            zhHans: '选择会话',
            zhHant: '選擇會話',
            en: 'Select Chat',
            ja: '会話を選択',
            ko: '대화 선택',
          ),
          style: TextStyle(
            color: titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: body,
    );
  }
}
