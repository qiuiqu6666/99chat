import 'package:tencent_cloud_chat_uikit/ui/utils/chat_input_bar_metrics.dart';
import 'dart:async';
import 'dart:math';

import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_setting_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_bubble_text_color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/optimize_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_reply_quote_card.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/custom_sticker_panel.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/DefaultSpecialTextSpanBuilder.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/emoji_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_forbidden_input_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_send_sound_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/input_panel_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';
import 'package:tim_ui_kit_sticker_plugin/tim_ui_kit_sticker_plugin.dart';

class TIMUIKitTextFieldLayoutNarrow extends StatefulWidget {
  /// 与 ExtendedTextField（fontSize 16、vertical padding 8、isDense）单行内容区一致。
  /// 字号不缩；只靠略减上下留白降低底栏总高。
  static const double singleLineInputHeight = ChatInputBarMetrics.inputHeight;

  /// 输入行上下留白（原 5，略收以降低底栏总高）。
  static const double inputBarVerticalPadding = ChatInputBarMetrics.verticalPadding;

  /// sticker panel customization
  final CustomStickerPanel? customStickerPanel;

  final VoidCallback onEmojiSubmitted;
  final Function(int, String) onCustomEmojiFaceSubmitted;
  final Function(String, bool) handleSendEditStatus;
  final VoidCallback backSpaceText;
  final ValueChanged<String> addStickerToText;

  final ValueChanged<String> handleAtText;

  /// Whether to use the default emoji
  final bool isUseDefaultEmoji;

  final bool isUseTencentCloudChatPackageOldKeys;

  final TUIChatSeparateViewModel model;

  /// background color
  final Color? backgroundColor;

  /// control input field behavior
  final TIMUIKitInputTextFieldController? controller;

  /// config for more panel
  final MorePanelConfig? morePanelConfig;

  final String languageType;

  final TextEditingController textEditingController;

  /// conversation id
  final String conversationID;

  /// conversation type
  final ConvType conversationType;

  final FocusNode focusNode;

  /// show more panel
  final bool showMorePanel;

  /// hint text for textField widget
  final String? hintText;

  final int? currentCursor;

  final ValueChanged<int?> setCurrentCursor;

  final VoidCallback onCursorChange;

  /// show send audio icon
  final bool showSendAudio;

  final VoidCallback handleSoftKeyBoardDelete;

  /// on text changed
  final void Function(String)? onChanged;

  final V2TimMessage? repliedMessage;

  final void Function(String)? onDeleteText;

  /// show send emoji icon
  final bool showSendEmoji;

  final VoidCallback onSubmitted;

  final VoidCallback goDownBottom;

  /// 键盘 viewInsets 变化时同步消息列表，与输入栏同帧跟手。
  final VoidCallback? onKeyboardGeometryChanged;

  final List<CustomEmojiFaceData> customEmojiStickerList;

  final List<CustomStickerPackage> stickerPackageList;

  /// 禁言等不可发言时的提示文案；非空时隐藏输入框与功能按钮。
  final String? forbiddenText;
  final bool isComposingText;

  const TIMUIKitTextFieldLayoutNarrow(
      {super.key,
      this.customStickerPanel,
      required this.onEmojiSubmitted,
      required this.onCustomEmojiFaceSubmitted,
      required this.backSpaceText,
      required this.addStickerToText,
      required this.isUseDefaultEmoji,
      this.isUseTencentCloudChatPackageOldKeys = false,
      required this.languageType,
      required this.textEditingController,
      this.morePanelConfig,
      required this.conversationID,
      required this.conversationType,
      required this.focusNode,
      this.currentCursor,
      required this.setCurrentCursor,
      required this.onCursorChange,
      required this.model,
      this.backgroundColor,
      this.onChanged,
      this.onDeleteText,
      required this.handleSendEditStatus,
      required this.handleAtText,
      required this.handleSoftKeyBoardDelete,
      this.repliedMessage,
      required this.onSubmitted,
      required this.goDownBottom,
      this.onKeyboardGeometryChanged,
      required this.showSendAudio,
      required this.showSendEmoji,
      required this.showMorePanel,
      this.hintText,
      required this.customEmojiStickerList,
      this.controller,
      required this.stickerPackageList,
      this.forbiddenText,
      this.isComposingText = false});

