// ignore_for_file: must_be_immutable, avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimGroupListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_class.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/first_unread_jump.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/frame.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/tim_uikit_local_image_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/at_member_panel.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_multi_select_panel.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_background_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_pipeline_clock.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_send_file.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_background_registry.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';
import 'TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue.dart';
import 'TIMUIKItMessageList/TIMUIKitTongue/unread_tongue_policy.dart';
import 'TIMUIKItMessageList/tim_uikit_chat_history_message_list_config.dart';
import 'TIMUIKItMessageList/tim_uikit_history_message_list_container.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_message_input_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_send_fly_overlay.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_list_stable_keys.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_setting_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/ime_insets_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';

class TIMUIKitChat extends StatefulWidget {
  /// The chat controller you tend to used.
  /// You have to provide this before using it since tencent_cloud_chat_uikit 0.1.4.
  final TIMUIKitChatController? controller;

  /// [Update] It is suggested to provide the `V2TimConversation` once directly, since tencent_cloud_chat_uikit 1.5.0.
  /// `conversationID` / `conversationType` / `groupAtInfoList` / `conversationShowName` are not necessary to be provided, unless you want to cover these fields manually.
  final V2TimConversation conversation;

  /// The ID of the Group that the topic belongs to, only need for topic.
  final String? groupID;

  /// Conversation id, use for load history message list.
  /// This field is not necessary to be provided, when `conversation` is provided, unless you want to cover this field manually.
  final String? conversationID;

  /// Conversation type.
  /// This field is not necessary to be provided, when `conversation` is provided, unless you want to cover this field manually.
  final ConvType? conversationType;

  /// use for customize avatar
  final Widget Function(BuildContext context, V2TimMessage message)?
      userAvatarBuilder;

  /// Use for show conversation name.
  /// This field is not necessary to be provided, when `conversation` is provided, unless you want to cover this field manually.
  final String? conversationShowName;

  /// Avatar and name in message reaction tap callback.
  final void Function(String userID, TapDownDetails tapDetails)? onTapAvatar;

  /// Avatar and name in message reaction secondary tap callback.
  final void Function(String userID, TapDownDetails tapDetails)?
      onSecondaryTapAvatar;

  /// 群聊中长按他人头像；未设置时默认在输入框 @ 对方。
  final void Function(String? userId, String? nickName)?
      onLongPressForOthersHeadPortrait;

  @Deprecated(
    "Nickname will not shows in one-to-one chat, if you tend to control it in group chat, please use `isShowSelfNameInGroup` and `isShowOthersNameInGroup` from `config: TIMUIKitChatConfig` instead",
  )

  /// Should show the nick name.
  final bool showNickName;

  /// Message item builder, can customize partial message item for different types or the layout for the whole line.
  final MessageItemBuilder? messageItemBuilder;

  /// Is show unread message count, default value is false
  final bool showTotalUnReadCount;

  /// Deprecated("Please use [extraTipsActionItemBuilder] instead")
  final Widget? Function(
    V2TimMessage message,
    Function() closeTooltip, [
    Key? key,
    BuildContext? context,
  ])? exteraTipsActionItemBuilder;

  /// The builder for extra tips action.
  final Widget? Function(
    V2TimMessage message,
    Function() closeTooltip, [
    Key? key,
    BuildContext? context,
  ])? extraTipsActionItemBuilder;

  /// The text of draft shows in TextField.
  /// [Recommend]: You can specify this field with the draftText from V2TimConversation.
  final String? draftText;

  /// Called when the input text changes.
  final ValueChanged<String>? onTextChanged;

  /// The target message been jumped just after entering the chat page.
  final V2TimMessage? initFindingMsg;

  /// Stable target anchor for search jump mode.
  final MessageAnchor? searchJumpAnchor;

  /// The hint text shows at input field.
  final String? textFieldHintText;

  /// The configuration for appbar.
  final AppBar? appBarConfig;

  /// The configuration for historical message list.
  final TIMUIKitHistoryMessageListConfig? mainHistoryListConfig;

  /// The configuration for more panel, can customize actions.
  final MorePanelConfig? morePanelConfig;

  /// The builder for the tongue on the right bottom.
  /// Used for back to bottom, shows the count of unread new messages,
  /// and prompts the messages that @ user.
  final TongueItemBuilder? tongueItemBuilder;

  /// The `groupAtInfoList` from `V2TimConversation`.
  /// This field is not necessary to be provided, when `conversation` is provided,
  /// unless you want to cover this field manually.
  final List<V2TimGroupAtInfo?>? groupAtInfoList;

  /// The configuration for the whole `TIMUIKitChat` widget.
  final TIMUIKitChatConfig? config;

  /// The callback for jumping to the page for `TIMUIKitGroupApplicationList`
  /// or other pages to deal with enter group application for group administrator manually,
  /// in the case of [public group].
  /// The parameter here is `String groupID`
  final ValueChanged<String>? onDealWithGroupApplication;

  /// The generator for the abstract summary preview of a message,
  /// typically used in replied and forwarded messages.
  /// Returns `null` to use the default message summary.
  final String? Function(V2TimMessage message)? abstractMessageBuilder;

  /// The configuration for tool tips panel, long press messages will show this panel.
  final ToolTipsConfig? toolTipsConfig;

  /// The life cycle for chat business logic.
  final ChatLifeCycle? lifeCycle;

  /// The top fixed widget.
  final Widget? topFixWidget;

  /// Specify the custom small png emoji packages.
  final List<CustomEmojiFaceData> customEmojiStickerList;

  final Widget? customAppBar;

  final Widget? inputTopBuilder;

  /// 进入会话时从列表捕获的未读数，避免 SDK 提前清未读导致入口提示条失效。
  final int? entryUnreadCount;

  /// 首次打开聊天页只读 SDK 本地快照，不在首屏任务中发起云端历史请求。
  /// 用户主动上拉、搜索定位和后续同步仍然可以请求云端。
  final bool localOnlyInitialOpen;

  /// Optional UI-only projection for local overlay rows. It never changes the
  /// formal message list used by history, unread, or reconciliation.
  final List<V2TimMessage?> Function(
    String conversationID,
    List<V2TimMessage?> formalMessages,
  )? messageListProjectionBuilder;
  final Listenable? messageListProjectionListenable;

  /// Custom emoji panel.
  final CustomStickerPanel? customStickerPanel;

  /// This parameter accepts a custom widget to be displayed when the mouse hovers over a message,
  /// replacing the default message hover action bar.
  /// Applicable only on desktop platforms.
  /// If provided, the default message action functionality will appear in the right-click context menu instead.
  /// Returns `null` to use default hover bar.
  final Widget? Function(V2TimMessage message)? customMessageHoverBarOnDesktop;

  /// Custom text field
  final Widget Function(BuildContext context)? textFieldBuilder;

  /// Wraps the default or custom text field without rebuilding the whole chat.
  final Widget Function(BuildContext context, Widget child)?
      textFieldWrapperBuilder;

  /// An optional parameter `groupMemberList` can be provided.
  /// `groupMemberList` accepts a list of nullable `V2TimGroupMemberFullInfo` objects.
  /// The purpose of this parameter is to allow the client to supply a pre-fetched list
  /// of group member information. If this list is provided, it will not make
  /// additional network requests to fetch the group member information internally.
  List<V2TimGroupMemberFullInfo?>? groupMemberList;

  TIMUIKitChat({
    Key? key,
    this.groupID,
    required this.conversation,
    this.conversationID,
    this.conversationType,
    this.groupMemberList,
    this.conversationShowName,
    this.abstractMessageBuilder,
    this.onTapAvatar,
    @Deprecated(
      "Nickname will not show in one-to-one chat, if you tend to control it in group chat, please use `isShowSelfNameInGroup` and `isShowOthersNameInGroup` from `config: TIMUIKitChatConfig` instead",
    )
    this.showNickName = false,
    this.showTotalUnReadCount = false,
    this.messageItemBuilder,
    @Deprecated("Please use [extraTipsActionItemBuilder] instead")
    this.exteraTipsActionItemBuilder,
    this.extraTipsActionItemBuilder,
    this.draftText,
    this.onTextChanged,
    this.textFieldHintText,
    this.initFindingMsg,
    this.searchJumpAnchor,
    this.userAvatarBuilder,
    this.appBarConfig,
    this.controller,
    this.morePanelConfig,
    this.customStickerPanel,
    this.config = const TIMUIKitChatConfig(),
    this.tongueItemBuilder,
    this.groupAtInfoList,
    this.mainHistoryListConfig,
    this.onDealWithGroupApplication,
    this.toolTipsConfig,
    this.lifeCycle,
    this.topFixWidget = const SizedBox(),
    this.textFieldBuilder,
    this.textFieldWrapperBuilder,
    this.customEmojiStickerList = const [],
    this.customAppBar,
    this.inputTopBuilder,
    this.onSecondaryTapAvatar,
    this.onLongPressForOthersHeadPortrait,
    this.customMessageHoverBarOnDesktop,
    this.messageListProjectionBuilder,
    this.messageListProjectionListenable,
    this.entryUnreadCount,
    this.localOnlyInitialOpen = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TUIChatState();
}

class _TUIChatState extends TIMUIKitState<TIMUIKitChat>
    with WidgetsBindingObserver {
  static const double _scrollDismissDeltaThreshold = 16;

  double _scrollDismissAccumulatedDelta = 0;
  FlutterView? _flutterView;
  double _cachedPaddingBottom = 0;
  late KeyboardViewportTransitionCoordinator _keyboardCoordinator;
  final ImeInsetsBridge _imeInsetsBridge = ImeInsetsBridge();

  TUIChatSeparateViewModel model = TUIChatSeparateViewModel();
  final TUISelfInfoViewModel selfInfoViewModel =
      serviceLocator<TUISelfInfoViewModel>();
  final TUIThemeViewModel themeViewModel = serviceLocator<TUIThemeViewModel>();
  final TUIConversationViewModel conversationViewModel =
      serviceLocator<TUIConversationViewModel>();
  TIMUIKitInputTextFieldController textFieldController =
      TIMUIKitInputTextFieldController();
  bool isInit = false;
  final TUIChatGlobalModel chatGlobalModel =
      serviceLocator<TUIChatGlobalModel>();
  bool _dragging = false;
  V2TimGroupListener? _groupListener;

  final GlobalKey alignKey = GlobalKey();

  /// 页面内按会话稳定的列表 Key：
  /// 父级 remount 时复用同一 GlobalKey 实例，把已有列表 State 挂回去。
  final GlobalKey messageInputAnchorKey = GlobalKey();
  final _listStableKeys = ChatListStableKeys();

  late AutoScrollController autoController = AutoScrollController(
    viewportBoundaryGetter: () =>
        Rect.fromLTRB(0, 0, 0, _cachedPaddingBottom),
    axis: Axis.vertical,
  );

  late AutoScrollController atMemberPanelScroll = AutoScrollController(
    viewportBoundaryGetter: () =>
        Rect.fromLTRB(0, 0, 0, _cachedPaddingBottom),
    axis: Axis.vertical,
  );

  final ValueNotifier<Widget?> _joinInGroupCallWidget =
      ValueNotifier<Widget?>(null);
  List<CustomEmojiFaceData>? _cachedEmojiPackages;
  Object? _cachedEmojiConfigKey;

  List<CustomEmojiFaceData> _resolveEmojiPackages() {
    final configKey = Object.hash(
      widget.config?.stickerPanelConfig?.customStickerPackages,
      widget.customEmojiStickerList,
    );
    if (_cachedEmojiPackages != null && _cachedEmojiConfigKey == configKey) {
      return _cachedEmojiPackages!;
    }
    List<CustomEmojiFaceData> customImageSmallPngEmojiPackages = [];
    if (widget.config?.stickerPanelConfig?.customStickerPackages != null &&
        widget.config!.stickerPanelConfig!.customStickerPackages.isNotEmpty) {
      customImageSmallPngEmojiPackages = widget
          .config!.stickerPanelConfig!.customStickerPackages
          .where((element) => element.isEmoji == true)
          .map((e) {
        return CustomEmojiFaceData(
          name: e.name,
          isEmoji: true,
          icon: e.menuItem.url ?? e.menuItem.name,
          list: e.stickerList
              .map((s) => (s.url?.isNotEmpty == true ? s.url! : s.name))
              .toList(),
        );
      }).toList();
    }
    if (customImageSmallPngEmojiPackages.isEmpty) {
      customImageSmallPngEmojiPackages.addAll(widget.customEmojiStickerList);
    }
    _cachedEmojiConfigKey = configKey;
    _cachedEmojiPackages = customImageSmallPngEmojiPackages;
    return customImageSmallPngEmojiPackages;
  }

  void _onChatBackgroundRegistryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onGroupMemberStoreChanged() {
    if (!mounted || _getConvType() != ConvType.group) {
      return;
    }
    final change = GroupMemberStore.instance.lastChange;
    if (change == null) {
      return;
    }
    model.applyGroupMemberChange(change);
  }

  void _onDisplayNameStoreChanged() {
    if (!mounted) {
      return;
    }
    final change = DisplayNameStore.instance.lastChange;
    if (change == null) {
      return;
    }
    model.applyDisplayNameChange(change);
  }

  void _onKeyboardTransitionBegin() {
    chatGlobalModel.beginKeyboardViewportTransition(_getConvID());
  }

  void _onKeyboardTransitionEnd() {
    chatGlobalModel.endKeyboardViewportTransition(_getConvID());
  }

  void _cachePaddingFromView(FlutterView view) {
    final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    _cachedPaddingBottom = view.padding.bottom / dpr;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute registers a dependency and notifies when another route covers
    // this chat, even though the chat State remains mounted in the stack.
    if (ModalRoute.of(context)?.isCurrent == false) {
      model.stopVoiceAutoPlay();
    }
    _flutterView = View.maybeOf(context);
    final view = _flutterView;
    if (view != null) {
      _cachePaddingFromView(view);
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final view = _flutterView;
    if (view == null) {
      return;
    }
    _cachePaddingFromView(view);
    _keyboardCoordinator.applyFromView(view);
  }

  @override
  void initState() {
    super.initState();
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'TIMUIKitChat',
      phase: 'initState',
      stateHash: identityHashCode(this),
      conv: _getConvID(),
    );
    final settingModel = serviceLocator<TUISettingModel>();
    _keyboardCoordinator = KeyboardViewportTransitionCoordinator(
      onBegin: _onKeyboardTransitionBegin,
      onEnd: _onKeyboardTransitionEnd,
      persistTrustedHeight: (height) {
        settingModel.keyboardHeight = height;
      },
    );
    _keyboardCoordinator.seedCachedHeight(settingModel.keyboardHeight);
    KeyboardViewportTransitionCoordinator.active = _keyboardCoordinator;
    _imeInsetsBridge.start(_keyboardCoordinator);
    WidgetsBinding.instance.addObserver(this);
    chatGlobalModel.setChatAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    TIMUIKitChatBackgroundRegistry.instance.addListener(
      _onChatBackgroundRegistryChanged,
    );
    GroupMemberStore.instance.addListener(_onGroupMemberStoreChanged);
    DisplayNameStore.instance.addListener(_onDisplayNameStoreChanged);
    if (kProfileMode) {
      Frame.init();
    }
    ChatMainThreadPerf.retainFrameTimingProbe();
    _addGroupListener();
    model.abstractMessageBuilder = widget.abstractMessageBuilder;
    model.onTapAvatar = widget.onTapAvatar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final view = _flutterView;
      if (view != null) {
        _keyboardCoordinator.applyFromView(view);
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) {
        return;
      }
      _updateJoinInGroupCallWidget();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      updateDraft();
    });
  }

  void _dismissInputKeyboardAndPanels({bool notifyAtPanel = true}) {
    widget.controller?.hideAllBottomPanelOnMobile();
    FocusManager.instance.primaryFocus?.unfocus();
    model.clearAtPanelState(notify: notifyAtPanel);
  }

  void _dismissInputKeyboardOnlyForDetach() {
    FocusManager.instance.primaryFocus?.unfocus();
    model.clearAtPanelState(notify: false);
  }

  /// 点击消息区空白：收起键盘与全部底部面板（与滑动列表一致）。
  void _dismissInputOnMessageAreaTap() {
    if (textFieldController.shouldIgnoreAccessoryDismiss()) {
      return;
    }
    _dismissInputKeyboardAndPanels();
  }

  /// 滑动消息列表：收起键盘与全部底部面板（与微信一致）。
  void _dismissInputOnScroll() {
    if (!textFieldController.isInputPanelOpen) {
      return;
    }
    if (textFieldController.shouldIgnoreAccessoryDismiss()) {
      return;
    }
    widget.controller?.hideAllBottomPanelOnMobile();
  }