  @override
  State<TIMUIKitTextFieldLayoutNarrow> createState() =>
      TIMUIKitTextFieldLayoutNarrowState();
}

class TIMUIKitTextFieldLayoutNarrowState
    extends TIMUIKitState<TIMUIKitTextFieldLayoutNarrow>
    implements TIMUIKitNarrowLayoutControllerDelegate {
  final TUISettingModel settingModel = serviceLocator<TUISettingModel>();

  double? _lastBottomHeight;
  bool _bottomHeightRebuildScheduled = false;
  KeyboardViewportTransitionCoordinator? _keyboardCoordinator;

  bool get _isInputForbidden =>
      widget.forbiddenText != null && widget.forbiddenText!.isNotEmpty;

  @override
  void didUpdateWidget(TIMUIKitTextFieldLayoutNarrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detachNarrowState(this);
      widget.controller?.attachNarrowState(this);
    }
    final conversationChanged =
        oldWidget.conversationID != widget.conversationID ||
            oldWidget.conversationType != widget.conversationType;
    if (conversationChanged) {
      widget.focusNode.unfocus();
      _panel.resetAll();
      bottomPadding = null;
      widget.controller?.updateInputPanelOpen(false);
    }
    if (_isInputForbidden &&
        (showMore || showEmojiPanel || showSendSoundText || showKeyboard)) {
      widget.focusNode.unfocus();
      _applyPanelState(_panel.resetAll);
    }
  }

  final InputPanelController _panel = InputPanelController();
  bool showMoreButton = true;

  bool get showMore => _panel.showMore;
  set showMore(bool value) => _panel.showMore = value;
  bool get showSendSoundText => _panel.showSendSoundText;
  set showSendSoundText(bool value) => _panel.showSendSoundText = value;
  bool get showEmojiPanel => _panel.showEmojiPanel;
  set showEmojiPanel(bool value) => _panel.showEmojiPanel = value;
  bool get showKeyboard => _panel.showKeyboard;
  set showKeyboard(bool value) => _panel.showKeyboard = value;

  Function? setKeyboardHeight;
  double? bottomPadding;

  bool get isAnyPanelOpen =>
      _panel.isAnyPanelOpen(hasFocus: widget.focusNode.hasFocus);

  void _syncInputPanelOpenState() {
    widget.controller?.updateInputPanelOpen(isAnyPanelOpen);
  }

  void _applyPanelState(VoidCallback update) {
    void apply() {
      if (!mounted) {
        return;
      }
      setState(update);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncInputPanelOpenState();
          // 面板高度变化时也需要刷新聊天页遮罩区域。
          widget.controller?.notifyLayoutChanged();
        }
      });
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
  }

  /// 关闭表情 / 更多 / 语音面板，并切换到系统键盘。
  void _switchToKeyboard() {
    widget.onCursorChange();
    widget.goDownBottom();
    widget.focusNode.requestFocus();
    _applyPanelState(_panel.switchToKeyboard);
  }

  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    _keyboardCoordinator?.setInputHasFocus(widget.focusNode.hasFocus);
    if (!widget.focusNode.hasFocus && showKeyboard) {
      final effectiveInset = _keyboardCoordinator?.effectiveInset.value ?? 0;
      if (effectiveInset <= 0) {
        _applyPanelState(() {
          showKeyboard = false;
        });
      } else {
        _rebuildBottomHeight(immediate: true);
      }
    } else {
      _rebuildBottomHeight(immediate: widget.focusNode.hasFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.attachNarrowState(this);
    widget.textEditingController.addListener(_syncSendButtonFromController);
    widget.focusNode.addListener(_syncInputPanelOpenState);
    widget.focusNode.addListener(_onFocusChanged);
    _syncSendButtonFromController();
    if (widget.controller != null) {
      widget.controller?.addListener(
        () {
          final actionType = widget.controller?.actionType;
          if (actionType == ActionType.hideAllPanel) {
            hideAllPanel();
            widget.controller?.actionType = null;
          } else if (actionType == ActionType.hideAccessoryPanel) {
            hideAccessoryPanels();
            widget.controller?.actionType = null;
          }
        },
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncInputPanelOpenState();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = KeyboardTransitionScope.maybeOf(context) ??
        KeyboardViewportTransitionCoordinator.active;
    if (identical(next, _keyboardCoordinator)) {
      return;
    }
    _keyboardCoordinator?.inset.removeListener(_onKeyboardInsetChanged);
    _keyboardCoordinator?.effectiveInset.removeListener(_onKeyboardInsetChanged);
    _keyboardCoordinator = next;
    _keyboardCoordinator?.inset.addListener(_onKeyboardInsetChanged);
    _keyboardCoordinator?.effectiveInset.addListener(_onKeyboardInsetChanged);
    _keyboardCoordinator?.setInputHasFocus(widget.focusNode.hasFocus);
  }

  void _onKeyboardInsetChanged() {
    if (!mounted) {
      return;
    }
    final effectiveInset = _keyboardCoordinator?.effectiveInset.value ?? 0;
    if (effectiveInset <= 0 && !widget.focusNode.hasFocus && showKeyboard) {
      setState(() {
        showKeyboard = false;
      });
    }
    _rebuildBottomHeight(immediate: true);
  }

  void _rebuildBottomHeight({bool immediate = false}) {
    if (!mounted) {
      return;
    }
    void apply() {
      if (!mounted) {
        return;
      }
      final height = _getBottomHeight();
      if (_lastBottomHeight != null &&
          (height - _lastBottomHeight!).abs() < 0.5) {
        return;
      }
      _lastBottomHeight = height;
      setState(() {});
    }

    if (immediate) {
      apply();
      return;
    }

    if (_bottomHeightRebuildScheduled) {
      return;
    }
    _bottomHeightRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomHeightRebuildScheduled = false;
      apply();
    });
  }

  void _scheduleBottomHeightRebuild() {
    _rebuildBottomHeight();
  }

  @override
  void dispose() {
    _textChangeTimer?.cancel();
    widget.controller?.detachNarrowState(this);
    _keyboardCoordinator?.inset.removeListener(_onKeyboardInsetChanged);
    _keyboardCoordinator?.effectiveInset.removeListener(_onKeyboardInsetChanged);
    widget.textEditingController.removeListener(_syncSendButtonFromController);
    widget.focusNode.removeListener(_syncInputPanelOpenState);
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller?.updateInputPanelOpen(false);
    super.dispose();
  }

  bool get _useInlineSendButton =>
      isWebDevice() || isAndroidDevice() || isIosDevice();

  void _syncSendButtonFromController() {
    if (!_useInlineSendButton) {
      return;
    }
    final hasText = widget.textEditingController.text.isNotEmpty;
    final shouldShowMoreButton = !hasText;
    if (showMoreButton == shouldShowMoreButton) {
      return;
    }
    if (mounted) {
      setState(() {
        showMoreButton = shouldShowMoreButton;
      });
    }
  }

  void setSendButton() {
    _syncSendButtonFromController();
  }

  void _submitOutgoingMessage({required bool fromKeyboard}) {
    if (fromKeyboard) {
      widget.controller?.markKeyboardSendRetain();
    }

    widget.onSubmitted();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncSendButtonFromController();
      }
    });
  }

  void _handleKeyboardSend() {
    _submitOutgoingMessage(fromKeyboard: true);
  }

  void _handleInlineSendPressed() {
    _submitOutgoingMessage(fromKeyboard: false);
  }

  /// 关闭表情 / 更多 / 语音面板，保留系统键盘与输入焦点。
  void hideAccessoryPanels() {
    if (!_panel.isAnyAccessoryOpen) {
      return;
    }
    _applyPanelState(_panel.hideAccessoryPanels);
  }

  void hideAllPanel() {
    final shouldClose = isAnyPanelOpen;
    widget.setCurrentCursor(null);
    if (!mounted) {
      widget.focusNode.unfocus();
      widget.controller?.updateInputPanelOpen(false);
      return;
    }
    if (shouldClose) {
      // 先清面板状态再 unfocus，避免仍用缓存 keyboardHeight 占位。
      // 这里不能在 build/layout 阶段同步 setState，拍照入口会和路由切换抢同一帧。
      _applyPanelState(_panel.hideAllPanels);
      widget.controller?.updateInputPanelOpen(false);
    }
    widget.focusNode.unfocus();
    if (!shouldClose) {
      widget.controller?.updateInputPanelOpen(false);
    }
  }

  Widget _getBottomContainer(TUITheme theme) {
    final panelHeight = _accessoryPanelHeightWithSafeInset();
    if (showEmojiPanel) {
      return widget.customStickerPanel != null
          ? widget.customStickerPanel!(
              sendTextMessage: () {
                widget.onEmojiSubmitted();
                setSendButton();
              },
              sendFaceMessage: widget.onCustomEmojiFaceSubmitted,
              deleteText: () {
                widget.backSpaceText();
                setSendButton();
              },
              addText: (int unicode) {
                final newText = String.fromCharCode(unicode);
                widget.addStickerToText(newText);
                setSendButton();
                // handleSetDraftText();
              },
              addCustomEmojiText: ((String singleEmojiName) {
                String? emojiName = singleEmojiName.split('.png')[0];
                String compatibleEmojiName = emojiName;
                if (widget.isUseTencentCloudChatPackageOldKeys) {
                  compatibleEmojiName =
                      EmojiUtil.getCompatibleEmojiName(emojiName);
                }

                String newText = '[$compatibleEmojiName]';
                widget.addStickerToText(newText);
                setSendButton();
              }),
              defaultCustomEmojiStickerList: widget.isUseDefaultEmoji
                  ? TUIKitStickerConstData.emojiList
                  : [],
              height: panelHeight,
            )
          : StickerPanel(
              isWideScreen: false,
              height: panelHeight,
              sendTextMsg: () {
                widget.onEmojiSubmitted();
                setSendButton();
              },
              sendFaceMsg: widget.onCustomEmojiFaceSubmitted,
              deleteText: () {
                widget.backSpaceText();
                setSendButton();
              },
              addText: (int unicode) {
                final newText = String.fromCharCode(unicode);
                widget.addStickerToText(newText);
                setSendButton();
                // handleSetDraftText();
              },
              addCustomEmojiText: ((String singleEmojiName) {
                String? emojiName = singleEmojiName.split('.png')[0];
                String compatibleEmojiName = emojiName;
                if (widget.isUseTencentCloudChatPackageOldKeys) {
                  compatibleEmojiName =
                      EmojiUtil.getCompatibleEmojiName(emojiName);
                }

                String newText = '[$compatibleEmojiName]';
                widget.addStickerToText(newText);
                setSendButton();
              }),
              customStickerPackageList: widget.stickerPackageList,
              lightPrimaryColor: theme.lightPrimaryColor);
    }

    if (showMore) {
      return SizedBox(
        height: panelHeight,
        width: double.infinity,
        child: ColoredBox(
          color: theme.weakBackgroundColor ?? hexToColor("f5f5f6"),
          child: MorePanel(
              morePanelConfig: widget.morePanelConfig,
              conversationID: widget.conversationID,
              conversationType: widget.conversationType,
              onImageSent: widget.goDownBottom),
        ),
      );
    }

    if (showSendSoundText) {
      return SendSoundMessage(
        height: panelHeight,
        onDownBottom: widget.goDownBottom,
        conversationID: widget.conversationID,
        conversationType: widget.conversationType,
      );
    }

    return const SizedBox(height: 0);
  }

  static const double _accessoryPanelHeight = 248.0;
  static const Duration _accessoryPanelAnimDuration =
      Duration(milliseconds: 200);

  @override
  void syncLayoutFromViewInsets() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  /// 表情/更多等面板打开时由面板自身铺满底部安全区，避免 SafeArea 露出输入栏白底。
  double _accessorySafeBottomInset() {
    if (!_useAccessoryPanelAnimation) {
      return 0;
    }
    return MediaQuery.paddingOf(context).bottom;
  }

  double _accessoryPanelHeightWithSafeInset() =>
      _accessoryPanelHeight + _accessorySafeBottomInset();

  double _keyboardInsetBottom() {
    if (showMore || showEmojiPanel || showSendSoundText) {
      return 0;
    }
    return _keyboardCoordinator?.effectiveInset.value ??
        MediaQuery.viewInsetsOf(context).bottom;
  }

  double _getBottomHeight() {
    final keyboardInset = _keyboardInsetBottom();
    if (showMore || showEmojiPanel || showSendSoundText) {
      return _accessoryPanelHeightWithSafeInset();
    }
    if (keyboardInset > 0) {
      final source = _keyboardCoordinator?.effectiveSource.value;
      if (setKeyboardHeight != null &&
          (source == KeyboardInsetSource.flutterInset ||
              source == KeyboardInsetSource.nativeIme)) {
        setKeyboardHeight!(keyboardInset);
      }
      return keyboardInset;
    }
    return 0;
  }

  /// 表情 / 更多：固定高度 + 短动画；系统键盘：直接跟 viewInsets，不再叠 AnimatedContainer。
  bool get _useAccessoryPanelAnimation =>
      showEmojiPanel || showMore || showSendSoundText;

  Widget _buildBottomSpacer(TUITheme theme) {
    final height = max(_getBottomHeight(), 0.0);
    final child = _getBottomContainer(theme);
    if (_useAccessoryPanelAnimation) {
      return AnimatedContainer(
        duration: _accessoryPanelAnimDuration,
        curve: Curves.easeOutCubic,
        height: height,
        alignment: Alignment.topCenter,
        child: child,
      );
    }
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }

  void _openMore() {
    widget.controller?.markAccessoryPanelOpening();
    if (!showMore) {
      widget.focusNode.unfocus();
      widget.setCurrentCursor(null);
    }
    _applyPanelState(() {
      showKeyboard = false;
      showEmojiPanel = false;
      showSendSoundText = false;
      showMore = !showMore;
    });
  }

  void _openEmojiPanel() {
    widget.onCursorChange();
    if (showEmojiPanel) {
      _switchToKeyboard();
      return;
    }
    widget.controller?.markAccessoryPanelOpening();
    widget.focusNode.unfocus();
    _applyPanelState(() {
      showMore = false;
      showSendSoundText = false;
      showKeyboard = false;
      showEmojiPanel = true;
    });
  }

  Timer? _textChangeTimer;

  ValueChanged<String> _debounce(
    ValueChanged<String> fun, [
    Duration delay = const Duration(milliseconds: 30),
  ]) {
    return (String text) {
      _textChangeTimer?.cancel();
      _textChangeTimer = Timer(delay, () {
        if (!mounted) return;
        fun(text);
      });
    };
  }

  Widget _buildRepliedMessage(V2TimMessage? repliedMessage, TUITheme theme) {
    if (repliedMessage == null) {
      return const SizedBox.shrink();
    }
    return TIMUIKitInputReplyPreview(
      repliedMessage: repliedMessage,
      chatModel: widget.model,
      theme: theme,
      backgroundColor: widget.backgroundColor,
      onClose: () => widget.model.repliedMessage = null,
    );
  }

  /// 固定宽度槽位，避免发送后「发送」与「+」切换时输入栏横向抖动。
  Widget _buildTrailingActionButton({
    required TUITheme theme,
    required Color inputIconColor,
  }) {
    final moreButton = InkWell(
      onTap: () {
        _openMore();
        widget.goDownBottom();
      },
      child: PlatformUtils().isWeb
          ? Icon(Icons.add_circle_outline_outlined,
              color: hexToColor("5c6168"), size: 32)
          : SvgPicture.asset(
              'images/add.svg',
              package: 'tencent_cloud_chat_uikit',
              colorFilter: ColorFilter.mode(inputIconColor, BlendMode.srcIn),
              height: 26,
              width: 26,
            ),
    );
    final sendButton = SizedBox(
      height: 30.0,
      child: ElevatedButton(
        onPressed: _handleInlineSendPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor ?? const Color(0xFF1E90FF),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 30),
          shape: const StadiumBorder(),
        ),
        child: Text(
          TIM_t("发送"),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ),
    );

    if (_useInlineSendButton && widget.showMorePanel) {
      if (showMoreButton) {
        return moreButton;
      }
      return SizedBox(
        height: TIMUIKitTextFieldLayoutNarrow.singleLineInputHeight,
        child: sendButton,
      );
    }
    if (widget.showMorePanel && showMoreButton) {
      return moreButton;
    }
    if (_useInlineSendButton && !showMoreButton) {
      return sendButton;
    }
    return const SizedBox.shrink();
  }

  Widget _buildRightActionCluster({
    required TUITheme theme,
    required Color inputIconColor,
  }) {
    final trailing = _buildTrailingActionButton(
      theme: theme,
      inputIconColor: inputIconColor,
    );
    if (!widget.showSendEmoji) {
      return trailing;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: TIMUIKitTextFieldLayoutNarrow.singleLineInputHeight,
          child: Center(
            child: InkWell(
              onTap: () {
                _openEmojiPanel();
                widget.goDownBottom();
              },
              child: PlatformUtils().isWeb
                  ? Icon(
                      showEmojiPanel
                          ? Icons.keyboard_alt_outlined
                          : Icons.mood_outlined,
                      color: hexToColor("5c6168"),
                      size: 32,
                    )
                  : SvgPicture.asset(
                      showEmojiPanel
                          ? 'images/keyboard.svg'
                          : 'images/face.svg',
                      package: 'tencent_cloud_chat_uikit',
                      colorFilter:
                          ColorFilter.mode(inputIconColor, BlendMode.srcIn),
                      height: 26,
                      width: 26,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        trailing,
      ],
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;
    final inputBarColor = widget.backgroundColor ??
        theme.weakBackgroundColor ??
        hexToColor("f5f5f6");
    final inputFillColor = theme.inputFillColor ?? Colors.white;
    final inputTextStyle = MessageBubbleTextColor.messageInputTextStyle(
      fontSize: 16,
      color: theme.darkTextColor ?? Colors.black,
      lineHeight: widget.model.chatConfig.textHeight,
    );
    final inputHintStyle = MessageBubbleTextColor.messageInputHintStyle(
      fontSize: 16,
      color: theme.weakTextColor ?? const Color(0xffAEA4A3),
      lineHeight: widget.model.chatConfig.textHeight,
    );
    final inputIconColor =
        theme.darkTextColor ?? const Color.fromRGBO(68, 68, 68, 1);

    setKeyboardHeight ??= OptimizeUtils.debounce((height) {
      final source = _keyboardCoordinator?.effectiveSource.value;
      if (source == KeyboardInsetSource.flutterInset ||
          source == KeyboardInsetSource.nativeIme) {
        settingModel.keyboardHeight = height;
      }
    }, const Duration(seconds: 1));

    final debounceFunc = _debounce((value) {
      final composing = widget.textEditingController.value.composing;
      if (widget.textEditingController.text != value) {
        return;
      }
      if (composing.isValid && composing.start < composing.end) {
        return;
      }
      _syncSendButtonFromController();
      widget.handleAtText(value);
      widget.handleSendEditStatus(value, true);
      final isEmpty = value.isEmpty;
      if (isEmpty) {
        widget.handleSoftKeyBoardDelete();
      }
    }, const Duration(milliseconds: 80));

    return Column(
      children: [
        _buildRepliedMessage(widget.repliedMessage, theme),
        DecoratedBox(
          decoration: BoxDecoration(
            color: inputBarColor,
            border: Border(
              top: BorderSide(
                color: theme.weakDividerColor ?? const Color(0xFFEAEAEA),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            // 附件面板打开时关闭底部安全区，由面板背景延伸到屏幕底边。
            bottom: !_useAccessoryPanelAnimation,
            minimum: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isInputForbidden)
                  TIMUIKitForbiddenInputBar(
                    text: widget.forbiddenText!,
                    theme: theme,
                    backgroundColor: inputBarColor,
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical:
                          TIMUIKitTextFieldLayoutNarrow.inputBarVerticalPadding,
                      horizontal: 16,
                    ),
                    constraints: const BoxConstraints(
                      minHeight:
                          TIMUIKitTextFieldLayoutNarrow.singleLineInputHeight,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (PlatformUtils().isMobile && widget.showSendAudio)
                          SizedBox(
                            height: TIMUIKitTextFieldLayoutNarrow
                                .singleLineInputHeight,
                            child: Center(
                              child: InkWell(
                                onTap: () {
                                  if (showSendSoundText) {
                                    _switchToKeyboard();
                                    return;
                                  }
                                  widget.focusNode.unfocus();
                                  _applyPanelState(() {
                                    showEmojiPanel = false;
                                    showMore = false;
                                    showKeyboard = false;
                                    showSendSoundText = true;
                                  });
                                },
                                child: SvgPicture.asset(
                                  showSendSoundText
                                      ? 'images/keyboard.svg'
                                      : 'images/voice.svg',
                                  package: 'tencent_cloud_chat_uikit',
                                  colorFilter: ColorFilter.mode(
                                    inputIconColor,
                                    BlendMode.srcIn,
                                  ),
                                  height: 26,
                                  width: 26,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child: showSendSoundText
                              ? GestureDetector(
                                  onTap: _switchToKeyboard,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    height: TIMUIKitTextFieldLayoutNarrow
                                        .singleLineInputHeight,
                                    decoration: BoxDecoration(
                                      color: inputFillColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                )
                              : ExtendedTextField(
                                  style: inputTextStyle,
                                  maxLines: 4,
                                  minLines: 1,
                                  focusNode: widget.focusNode,
                                  onChanged: (value) {
                                    // Draft ownership must advance before an
                                    // async send/load can restore older text.
                                    widget.onChanged?.call(value);
                                    debounceFunc(value);
                                  },
                                  onTap: () {
                                    if (showEmojiPanel ||
                                        showMore ||
                                        showSendSoundText) {
                                      _switchToKeyboard();
                                    } else {
                                      widget.goDownBottom();
                                    }
                                  },
                                  keyboardType: TextInputType.text,
                                  textCapitalization: TextCapitalization.none,
                                  autocorrect: false,
                                  enableSuggestions: true,
                                  textInputAction: TextInputAction.send,
                                  // 走 onEditingComplete 而非 onSubmitted，避免 Flutter
                                  // TextInputAction.send 在 onSubmitted 后重建 IME 连接导致键盘抖动。
                                  onEditingComplete: _handleKeyboardSend,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      hintStyle: inputHintStyle,
                                      fillColor: inputFillColor,
                                      filled: true,
                                      isDense: true,
                                      hintText: widget.hintText ?? ''),
                                  controller: widget.textEditingController,
                                  specialTextSpanBuilder: widget.isComposingText
                                      ? null
                                      : PlatformUtils().isWeb
                                          ? null
                                          : DefaultSpecialTextSpanBuilder(
                                              isUseQQPackage: widget
                                                      .model
                                                      .chatConfig
                                                      .stickerPanelConfig
                                                      ?.useQQStickerPackage ??
                                                  true,
                                              isUseTencentCloudChatPackage: widget
                                                      .model
                                                      .chatConfig
                                                      .stickerPanelConfig
                                                      ?.useTencentCloudChatStickerPackage ??
                                                  true,
                                              isUseTencentCloudChatPackageOldKeys:
                                                  widget
                                                          .model
                                                          .chatConfig
                                                          .stickerPanelConfig
                                                          ?.useTencentCloudChatStickerPackageOldKeys ??
                                                      false,
                                              customEmojiStickerList:
                                                  widget.customEmojiStickerList,
                                              showAtBackground: true,
                                              checkHttpLink: false),
                                ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        _buildRightActionCluster(
                          theme: theme,
                          inputIconColor: inputIconColor,
                        ),
                      ],
                    ),
                  ),
                if (!_isInputForbidden) _buildBottomSpacer(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