  bool _onMessageListScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollEndNotification) {
      _scrollDismissAccumulatedDelta = 0;
      return false;
    }
    // 仅手指拖动列表时收起；忽略惯性滚动、animateTo/jumpTo 等程序滚动。
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta?.abs() ?? 0;
      if (delta <= 0) {
        return false;
      }
      _scrollDismissAccumulatedDelta += delta;
      if (_scrollDismissAccumulatedDelta >= _scrollDismissDeltaThreshold) {
        _scrollDismissAccumulatedDelta = 0;
        _dismissInputOnScroll();
      }
    }
    return false;
  }

  Widget _wrapMessageListForAccessoryDismiss(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onMessageListScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _dismissInputOnMessageAreaTap(),
        child: child,
      ),
    );
  }

  @override
  void deactivate() {
    // Flutter 正在 deactivate/build 阶段时不能触发 Provider 通知。
    // 这里只清本地输入焦点和 @ 面板缓存，不广播刷新整个聊天列表。
    _dismissInputKeyboardOnlyForDetach();
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    chatGlobalModel.setChatAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      model.stopVoiceAutoPlay();
    }
  }

  @override
  void dispose() {
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'TIMUIKitChat',
      phase: 'dispose',
      stateHash: identityHashCode(this),
      conv: widget.conversationID ?? _getConvID(),
    );
    WidgetsBinding.instance.removeObserver(this);
    serviceLocator<ChatUiStateStore>().clearConversationState(
      _getConvID(),
      notify: false,
    );
    chatGlobalModel.clearActiveChatScrollController(
      conversationID: widget.conversationID,
    );
    _dismissInputKeyboardOnlyForDetach();
    TIMUIKitChatBackgroundRegistry.instance.removeListener(
      _onChatBackgroundRegistryChanged,
    );
    GroupMemberStore.instance.removeListener(_onGroupMemberStoreChanged);
    DisplayNameStore.instance.removeListener(_onDisplayNameStoreChanged);
    ChatMainThreadPerf.releaseFrameTimingProbe();
    _imeInsetsBridge.stop();
    super.dispose();
    _keyboardCoordinator.dispose();
    _joinInGroupCallWidget.dispose();
    if (kProfileMode) {
      Frame.destroy();
    }
    _removeGroupListener();
    model.dispose();
  }

  @override
  void didUpdateWidget(TIMUIKitChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchTargetKey(widget) != _searchTargetKey(oldWidget)) {
      // A desktop pane may reuse this State for another result in the same chat.
      isInit = false;
    }
    if (widget.conversationID != oldWidget.conversationID) {
      model.stopVoiceAutoPlay();
      _keyboardCoordinator.reset();
      serviceLocator<ChatUiStateStore>().clearConversationState(
        oldWidget.conversationID ?? '',
      );
      isInit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
      chatGlobalModel.clearCurrentConversation();
      _updateJoinInGroupCallWidget();
      final existing = widget.controller?.model;
      if (existing != null &&
          existing.conversationID == widget.conversationID) {
        model = existing;
      } else {
        model = TUIChatSeparateViewModel();
      }
      model.abstractMessageBuilder = widget.abstractMessageBuilder;
      model.onTapAvatar = widget.onTapAvatar;
      Future.delayed(const Duration(milliseconds: 50), () {
        updateDraft();
        try {
          if (autoController.hasClients &&
              !chatGlobalModel.hasPendingScrollRestore(widget.conversationID)) {
            autoController.jumpTo(autoController.position.minScrollExtent);
          }
          // ignore: empty_catches
        } catch (e) {}
      });
    }
    if (oldWidget.textFieldBuilder != null && widget.textFieldBuilder == null) {
      textFieldController = TIMUIKitInputTextFieldController();
    }
    if (oldWidget.groupMemberList != widget.groupMemberList) {
      model.groupMemberList = widget.groupMemberList == null
          ? null
          : List<V2TimGroupMemberFullInfo?>.from(widget.groupMemberList!);
    }
    if (oldWidget.config?.stickerPanelConfig?.customStickerPackages !=
            widget.config?.stickerPanelConfig?.customStickerPackages ||
        oldWidget.customEmojiStickerList != widget.customEmojiStickerList) {
      _cachedEmojiPackages = null;
      _cachedEmojiConfigKey = null;
    }
  }

  void _addGroupListener() {
    _groupListener = V2TimGroupListener(
      onGroupAttributeChanged:
          (String groupID, Map<String, String> groupAttributeMap) {
        if (groupID == widget.conversationID) {
          _updateJoinInGroupCallWidget();
        }
      },
    );
    TencentImSDKPlugin.v2TIMManager.addGroupListener(listener: _groupListener!);
  }

  void _removeGroupListener() {
    if (_groupListener != null) {
      TencentImSDKPlugin.v2TIMManager.removeGroupListener(
        listener: _groupListener!,
      );
      _groupListener = null;
    }
  }

  updateDraft() async {
    final isTopic = widget.conversation.conversationID.contains("@TOPIC#");
    if (isTopic) {
      final topicInfoList = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getTopicInfoList(
        groupID: widget.groupID!,
        topicIDList: [widget.conversation.conversationID],
      );
      final topicInfo = topicInfoList.data?.first.topicInfo;
      final draftText = topicInfo?.draftText;
      if (TencentUtils.checkString(draftText) != null) {
        textFieldController.setTextField(draftText!, notifyChanged: false);
      }
    }
  }

  Widget _renderJoinGroupApplication(int amount, TUITheme theme) {
    String option1 = amount.toString();
    return Container(
      height: 36,
      decoration: BoxDecoration(color: hexToColor("f6eabc")),
      child: GestureDetector(
        onTap: () {
          if (widget.onDealWithGroupApplication != null) {
            widget.onDealWithGroupApplication!(_getConvID());
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              TIM_t_para("{{option1}} 条入群请求", "$option1 条入群请求")(
                option1: option1,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            Container(
              margin: const EdgeInsets.only(left: 12),
              child: Text(
                TIM_t("去处理"),
                style: TextStyle(fontSize: 12, color: theme.primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    return TencentUtils.checkString(widget.conversationShowName) ??
        widget.conversation.showName ??
        "Chat";
  }

  String _getConvID() {
    return TencentUtils.checkString(widget.conversationID) ??
        (widget.conversation.type == 1
            ? widget.conversation.userID
            : widget.conversation.groupID) ??
        "";
  }

  /// 与 [ChatBackgroundService] 存储键一致，优先使用 IM 会话 ID（如 c2c_xxx / group_xxx）。
  String _getBackgroundRegistryKey() {
    final conversationId = TencentUtils.checkString(
      widget.conversation.conversationID,
    );
    if (conversationId != null && conversationId.isNotEmpty) {
      return conversationId;
    }
    return _getConvID();
  }

  String? _searchTargetKey(TIMUIKitChat chat) => (chat.searchJumpAnchor ??
          (chat.initFindingMsg == null
              ? null
              : MessageAnchor.fromConversationMessage(
                  chat.conversation, chat.initFindingMsg!)))
      ?.stableKey;

  GlobalKey _listContainerKeyForConversation() {
    return _listStableKeys.containerFor(
        '${_getConvID()}|${_searchTargetKey(widget) ?? "latest"}');
  }

  ConvType _getConvType() {
    return widget.conversation.type == 1 ? ConvType.c2c : ConvType.group;
  }

  int _resolvedEntryUnreadCount() {
    final captured = widget.entryUnreadCount ?? 0;
    final current = widget.conversation.unreadCount ?? 0;
    return captured > current ? captured : current;
  }

  _updateJoinInGroupCallWidget() async {
    if (_getConvType() != ConvType.group) {
      return;
    }
    final w = await TUICore.instance.raiseExtension(
      TUIExtensionID.joinInGroup,
      {GROUP_ID: widget.conversationID!},
    );
    if (!mounted) {
      return;
    }
    if (w != _joinInGroupCallWidget.value) {
      ChatJitterDiag.log(
        'join_group_call_slot',
        conv: _getConvID(),
        extras: <String, Object?>{
          'hadWidget': _joinInGroupCallWidget.value != null,
          'nextWidget': w != null,
          'stack': ChatJitterDiag.compactStack(),
        },
      );
      _joinInGroupCallWidget.value = w;
    }
  }

  bool _isOfficialAccountChat() {
    return PlatformOfficialAccountService.matchesOfficialConversation(
          widget.conversation,
        ) ||
        PlatformOfficialAccountService.isPlatformOfficialAccount(
          widget.conversation.userID,
        ) ||
        ChatBackgroundService.isOfficialAccountConversationId(
          _getBackgroundRegistryKey(),
        );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;
    final isOfficialAccountChat = _isOfficialAccountChat();
    final backgroundImagePath = isOfficialAccountChat
        ? null
        : TIMUIKitChatBackgroundRegistry.getPath(_getBackgroundRegistryKey());
    final isColorBackground =
        backgroundImagePath?.startsWith(ChatBackgroundService.colorPrefix) ??
            false;
    final isAssetBackground =
        backgroundImagePath?.startsWith(ChatBackgroundService.assetPrefix) ??
            false;
    final isFileBackground =
        backgroundImagePath?.startsWith(ChatBackgroundService.filePrefix) ??
            false;
    final backgroundImageProvider =
        backgroundImagePath == null || isColorBackground
            ? null
            : isAssetBackground
                ? AssetImage(
                    backgroundImagePath.substring(
                      ChatBackgroundService.assetPrefix.length,
                    ),
                  )
                : timUIKitLocalImageProvider(
                    isFileBackground
                        ? backgroundImagePath.substring(
                            ChatBackgroundService.filePrefix.length,
                          )
                        : backgroundImagePath,
                  );
    final hasCustomBackground =
        backgroundImageProvider != null || isColorBackground;
    final Color? backgroundColor = isColorBackground
        ? Color(
            int.tryParse(
                  backgroundImagePath!.substring(
                    ChatBackgroundService.colorPrefix.length,
                  ),
                  radix: 16,
                ) ??
                0xFFF3F5F8,
          )
        : null;
    final isBuild = isInit;
    isInit = true;

    return TIMUIKitChatProviderScope(
      model: model,
      groupID: widget.groupID,
      groupType: widget.conversation.groupType,
      scrollController: autoController,
      textFieldController: textFieldController,
      conversationID: _getConvID(),
      previewLastMessage: widget.conversation.lastMessage,
      initFindingMsg: widget.initFindingMsg,
      searchJumpAnchor: widget.searchJumpAnchor,
      groupMemberList: widget.groupMemberList,
      conversationType: _getConvType(),
      initialUnreadCount: _resolvedEntryUnreadCount(),
      localOnlyInitialOpen: widget.localOnlyInitialOpen,
      lifeCycle: widget.lifeCycle,
      config: widget.config,
      isBuild: isBuild,
      providers: [
        // 用 value 避免每次 rebuild 换 create 闭包；config 变更走 updateShouldNotify。
        Provider<TIMUIKitChatConfig>.value(
          value: widget.config ?? const TIMUIKitChatConfig(),
        ),
      ],
      builder: (context, model, w) {
        widget.controller?.model = model;
        widget.controller?.textFieldController = textFieldController;
        widget.controller?.scrollController = autoController;

        final selfUserID = selfInfoViewModel.loginInfo?.userID;

        final customImageSmallPngEmojiPackages = _resolveEmojiPackages();
        _keyboardCoordinator.noteChatBuild();

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: (widget.customAppBar == null)
              ? TIMUIKitAppBar(
                  showTotalUnReadCount: widget.showTotalUnReadCount,
                  config: widget.appBarConfig,
                  conversationShowName: _getTitle(),
                  conversationID: _getConvID(),
                  conversationType: _getConvType() == ConvType.group ? 2 : 1,
                  showC2cMessageEditStatus:
                      widget.config?.showC2cMessageEditStatus ?? true,
                )
              : null,
          body: DropTarget(
            onDragDone: (detail) {
              setState(() {
                _dragging = false;
                sendFileWithConfirmation(
                  files: detail.files,
                  conversation: widget.conversation,
                  conversationType: _getConvType(),
                  model: model,
                  theme: theme,
                  context: context,
                );
              });
            },
            onDragEntered: (detail) {
              setState(() {
                _dragging = true;
              });
            },
            onDragExited: (detail) {
              setState(() {
                _dragging = false;
              });
            },
            child: Stack(
              children: [
                KeyboardTransitionScope(
                  coordinator: _keyboardCoordinator,
                  child: ChatMessageInputAnchor(
                    inputAnchorKey: messageInputAnchorKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyedSubtree(
                          key: const ValueKey('chat_custom_app_bar'),
                          child: widget.customAppBar ?? const SizedBox.shrink(),
                        ),
                        KeyedSubtree(
                          key: const ValueKey('chat_group_application_banner'),
                          child: _GroupApplicationBanner(
                            conversationID: widget.conversationID ?? '',
                            conversationType: _getConvType(),
                            onDealWithGroupApplication:
                                widget.onDealWithGroupApplication,
                            theme: theme,
                            bannerBuilder: _renderJoinGroupApplication,
                          ),
                        ),
                        KeyedSubtree(
                          key: const ValueKey('chat_top_fix'),
                          child: widget.topFixWidget ?? const SizedBox.shrink(),
                        ),
                        // 槽位始终占住，避免异步插入 join-call 条时 Expanded 错位卸列表。
                        KeyedSubtree(
                          key: const ValueKey('chat_join_group_call'),
                          child: ValueListenableBuilder<Widget?>(
                            valueListenable: _joinInGroupCallWidget,
                            builder: (context, joinWidget, _) {
                              return joinWidget != null
                                  ? Center(child: joinWidget)
                                  : const SizedBox.shrink();
                            },
                          ),
                        ),
                        Expanded(
                          key: const ValueKey('chat_message_list_expanded'),
                          child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              decoration: hasCustomBackground
                                  ? BoxDecoration(
                                      color: backgroundColor,
                                      image: backgroundImageProvider == null
                                          ? null
                                          : DecorationImage(
                                              image: backgroundImageProvider,
                                              fit: BoxFit.cover,
                                            ),
                                    )
                                  : BoxDecoration(color: theme.chatBgColor),
                              child: RepaintBoundary(
                                child: _wrapMessageListForAccessoryDismiss(
                                  TIMUIKitHistoryMessageListContainer(
                                    customMessageHoverBarOnDesktop:
                                        widget.customMessageHoverBarOnDesktop,
                                    conversation: widget.conversation,
                                    // open-shell 后 list 常为非空元素 List，
                                    // firstWhere(orElse: () => null) 会类型崩溃整页灰屏。
                                    groupMemberInfo: model.selfMemberInfo ??
                                        model.groupMemberList?.firstWhereOrNull(
                                          (element) =>
                                              element?.userID == selfUserID,
                                        ),
                                    textFieldController: textFieldController,
                                    customEmojiStickerList:
                                        customImageSmallPngEmojiPackages,
                                    key: _listContainerKeyForConversation(),
                                    isAllowScroll: true,
                                    userAvatarBuilder: widget.userAvatarBuilder,
                                    toolTipsConfig: widget.toolTipsConfig,
                                    groupAtInfoList: widget.groupAtInfoList,
                                    tongueItemBuilder: widget.tongueItemBuilder,
                                    onLongPressForOthersHeadPortrait: widget
                                            .onLongPressForOthersHeadPortrait ??
                                        (String? userId, String? nickName) {
                                          textFieldController.longPressToAt(
                                            nickName,
                                            userId,
                                          );
                                        },
                                    onAtUserWhenReply:
                                        (String? userId, String? nickName) {
                                      textFieldController.longPressToAt(
                                        nickName,
                                        userId,
                                        pinToLatest: true,
                                      );
                                    },
                                    mainHistoryListConfig:
                                        widget.mainHistoryListConfig,
                                    initFindingMsg: widget.initFindingMsg,
                                    searchJumpAnchor: widget.searchJumpAnchor,
                                    extraTipsActionItemBuilder:
                                        widget.extraTipsActionItemBuilder ??
                                            widget.exteraTipsActionItemBuilder,
                                    conversationType: _getConvType(),
                                    scrollController: autoController,
                                    onSecondaryTapAvatar:
                                        widget.onSecondaryTapAvatar,
                                    onTapAvatar: widget.onTapAvatar,
                                    // ignore: deprecated_member_use_from_same_package
                                    showNickName: widget.showNickName,
                                    messageItemBuilder:
                                        widget.messageItemBuilder,
                                    messageListProjectionBuilder:
                                        widget.messageListProjectionBuilder,
                                    messageListProjectionListenable:
                                        widget.messageListProjectionListenable,
                                    conversationID: _getConvID(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        KeyedSubtree(
                          key: messageInputAnchorKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              widget.inputTopBuilder ?? Container(),
                              Selector2<ChatUiStateStore,
                                  TUIChatSeparateViewModel, bool>(
                                builder: (context, value, child) {
                                  if (value) {
                                    return MultiSelectPanel(
                                      conversationType: _getConvType(),
                                    );
                                  }
                                  final input = widget.textFieldBuilder != null
                                      ? widget.textFieldBuilder!(context)
                                      : TIMUIKitInputTextField(
                                          chatConfig: widget.config,
                                          groupID: widget.groupID,
                                          atMemberPanelScroll:
                                              atMemberPanelScroll,
                                          groupType:
                                              widget.conversation.groupType,
                                          currentConversation:
                                              widget.conversation,
                                          model: model,
                                          controller: textFieldController,
                                          customEmojiStickerList:
                                              customImageSmallPngEmojiPackages,
                                          customStickerPanel:
                                              widget.customStickerPanel,
                                          morePanelConfig:
                                              widget.morePanelConfig,
                                          scrollController: autoController,
                                          conversationID: _getConvID(),
                                          conversationType: _getConvType(),
                                          initText: TencentUtils.checkString(
                                                widget.draftText,
                                              ) ??
                                              (widget.config?.isUseDraft ==
                                                      false
                                                  ? null
                                                  : (PlatformUtils().isWeb
                                                      ? TencentUtils
                                                          .checkString(
                                                          conversationViewModel
                                                              .getWebDraft(
                                                            conversationID: widget
                                                                .conversation
                                                                .conversationID,
                                                          ),
                                                        )
                                                      : TencentUtils
                                                          .checkString(
                                                          widget.conversation
                                                              .draftText,
                                                        ))),
                                          onChanged: widget.onTextChanged,
                                          hintText: widget.textFieldHintText,
                                          showMorePanel: widget.config
                                                  ?.isAllowShowMorePanel ??
                                              true,
                                          showSendAudio: widget.config
                                                  ?.isAllowSoundMessage ??
                                              true,
                                          showSendEmoji: widget
                                                  .config?.isAllowEmojiPanel ??
                                              true,
                                        );
                                  return widget.textFieldWrapperBuilder?.call(
                                        context,
                                        input,
                                      ) ??
                                      input;
                                },
                                selector: (c, stateStore, chatModel) {
                                  // 优先用 model 会话 ID；store 内已做 c2c_/group_ 归一化。
                                  final convId =
                                      chatModel.conversationID.isNotEmpty
                                          ? chatModel.conversationID
                                          : _getConvID();
                                  return stateStore.isMultiSelect(convId);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_dragging)
                  TIMUIKitSendFile(conversation: widget.conversation),
                AtMemberPanel(
                  atMemberPanelScroll: atMemberPanelScroll,
                  onSelectMember: (member) =>
                      textFieldController.handleAtMember(member),
                ),
                _GroupUpdateListener(
                  conversationID: widget.conversationID ?? '',
                  model: model,
                  getConvID: _getConvID,
                ),
                ListenableBuilder(
                  listenable: chatGlobalModel,
                  builder: (context, _) {
                    final req = chatGlobalModel.sendFlyOverlayRequest;
                    final convId = widget.conversationID ?? _getConvID();
                    if (req == null || req.conversationId != convId) {
                      return const SizedBox.shrink();
                    }
                    return ChatSendFlyOverlayHost(
                      request: req,
                      inputAnchorKey: messageInputAnchorKey,
                      onFinished: chatGlobalModel.completeSendFlyOverlay,
                      backgroundColor: theme.chatMessageItemFromSelfBgColor ??
                          const Color(0xFF95EC69),
                      textColor: theme.chatMessageItemTextColor ??
                          const Color(0xFF111111),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupApplicationBanner extends StatelessWidget {
  final String conversationID;
  final ConvType conversationType;
  final void Function(String groupID)? onDealWithGroupApplication;
  final TUITheme theme;
  final Widget Function(int amount, TUITheme theme) bannerBuilder;

  const _GroupApplicationBanner({
    required this.conversationID,
    required this.conversationType,
    required this.onDealWithGroupApplication,
    required this.theme,
    required this.bannerBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (conversationType != ConvType.group ||
        onDealWithGroupApplication == null) {
      return const SizedBox.shrink();
    }
    return Selector<TUIChatGlobalModel, int>(
      selector: (_, model) => model.groupApplicationList
          .where(
            (item) => item.groupID == conversationID && item.handleStatus == 0,
          )
          .length,
      builder: (context, count, _) {
        if (count <= 0) {
          return const SizedBox.shrink();
        }
        return bannerBuilder(count, theme);
      },
    );
  }
}

class _GroupUpdateListener extends StatelessWidget {
  final String conversationID;
  final TUIChatSeparateViewModel model;
  final String Function() getConvID;

  const _GroupUpdateListener({
    required this.conversationID,
    required this.model,
    required this.getConvID,
  });

  static bool _matchesGroupConversation(
    String needUpdateGroupId,
    String conversationId,
  ) {
    final raw = needUpdateGroupId.trim();
    final conv = conversationId.trim();
    if (raw.isEmpty || conv.isEmpty) {
      return false;
    }
    if (raw == conv) {
      return true;
    }
    if (conv == 'group_$raw' || raw == 'group_$conv') {
      return true;
    }
    if (conv.startsWith('group_') && conv.substring(6) == raw) {
      return true;
    }
    return false;
  }

  Future<void> _refreshGroupMuteState(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }

    await model.loadGroupInfo(id);
    await model.loadSelfMemberInfo(groupID: id);
  }

  @override
  Widget build(BuildContext context) {
    // Pipeline [6] - timuikit_build：UIKit 首次 build 进入
    if (conversationID.isNotEmpty) {
      final pipelineKey = ChatPipelineClock.normalizeKey(
        rawConversationId: conversationID,
        groupId: conversationID.startsWith('c2c_') ? null : conversationID,
      );
      // ignore: avoid_print
      debugPrint(
        '[Pipeline] stage=timuikit_build conv=$pipelineKey '
        'offset=${ChatPipelineClock.instance.offsetMs(pipelineKey)}ms',
      );
    }
    return Selector<TUIGroupListenerModel, NeedUpdate?>(
      selector: (_, groupListenerModel) {
        final needUpdate = groupListenerModel.needUpdate;
        if (needUpdate != null &&
            _matchesGroupConversation(needUpdate.groupID, conversationID)) {
          return needUpdate;
        }
        return null;
      },
      builder: (context, needUpdate, _) {
        if (needUpdate != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final groupListenerModel = context.read<TUIGroupListenerModel>();
            final pending = groupListenerModel.needUpdate;
            if (pending == null ||
                !_matchesGroupConversation(pending.groupID, conversationID)) {
              return;
            }
            groupListenerModel.needUpdate = null;
            final convId = getConvID();
            switch (needUpdate.updateType) {
              case UpdateType.groupInfo:
                model.loadGroupInfo(convId);
                break;
              case UpdateType.memberEnter:
                model.processGroupMemberListEnter(
                  groupID: convId,
                  memberList: needUpdate.extraData,
                );
                break;
              case UpdateType.memberLeave:
                model.processGroupMemberListLeave(
                  groupID: convId,
                  memberList: needUpdate.extraData,
                );
                break;
              case UpdateType.memberListReload:
                unawaited(_refreshGroupMuteState(convId));
                break;
              default:
                break;
            }
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class TIMUIKitChatProviderScope extends StatelessWidget {
  final TUIChatGlobalModel globalModel = serviceLocator<TUIChatGlobalModel>();
  final ChatUiStateStore chatUiStateStore = serviceLocator<ChatUiStateStore>();
  TUIChatSeparateViewModel? model;
  final TUIGroupListenerModel groupListenerModel =
      serviceLocator<TUIGroupListenerModel>();
  final TUIFriendShipViewModel friendShipViewModel =
      serviceLocator<TUIFriendShipViewModel>();
  final TUIThemeViewModel themeViewModel = serviceLocator<TUIThemeViewModel>();
  final Widget? child;

  /// You could get the model from here, and transfer it to other widget from TUIKit.
  final Widget Function(BuildContext, TUIChatSeparateViewModel, Widget?)
      builder;
  final List<SingleChildWidget>? providers;

  /// `TIMUIKitChatController` needs to be provided if you use it outside.
  final TIMUIKitChatController? controller;

  /// The global config for TIMUIKitChat.
  final TIMUIKitChatConfig? config;

  /// Conversation id, use for get history message list.
  final String conversationID;

  final String? groupID;

  /// Backend/SDK group type used to select Community history routing.
  final String? groupType;

  /// Conversation type
  final ConvType conversationType;

  final int initialUnreadCount;

  final bool localOnlyInitialOpen;

  /// The life cycle for chat business logic.
  final ChatLifeCycle? lifeCycle;

  /// The controller for text field.
  final TIMUIKitInputTextFieldController? textFieldController;

  final bool? isBuild;

  final V2TimMessage? initFindingMsg;

  final V2TimMessage? previewLastMessage;

  final MessageAnchor? searchJumpAnchor;

  final AutoScrollController? scrollController;

  /// An optional parameter `groupMemberList` can be provided.
  /// `groupMemberList` accepts a list of nullable `V2TimGroupMemberFullInfo` objects.
  /// The purpose of this parameter is to allow the client to supply a pre-fetched list
  /// of group member information. If this list is provided, it will not make
  /// additional network requests to fetch the group member information internally.
  List<V2TimGroupMemberFullInfo?>? groupMemberList;

  TIMUIKitChatProviderScope({
    Key? key,
    this.child,
    this.providers,
    this.groupMemberList,
    this.textFieldController,
    required this.builder,
    this.model,
    this.groupID,
    this.groupType,
    this.isBuild,
    this.initFindingMsg,
    this.previewLastMessage,
    this.searchJumpAnchor,
    required this.conversationID,
    required this.conversationType,
    this.initialUnreadCount = 0,
    this.localOnlyInitialOpen = false,
    this.controller,
    this.config,
    this.lifeCycle,
    this.scrollController,
  }) : super(key: key) {
    if (isBuild ?? false) {
      return;
    }
    final existingModel = controller?.model;
    if (existingModel != null &&
        existingModel.conversationID == conversationID &&
        existingModel.conversationType == conversationType) {
      model = existingModel;
    } else {
      model ??= TUIChatSeparateViewModel();
    }
    model?.localOnlyInitialOpen = localOnlyInitialOpen;
    // K.1：注入 entryUnreadCount 到 viewModel，供首屏动态 count 使用。
    model?.initialUnreadCount = initialUnreadCount;
    controller?.model = model;
    controller?.textFieldController = textFieldController;
    controller?.scrollController = scrollController;
    if (config != null) {
      model?.chatConfig = config!;
    }
    model?.lifeCycle = lifeCycle;
    final isPlainInitialOpen =
        searchJumpAnchor == null && initFindingMsg == null;
    final entryConversation = serviceLocator<TUIConversationViewModel>()
        .getConversation(_fullConversationId());
    final entryWindow = globalModel.rawMessageList(conversationID);
    model?.entryUnreadLastMessage = isPlainInitialOpen
        ? (previewLastMessage ??
            entryConversation?.lastMessage ??
            (entryWindow?.isNotEmpty == true ? entryWindow!.first : null))
        : null;
    final historyPositionBeforeInit = globalModel.getMessageListPosition(
      conversationID,
    );
    final searchJumpStatusBeforeInit = globalModel.getSearchJumpStatus(
      conversationID,
    );
    model?.initForEachConversation(
      conversationType,
      conversationID,
      (String value) {
        textFieldController?.textEditingController?.text = value;
      },
      preGroupMemberList: groupMemberList,
      groupID: groupID,
      groupType: groupType,
    );
    ChatOpenPerfLog.mark(
      'uikit_initForEachConversation',
      conversationID: conversationID,
    );
    model?.showC2cMessageEditStatus = (conversationType == ConvType.c2c
        ? config?.showC2cMessageEditStatus ?? true
        : false);

    // 进入会话前先冻结入口未读数。SDK 清未读可能会很快把
    // conversation.unreadCount 置 0，如果这里不先保存，消息列表会直接
    // 当成“已读会话”滚到底部，后续再点“xx条新消息”就只能重新拉取，
    // 容易丢掉首条未读之后的新消息窗口。
    final shouldLockInitialUnread = isPlainInitialOpen &&
        initialUnreadCount > 0 &&
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          conversationType,
          initialUnreadCount,
        );
    final shouldResetToLatestWindow = isPlainInitialOpen &&
        (searchJumpStatusBeforeInit == SearchJumpStatus.success ||
            searchJumpStatusBeforeInit == SearchJumpStatus.failed ||
            historyPositionBeforeInit == HistoryMessagePosition.notShowLatest ||
            historyPositionBeforeInit == HistoryMessagePosition.awayTwoScreen);
    OutgoingVisibleProbe.log(
      'enter_window_policy',
      conversationID: conversationID,
      extras: <String, Object?>{
        'isPlainInitialOpen': isPlainInitialOpen,
        'unread': initialUnreadCount,
        'shouldLockUnread': shouldLockInitialUnread,
        'shouldResetLatest': shouldResetToLatestWindow,
        'searchJump': searchJumpStatusBeforeInit.name,
        'position': historyPositionBeforeInit.name,
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(conversationID),
        ),
      },
    );
    if (shouldResetToLatestWindow) {
      OutgoingVisibleProbe.log(
        'enter_reset_latest_wipe',
        conversationID: conversationID,
      );
      globalModel.removeMessageList(conversationID);
      model?.haveMoreData = false;
      model?.haveMoreLatestData = false;
      globalModel.clearSearchJumpStatus(conversationID, notify: false);
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: true,
      );
    }
    if (shouldLockInitialUnread) {
      // Preserve the prepared latest page; locating older unread happens on tap.
      _lockEntryUnreadWithFrozenSeq(
        conversationID: conversationID,
        unreadCount: initialUnreadCount,
      );
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: false,
      );
    } else if (initialUnreadCount > 0 &&
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          conversationType,
          initialUnreadCount,
        )) {
      _lockEntryUnreadWithFrozenSeq(
        conversationID: conversationID,
        unreadCount: initialUnreadCount,
      );
    } else if (!UnreadTonguePolicy.entryUnreadTongueEnabled ||
        !globalModel.hasLockedEntryUnreadFor(conversationID)) {
      globalModel.unlockEntryUnreadForTongue(
        conversationID: conversationID,
        notify: false,
      );
      globalModel.setUnreadCountForTongue(
        0,
        conversationID: conversationID,
        notify: false,
      );
    }

    ChatOpenPerfLog.mark(
      'uikit_loadData_started',
      conversationID: conversationID,
      extras: <String, Object?>{
        'localOnly': localOnlyInitialOpen,
        'hasInFlight': globalModel.hasOpenHydrateInFlight(conversationID),
        'rawCount': globalModel.rawMessageCount(conversationID),
        'historyPosition':
            globalModel.getMessageListPosition(conversationID).name,
      },
    );
    _loadData(
      initFindingMsg: initFindingMsg,
      searchJumpAnchor: searchJumpAnchor,
    );
  }

  void _lockEntryUnreadWithFrozenSeq({
    required String conversationID,
    required int unreadCount,
    bool notify = true,
  }) {
    final isGroup = conversationType == ConvType.group;
    final conversationViewModel = serviceLocator<TUIConversationViewModel>();
    final conversation =
        conversationViewModel.getConversation(_fullConversationId()) ??
            conversationViewModel.getConversation(conversationID);
    final lastSeq = int.tryParse(
          conversation?.lastMessage?.seq?.trim() ??
              previewLastMessage?.seq?.trim() ??
              '',
        ) ??
        0;
    final firstUnreadSeq = FirstUnreadJump.resolveLockedFirstUnreadSeq(
      unreadCount: unreadCount,
      isGroup: isGroup,
      groupReadSequence: conversation?.groupReadSequence,
      lastMessageSeq: lastSeq > 0 ? lastSeq : null,
    );
    globalModel.lockEntryUnreadForTongue(
      conversationID: conversationID,
      unreadCount: unreadCount,
      firstUnreadSeq: firstUnreadSeq,
      notify: notify,
    );
    if (isGroup && (firstUnreadSeq == null || firstUnreadSeq <= 0)) {
      unawaited(
        _refreshLockedFirstUnreadSeq(
          conversationID: conversationID,
          unreadCount: unreadCount,
        ),
      );
    }
  }

  String _fullConversationId() {
    if (conversationType == ConvType.group) {
      if (conversationID.startsWith('group_')) {
        return conversationID;
      }
      return 'group_$conversationID';
    }
    if (conversationID.startsWith('c2c_')) {
      return conversationID;
    }
    return 'c2c_$conversationID';
  }

  Future<void> _refreshLockedFirstUnreadSeq({
    required String conversationID,
    required int unreadCount,
  }) async {
    final updateSequence =
        globalModel.captureEntryUnreadSequenceUpdate(conversationID);
    final openedModel = model;
    try {
      final id = _fullConversationId();
      final fresh = await serviceLocator<ConversationService>().getConversation(
        conversationID: id,
      );
      if (fresh == null ||
          !identical(model, openedModel) ||
          !TUIChatGlobalModel.isSameConversationIdForHistory(
              openedModel?.conversationID ?? '', conversationID) ||
          !TUIChatGlobalModel.isSameConversationIdForHistory(
              globalModel.currentSelectedConv, conversationID)) {
        return;
      }
      final lastSeq = int.tryParse(fresh.lastMessage?.seq?.trim() ?? '') ?? 0;
      final seq = FirstUnreadJump.resolveLockedFirstUnreadSeq(
        unreadCount: unreadCount,
        isGroup: true,
        groupReadSequence: fresh.groupReadSequence,
        lastMessageSeq: lastSeq > 0 ? lastSeq : null,
      );
      if (seq == null || seq <= 0) {
        return;
      }
      updateSequence(seq);
    } catch (_) {}
  }

  String? _oldestLoadedMessageID() {
    final messages = globalModel.getMessageList(conversationID);
    if (messages == null || messages.isEmpty) {
      return null;
    }
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final msgID = message.msgID?.trim() ?? '';
      if (msgID.isNotEmpty) {
        return msgID;
      }
    }
    return null;
  }

  int? _oldestLoadedMessageSeq() {
    final messages = globalModel.getMessageList(conversationID);
    if (messages == null || messages.isEmpty) {
      return null;
    }
    for (var i = messages.length - 1; i >= 0; i--) {
      final seq = int.tryParse(messages[i].seq?.trim() ?? '');
      if (seq != null && seq > 0) {
        return seq;
      }
    }
    return null;
  }

  int _loadedRealMessageCount() {
    final messages = globalModel.getMessageList(conversationID);
    if (messages == null || messages.isEmpty) {
      return 0;
    }
    var count = 0;
    for (final message in messages) {
      if (message.elemType != 11) {
        count++;
      }
    }
    return count;
  }

  Future<void> _ensureInitialUnreadWindowLoaded(int unreadCount) async {
    if (unreadCount <= 0) {
      return;
    }

    // 入口大量未读：首屏只拉普通最新窗，提示条展示冻结未读数。
    // 禁止按 unreadCount+12 预拉（万级未读会卡死/OOM）；首条未读靠点击 around 跳转。
    final requiredRealCount = HistoryMessageDartConstant.initialOpenFetchCount;
    const maxBatchCount = 80;
    final maxPaginationRounds = 3;
    // A local-only route may enter this helper through a late unread update.
    // Keep that route SDK-local: cloud verification belongs to the shared
    // ConversationHistorySyncCoordinator after the first frame.
    final localOnlyOpen = model!.localOnlyInitialOpen;
    var safety = 0;

    final existing = globalModel.getMessageList(conversationID);
    if (_loadedRealMessageCount() >= requiredRealCount) return;
    if (!localOnlyOpen && existing != null && existing.isNotEmpty) {
      final latestMsgID = existing.first.msgID?.trim() ?? '';
      if (latestMsgID.isNotEmpty) {
        await model!.loadChatRecord(
          count: maxBatchCount,
          lastMsgID: latestMsgID,
          direction: LoadDirection.latest,
        );
      }
    }

    while (_loadedRealMessageCount() < requiredRealCount &&
        safety < maxPaginationRounds) {
      safety++;
      final beforeCount = _loadedRealMessageCount();
      final remaining = requiredRealCount - beforeCount;
      final batchCount = remaining <= maxBatchCount ? remaining : maxBatchCount;

      final oldestMsgID = _oldestLoadedMessageID();
      final oldestSeq = _oldestLoadedMessageSeq();
      if (oldestMsgID == null && (oldestSeq == null || oldestSeq <= 0)) {
        final localLoaded = await model!.loadChatRecord(
          count: batchCount,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
        );
        final afterLocalCount = _loadedRealMessageCount();
        if (afterLocalCount >= requiredRealCount) {
          break;
        }
        if (!localOnlyOpen &&
            (!localLoaded || afterLocalCount == beforeCount)) {
          final cloudLoaded = await model!.loadChatRecord(
            count: batchCount,
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          );
          final afterCloudCount = _loadedRealMessageCount();
          if (afterCloudCount >= requiredRealCount) {
            break;
          }
          if (!cloudLoaded || afterCloudCount == beforeCount) {
            break;
          }
        }
      } else {
        await model!.loadChatRecord(
          count: batchCount,
          lastMsgID: oldestMsgID,
          lastMsgSeq: oldestSeq ?? -1,
          getType: localOnlyOpen
              ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
              : null,
          direction: LoadDirection.previous,
        );
      }

      final afterCount = _loadedRealMessageCount();
      if (afterCount <= beforeCount) {
        break;
      }
      if (!model!.haveMoreData && afterCount < requiredRealCount) {
        break;
      }
    }

    // 拉取完成后再次写回入口未读数，防止 markRead 或会话刷新把 UI 锚点清掉。
    _lockEntryUnreadWithFrozenSeq(
      conversationID: conversationID,
      unreadCount: unreadCount,
    );
    globalModel.setMessageListPosition(
      conversationID,
      HistoryMessagePosition.bottom,
      notify: false,
    );
  }

  bool _reusePreparedInitialHistory(int fetchCount) {
    if (!ConversationPreviewHistorySync.canReusePreparedInitialWindow(
      globalModel: globalModel,
      conversationKey: conversationID,
      preview: previewLastMessage,
    )) {
      return false;
    }
    final cached = globalModel.rawMessageList(conversationID)!;
    globalModel.markInitialHistoryLoaded(conversationID);
    model!.syncHaveMoreDataFromCachedHistory(
      mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
          cached.length >= fetchCount,
    );
    return true;
  }

  void _loadData({
    V2TimMessage? initFindingMsg,
    MessageAnchor? searchJumpAnchor,
  }) {
    final count = HistoryMessageDartConstant.getCount;
    searchJumpAnchor ??= initFindingMsg == null
        ? null
        : MessageAnchor(
            conversationID: conversationID,
            convType: conversationType.index,
            msgID: initFindingMsg.msgID,
            localID: initFindingMsg.id,
            seq: initFindingMsg.seq,
            timestamp: initFindingMsg.timestamp,
            sender: initFindingMsg.sender,
            elemType: initFindingMsg.elemType);
    final isSearchJump = searchJumpAnchor != null;
    final searchRequest =
        isSearchJump ? globalModel.beginSearchJump(conversationID) : null;
    bool isCurrentSearch() =>
        searchRequest == null ||
        globalModel.isCurrentSearchJumpRequest(conversationID, searchRequest);
    final localOnlyPlainOpen =
        model!.localOnlyInitialOpen && !isSearchJump && initFindingMsg == null;
    if (!isSearchJump) {
      globalModel.clearSearchJumpStatus(conversationID);
    }
    final needUnreadSync = !localOnlyPlainOpen &&
        !isSearchJump &&
        initFindingMsg == null &&
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          conversationType,
          initialUnreadCount,
        );
    Future<void>(() async {
      final loadTrace = ChatOpenPerfLog.captureCurrent(
        conversationKey: conversationID,
      );
      if (!isCurrentSearch()) return;
      final initialLoadGeneration =
          ChatHistoryRecoveryCoordinator.instance.beginInitialLoad(
        conversationID,
      );
      var shouldMarkRead = false;
      String messageListSignature(List<V2TimMessage>? messages) {
        if (messages == null || messages.isEmpty) {
          return 'empty';
        }
        return messages.map((message) {
          final msgID = message.msgID?.trim() ?? '';
          if (msgID.isNotEmpty) return msgID;
          final id = message.id?.trim() ?? '';
          if (id.isNotEmpty) return id;
          final seq = message.seq?.trim() ?? '';
          if (seq.isNotEmpty) return 'seq_$seq';
          return message.timestamp?.toString() ?? '';
        }).join('|');
      }

      try {
        final target = initFindingMsg;
        if (!isSearchJump && target == null) {
          if (needUnreadSync && initialUnreadCount > 0) {
            await _ensureInitialUnreadWindowLoaded(initialUnreadCount);
            final loadedMessages = globalModel.getMessageList(conversationID);
            if (loadedMessages != null && loadedMessages.isNotEmpty) {
              // 大量未读入口先展示提示条，等用户主动查看后再上报已读。
              _lockEntryUnreadWithFrozenSeq(
                conversationID: conversationID,
                unreadCount: initialUnreadCount,
              );
              globalModel.setMessageListPosition(
                conversationID,
                HistoryMessagePosition.bottom,
                notify: true,
              );
              return;
            }
          }

          final rawCount = globalModel.rawMessageCount(conversationID);
          final currentPosition = globalModel.getMessageListPosition(
            conversationID,
          );
          if (rawCount > 0 &&
              currentPosition == HistoryMessagePosition.notShowLatest) {
            OutgoingVisibleProbe.log(
              'load_not_show_latest_wipe',
              conversationID: conversationID,
              extras: <String, Object?>{'rawCount': rawCount},
            );
            ChatOpenPerfLog.mark(
              'uikit_removeMessageList',
              conversationID: conversationID,
              extras: <String, Object?>{
                'reason': 'not_show_latest_wipe',
                'rawCount': rawCount,
              },
              trace: loadTrace,
            );
            // 搜索定位后若仍停留在历史窗口缓存，普通进入应回到最新。
            globalModel.removeMessageList(conversationID);
            globalModel.setMessageListPosition(
              conversationID,
              HistoryMessagePosition.bottom,
              notify: true,
            );
            model!.haveMoreData = false;
            model!.haveMoreLatestData = false;
          }

          if (localOnlyPlainOpen) {
            // The app-owned bootstrap is the only first-window owner. Give it
            // a tiny coalescing window, then let the page mount immediately.
            // A native SDK read can be slow on some conversations; waiting
            // 900ms and then another 3s here made route entry look frozen.
            await globalModel.awaitOpenHydrateInFlight(
              conversationID,
              timeout: const Duration(milliseconds: 80),
            );
            ChatOpenPerfLog.mark(
              'uikit_hydrate_wait_result',
              conversationID: conversationID,
              extras: <String, Object?>{
                'waitMs': 80,
                'hasInFlight':
                    globalModel.hasOpenHydrateInFlight(conversationID),
              },
              trace: loadTrace,
            );
            if (globalModel.hasOpenHydrateInFlight(conversationID)) {
              model!.syncHaveMoreDataFromCachedHistory(mayHaveOlder: true);
              ChatHistoryTrace.log(
                'chat_page_defer_open_hydrate_inflight',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'needUnreadSync': needUnreadSync,
                  'waitMs': 80,
                },
              );
              ChatOpenPerfLog.mark(
                'uikit_hydrate_deferred',
                conversationID: conversationID,
                extras: <String, Object?>{'waitMs': 80},
                trace: loadTrace,
              );
              return;
            }

            // App-owned ChatHistoryPeekBootstrap normally has already placed
            // the local snapshot into the global model. If this widget wins a
            // race before that task starts, perform one local SDK read here.
            // Never fall through to hydrateInitialHistoryPeekStyle or the
            // cloud branches below during the initial route open.
            var localMessages = globalModel.getMessageList(conversationID);
            final openResult = globalModel.openHydrateResultFor(conversationID);
            if ((localMessages == null || localMessages.isEmpty) &&
                openResult?.shouldSuppressOrdinaryLoad != true) {
              ChatOpenPerfLog.mark(
                'uikit_loadChatRecord_local_started',
                conversationID: conversationID,
                trace: loadTrace,
              );
              await model!.loadChatRecord(
                count: HistoryMessageDartConstant.initialOpenFetchCount,
                getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
              );
              localMessages = globalModel.getMessageList(conversationID);
              ChatOpenPerfLog.mark(
                'uikit_loadChatRecord_local_done',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'localCount': localMessages?.length ?? 0,
                },
                trace: loadTrace,
              );
            }
            final localCount = localMessages?.length ?? 0;
            // Local SDK is not proof of cloud continuity. Keep pagination
            // armed until the deferred cloud verification or an explicit
            // user pagination receives a terminal cloud result.
            // D-fix：若 warm scheduler 已经标 mayHaveOlder=false（SDK isFinished），
            // 沿用 false；否则保持原行为 true。
            final mayHaveOlder =
                globalModel.mayHaveOlderHistory(conversationID);
            globalModel.markLocalInitialHistoryVisible(conversationID);
            globalModel.markInitialHistoryMayHaveOlder(
              conversationID,
              mayHaveOlder: mayHaveOlder,
            );
            model!.syncHaveMoreDataFromCachedHistory(
              mayHaveOlder: mayHaveOlder,
            );
            globalModel.setMessageListPosition(
              conversationID,
              HistoryMessagePosition.bottom,
              notify: true,
            );
            shouldMarkRead = localCount > 0 && initialUnreadCount <= 0;
            ChatHistoryTrace.log(
              'chat_page_local_only_initial_done',
              conversationID: conversationID,
              extras: <String, Object?>{
                'localCount': localCount,
                'mayHaveOlder': mayHaveOlder,
              },
            );
            return;
          }

          // Non-local/search/unread entry paths retain their existing bounded
          // coordination because they have explicit positioning semantics.
          await globalModel.awaitOpenHydrateInFlight(
            conversationID,
            timeout: const Duration(milliseconds: 900),
          );
          if (globalModel.hasOpenHydrateInFlight(conversationID)) {
            // A Dart timeout does not cancel the native SDK request. Do not
            // create a second logical first-window owner after the bounded
            // wait; the app bootstrap will publish its result and the normal
            // post-open recovery path may retry only after the flight ends.
            await globalModel.awaitOpenHydrateInFlight(
              conversationID,
              timeout: const Duration(milliseconds: 3000),
            );
            if (globalModel.hasOpenHydrateInFlight(conversationID)) {
              ChatHistoryTrace.log(
                'chat_page_defer_open_hydrate_inflight',
                conversationID: conversationID,
                extras: <String, Object?>{'needUnreadSync': needUnreadSync},
              );
              return;
            }
          }

          model!.haveMoreData = false;
          model!.haveMoreLatestData = false;

          final fetchCount = HistoryMessageDartConstant.initialOpenFetchCount;
          if (_reusePreparedInitialHistory(fetchCount)) {
            ChatHistoryTrace.log(
              'chat_page_reuse_prepared_window',
              conversationID: conversationID,
              extras: <String, Object?>{
                'rawCount': globalModel.rawMessageCount(conversationID),
                'mayHaveOlder': globalModel.mayHaveOlderHistory(conversationID),
              },
            );
            shouldMarkRead = true;
            return;
          }

          ChatHistoryTrace.log(
            'chat_page_hydrate_begin',
            conversationID: conversationID,
            extras: <String, Object?>{
              'modelConv': model!.conversationID,
              'needUnreadSync': needUnreadSync,
              'entryUnread': initialUnreadCount,
              'rawCount': globalModel.rawMessageCount(conversationID),
              'modelRawCount': globalModel.rawMessageCount(
                model!.conversationID,
              ),
              ...ChatHistoryTrace.windowSummary(
                globalModel.messageListMap[conversationID] ??
                    globalModel.messageListMap[model!.conversationID],
                prefix: 'before',
              ),
            },
          );

          // 与会话 Peek 相同：每次进页按预览窗口 replace 首屏（不信任旧暖缓存）。
          final peekRefreshed = await model!.hydrateInitialHistoryPeekStyle(
            count: fetchCount,
            plainOpen: true,
          );
          final afterPeekCount = globalModel.rawMessageCount(conversationID);
          ChatHistoryTrace.log(
            'chat_page_hydrate_end',
            conversationID: conversationID,
            extras: <String, Object?>{
              'peekRefreshed': peekRefreshed,
              'afterPeekCount': afterPeekCount,
              'willFallthroughLoad': peekRefreshed && afterPeekCount == 0,
              'modelAfterCount': globalModel.rawMessageCount(
                model!.conversationID,
              ),
              ...ChatHistoryTrace.windowSummary(
                globalModel.messageListMap[conversationID] ??
                    globalModel.messageListMap[model!.conversationID],
                prefix: 'after',
              ),
            },
          );
          if (peekRefreshed && afterPeekCount > 0) {
            // 首屏 replace 后务必恢复上拉开关，避免 haveMoreData 被误留 false。
            model!.syncHaveMoreDataFromCachedHistory(
              mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
                  afterPeekCount >=
                      HistoryMessageDartConstant.initialOpenFetchCount ||
                  model!.haveMoreData,
            );
            shouldMarkRead = true;
            return;
          }
        }
        if (isSearchJump && searchJumpAnchor != null) {
          // Keep a local non-null reference across the await below. Dart
          // cannot promote the captured variable after an async suspension.
          final anchor = searchJumpAnchor;
          globalModel.setSearchJumpStatus(
            conversationID,
            SearchJumpStatus.loading,
            requestID: searchRequest,
            notify: true,
          );
          OutgoingVisibleProbe.log(
            'search_jump_preserve_window',
            conversationID: conversationID,
          );
          globalModel.setMessageListPosition(
            conversationID,
            HistoryMessagePosition.notShowLatest,
            notify: false,
          );
          final loaded = await model!
              .loadListForSpecificMessage(
                anchor: anchor,
                targetMessage: target,
                searchJumpRequest: searchRequest,
              )
              .timeout(const Duration(seconds: 12));
          if (!isCurrentSearch()) return;
          final messages = globalModel.getMessageList(conversationID);
          if (loaded && messages != null && anchor.isPresentIn(messages)) {
            globalModel.setSearchJumpStatus(
              conversationID,
              SearchJumpStatus.positioning,
              requestID: searchRequest,
              notify: true,
            );
            shouldMarkRead = false;
            return;
          }
          globalModel.setSearchJumpStatus(
              conversationID, SearchJumpStatus.failed,
              requestID: searchRequest, notify: true);
          TIMUIKitClass.onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t("无法定位到原消息，请重试"),
            infoCode: 6660401,
          ));
          return;
        } else if (target != null) {
          final fallbackAnchor = MessageAnchor(
            conversationID: conversationID,
            convType: conversationType.index,
            msgID: target.msgID?.trim().isEmpty ?? true
                ? null
                : target.msgID?.trim(),
            localID:
                target.id?.trim().isEmpty ?? true ? null : target.id?.trim(),
            seq: target.seq?.trim().isEmpty ?? true ? null : target.seq?.trim(),
            timestamp: target.timestamp,
            sender: target.sender ?? target.userID,
            elemType: target.elemType,
          );
          final loaded = await model!.loadListForSpecificMessage(
            anchor: fallbackAnchor,
            targetMessage: target,
          );
          final messages = globalModel.getMessageList(conversationID);
          if (loaded && messages != null && messages.isNotEmpty) {
            shouldMarkRead = true;
            return;
          }
        }
        final fetchCount = needUnreadSync && initialUnreadCount > 0
            ? math.min(
                math.max(
                  initialUnreadCount + 12,
                  HistoryMessageDartConstant.initialOpenFetchCount,
                ),
                80,
              )
            : globalModel.hasInitialHistoryLoaded(conversationID)
                ? count
                : HistoryMessageDartConstant.initialOpenFetchCount;
        final beforeLocalSignature = messageListSignature(
          globalModel.getMessageList(conversationID),
        );
        final localLoaded = await model!.loadChatRecord(
          count: fetchCount,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
        );
        final localMessages = globalModel.getMessageList(conversationID);
        final afterLocalSignature = messageListSignature(localMessages);
        final localChanged = afterLocalSignature != beforeLocalSignature;
        final localCount = localMessages?.length ?? 0;
        final localWindowComplete = localLoaded &&
            localMessages != null &&
            localMessages.isNotEmpty &&
            localCount >= fetchCount;
        final memoryWindowNeedsReconciliation =
            globalModel.memoryWindowNeedsReconciliation(conversationID);
        if (localWindowComplete &&
            localChanged &&
            !memoryWindowNeedsReconciliation) {
          globalModel.markInitialHistoryLoaded(conversationID);
          shouldMarkRead = true;
          return;
        }
        if (localMessages != null && localMessages.isNotEmpty) {
          final cloudLoaded = await model!.loadChatRecord(
            count: fetchCount,
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          );
          final cloudMessages = globalModel.getMessageList(conversationID);
          if (cloudLoaded &&
              (!globalModel.memoryWindowNeedsReconciliation(conversationID) ||
                  globalModel.memoryWindowReconciliationCovered(
                    conversationID,
                    cloudMessages,
                  ))) {
            globalModel.markInitialHistoryLoaded(conversationID);
            globalModel.clearMemoryWindowReconciliation(conversationID);
          }
          shouldMarkRead = cloudMessages != null && cloudMessages.isNotEmpty;
          return;
        }
        final cloudLoaded = await model!.loadChatRecord(
          count: fetchCount,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
        );
        final cloudMessages = globalModel.getMessageList(conversationID);
        if (cloudLoaded &&
            (!globalModel.memoryWindowNeedsReconciliation(conversationID) ||
                globalModel.memoryWindowReconciliationCovered(
                  conversationID,
                  cloudMessages,
                ))) {
          globalModel.markInitialHistoryLoaded(conversationID);
          globalModel.clearMemoryWindowReconciliation(conversationID);
        }
        if (cloudLoaded && cloudMessages != null && cloudMessages.isNotEmpty) {
          shouldMarkRead = true;
        } else if (!isSearchJump &&
            target == null &&
            !needUnreadSync &&
            (cloudMessages == null || cloudMessages.isEmpty) &&
            !model!.haveMoreData) {
          final selected = model!.conversationViewModel.selectedConversation;
          final selectedMatches = selected != null &&
              TUIChatSeparateViewModel.selectedConversationMatchesChatId(
                conversationID: conversationID,
                selectedUserID: selected.userID,
                selectedGroupID: selected.groupID,
                selectedConversationID: selected.conversationID,
              );
          final previewLast = selectedMatches ? selected.lastMessage : null;
          final previewMsgId = previewLast?.msgID?.trim() ?? '';
          final hasListSideEvidence =
              initialUnreadCount > 0 || previewLast != null;
          // 列表侧有 lastMessage/未读时勿误标空历史，留给 Chat post-open 补拉。
          if (hasListSideEvidence) {
            // 本地 tip（ce_/localGroupTips）不能当作历史种子，否则会触发 tip
            // 整库回灌，把空会话铺满入退群灰字。
            final previewIsLocalTip = previewLast != null &&
                HistoryPaginationAnchor.isLocalInjectedMessage(previewLast);
            if (previewLast != null &&
                !previewIsLocalTip &&
                globalModel.rawMessageCount(conversationID) == 0) {
              globalModel.setMessageList(
                conversationID,
                TUIChatGlobalModel.mergeHistoricalWithInMemory(
                  existing: globalModel.messageListMap[conversationID],
                  fetched: <V2TimMessage>[previewLast],
                ),
                needResetNewMessageCount: false,
                replace: true,
              );
              globalModel.markInitialHistoryLoaded(conversationID);
              shouldMarkRead = true;
              ChatHistoryTrace.log(
                'seed_preview_last_message',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'previewMsgId': previewMsgId,
                  'entryUnread': initialUnreadCount,
                },
              );
            } else if (previewIsLocalTip &&
                globalModel.rawMessageCount(conversationID) == 0) {
              globalModel.markInitialHistoryLoaded(conversationID);
              ChatHistoryTrace.log(
                'skip_seed_preview_local_tip',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'previewMsgId': previewMsgId,
                  'entryUnread': initialUnreadCount,
                },
              );
            } else {
              ChatHistoryTrace.log(
                'skip_mark_empty_loaded_has_preview',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'entryUnread': initialUnreadCount,
                  'previewMsgId': previewMsgId,
                  'localCount': localCount,
                  'cloudLoaded': cloudLoaded,
                },
              );
            }
          } else {
            // 空会话也必须结束首轮历史加载，否则消息区会一直显示 loading。
            globalModel.markInitialHistoryLoaded(conversationID);
            ChatHistoryTrace.log(
              'mark_empty_history_loaded',
              conversationID: conversationID,
              extras: <String, Object?>{
                'localCount': localCount,
                'cloudLoaded': cloudLoaded,
              },
            );
          }
        }
      } catch (error) {
        if (!isSearchJump) rethrow;
        if (!isCurrentSearch()) return;
        // This also invalidates late around-window completions in the model.
        globalModel.setSearchJumpStatus(conversationID, SearchJumpStatus.failed,
            requestID: searchRequest, notify: true);
        ChatHistoryTrace.log('search_jump_load_failed',
            conversationID: conversationID,
            extras: {'request': searchRequest, 'error': error.toString()});
        TIMUIKitClass.onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("消息定位加载失败，请重试"),
          infoCode: 6660401,
        ));
      } finally {
        ChatHistoryRecoveryCoordinator.instance.markInitialLoadComplete(
          conversationID,
          generation: initialLoadGeneration,
        );
        if (shouldMarkRead &&
            !needUnreadSync &&
            !globalModel.hasLockedEntryUnread) {
          await model!.markMessageAsRead(force: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider.value(value: globalModel),
        ChangeNotifierProvider.value(value: chatUiStateStore),
        ChangeNotifierProvider.value(value: themeViewModel),
        ChangeNotifierProvider.value(value: groupListenerModel),
        ChangeNotifierProvider.value(value: friendShipViewModel),
        Provider(create: (_) => const TIMUIKitChatConfig()),
        ...?providers,
      ],
      child: child,
      builder: (context, w) => builder(context, model!, w),
    );
  }
}
