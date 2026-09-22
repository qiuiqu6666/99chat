import 'package:tencent_cloud_chat_demo/utils/navigation_routes.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_wide_modal_operation_key.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/wide_popup_layout.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/forward_message_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

enum MultiSelectForwardBlockReason {
  noSelection,
  sendFailed,
  vote,
  walletCard,
  contactCard,
}

@visibleForTesting
MultiSelectForwardBlockReason? resolveMultiSelectForwardBlockReason({
  required Iterable<V2TimMessage> messages,
  required bool Function(V2TimMessage message) isVoteMessage,
  required bool Function(V2TimMessage message) isWalletCardMessage,
  required bool Function(V2TimMessage message) isContactCardMessage,
}) {
  final selected = messages.toList(growable: false);
  if (selected.isEmpty) {
    return MultiSelectForwardBlockReason.noSelection;
  }
  for (final message in selected) {
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      return MultiSelectForwardBlockReason.sendFailed;
    }
    if (isVoteMessage(message)) {
      return MultiSelectForwardBlockReason.vote;
    }
    if (isWalletCardMessage(message)) {
      return MultiSelectForwardBlockReason.walletCard;
    }
    if (isContactCardMessage(message)) {
      return MultiSelectForwardBlockReason.contactCard;
    }
  }
  return null;
}

Future<void> showMultiSelectForwardBlockedDialog(
  BuildContext context,
  MultiSelectForwardBlockReason reason,
) async {
  if (AppHud.isActive || AppDialog.isNoticeVisible) return;
  final text = switch (reason) {
    MultiSelectForwardBlockReason.noSelection => TIM_t("请选择要操作的消息！"),
    MultiSelectForwardBlockReason.sendFailed => TIM_t("发送失败消息不支持转发！"),
    MultiSelectForwardBlockReason.vote => TIM_t("投票消息不支持转发！"),
    MultiSelectForwardBlockReason.walletCard => TIM_t("红包、转账消息不支持转发，请取消勾选后重试。"),
    MultiSelectForwardBlockReason.contactCard => TIM_t("个人名片不支持转发，请取消勾选后重试。"),
  };
  final hud = AppHud.begin(showDelay: Duration.zero);
  try {
    // Give the shared loading indicator time to appear before the notice.
    await Future<void>.delayed(AppHud.defaultMinVisible);
    await hud.end();
    if (context.mounted) {
      ToastUtils.toast(text, context: context);
    }
  } finally {
    await hud.end();
  }
}

class MultiSelectPanel extends TIMUIKitStatelessWidget {
  final int forwardMsgNumLimit = 30;

  final ConvType conversationType;

  MultiSelectPanel({Key? key, required this.conversationType})
      : super(key: key);

  bool _validateForwardSelection(
      BuildContext context, TUIChatSeparateViewModel model) {
    if (AppHud.isActive || AppDialog.isNoticeVisible) return false;
    final reason = resolveMultiSelectForwardBlockReason(
      messages: model.getSelectedMessageList(),
      isVoteMessage: model.isVoteMessage,
      isWalletCardMessage: model.isWalletCardMessage,
      isContactCardMessage: model.isContactCardMessage,
    );
    if (reason == null) {
      return true;
    }
    showMultiSelectForwardBlockedDialog(context, reason);
    return false;
  }

  _handleForwardMessage(BuildContext context, bool isMergerForward,
      TUIChatSeparateViewModel model) {
    if (!_validateForwardSelection(context, model)) return;

    // 逐条转发限制在 30 条以内
    if (!isMergerForward &&
        model.getSelectedMessageList().length > forwardMsgNumLimit) {
      _showForwardLimitDialog(context);
      return;
    }

    Navigator.push(
        context,
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop
            ? MaterialPageRoute(
                builder: (context) => ForwardMessageScreen(
                      model: model,
                      isMergerForward: isMergerForward,
                      conversationType: conversationType,
                    ))
            : NavigationRoutes.push(
                builder: (context) => ForwardMessageScreen(
                      model: model,
                      isMergerForward: isMergerForward,
                      conversationType: conversationType,
                    )));
  }

  // 弹出逐条转发超限的对话框
  Future<bool?> _showForwardLimitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(TIM_t("转发消息过多，暂不支持逐条转发")),
          actions: [
            CupertinoDialogAction(
              child: Text(TIM_t("确定")),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
            CupertinoDialogAction(
              child: Text(TIM_t("取消")),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  _handleForwardMessageWide(BuildContext context, bool isMergerForward,
      TUIChatSeparateViewModel model) {
    if (!_validateForwardSelection(context, model)) return;
    if (!isMergerForward &&
        model.getSelectedMessageList().length > forwardMsgNumLimit) {
      _showForwardLimitDialog(context);
      return;
    }
    final popupSize = WidePopupLayout.large(context);
    TUIKitWidePopup.showPopupWindow(
        operationKey: TUIKitWideModalOperationKey.forward,
        context: context,
        isDarkBackground: false,
        title: TIM_t("转发"),
        width: popupSize.width,
        height: popupSize.height,
        onCancel: () {},
        onConfirm: () {
          forwardMessageScreenKey.currentState?.handleForwardMessage();
        },
        confirmText: TIM_t("发送"),
        child: (onClose) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ForwardMessageScreen(
                model: model,
                key: forwardMessageScreenKey,
                onClose: onClose,
                isMergerForward: isMergerForward,
                conversationType: conversationType,
              ),
            ));
  }

  Widget _panelShell({
    required TUITheme theme,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.weakDividerColor ?? CommonColor.weakDividerColor,
          ),
        ),
        color: theme.selectPanelBgColor ?? theme.primaryColor,
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _actionItem({
    required TUITheme theme,
    required String iconAsset,
    required String label,
    required VoidCallback onPressed,
    double iconSize = 24,
    bool compact = false,
  }) {
    final labelColor =
        theme.selectPanelTextIconColor ?? theme.darkTextColor ?? Colors.black87;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 2, vertical: compact ? 2 : 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  iconAsset,
                  package: 'tencent_cloud_chat_uikit',
                  width: compact ? 20 : iconSize,
                  height: compact ? 20 : iconSize,
                  color: theme.selectPanelTextIconColor,
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: labelColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactActionBar({
    required BuildContext context,
    required TUITheme theme,
    required TUIChatSeparateViewModel model,
    required bool isDesktop,
  }) {
    return SizedBox(
      height: isDesktop
          ? null
          : TIMUIKitTextFieldLayoutNarrow.singleLineInputHeight +
              2 * TIMUIKitTextFieldLayoutNarrow.inputBarVerticalPadding +
              MediaQuery.paddingOf(context).bottom,
      child: _panelShell(
        theme: theme,
        padding: EdgeInsets.only(
          top: isDesktop ? 8 : 0,
          bottom: isDesktop ? 12 : 0,
          left: 8,
          right: 8,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: _actionItem(
                  theme: theme,
                  iconAsset: 'images/forward.png',
                  compact: !isDesktop,
                  label: TIM_t("逐条转发"),
                  onPressed: () {
                    if (isDesktop) {
                      _handleForwardMessageWide(context, false, model);
                    } else {
                      _handleForwardMessage(context, false, model);
                    }
                  },
                ),
              ),
              Expanded(
                child: _actionItem(
                  theme: theme,
                  iconAsset: 'images/merge_forward.png',
                  compact: !isDesktop,
                  label: TIM_t("合并转发"),
                  onPressed: () {
                    if (isDesktop) {
                      _handleForwardMessageWide(context, true, model);
                    } else {
                      _handleForwardMessage(context, true, model);
                    }
                  },
                ),
              ),
              Expanded(
                child: _actionItem(
                  theme: theme,
                  iconAsset: 'images/delete.png',
                  compact: !isDesktop,
                  label: TIM_t("删除"),
                  onPressed: () =>
                      _confirmDelete(context, theme, model, isDesktop),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    TUITheme theme,
    TUIChatSeparateViewModel model,
    bool isDesktop,
  ) {
    if (isDesktop) {
      TUIKitWidePopup.showSecondaryConfirmDialog(
        operationKey: TUIKitWideModalOperationKey.confirmDeleteMessages,
        context: context,
        text: TIM_t("确定删除已选消息"),
        theme: theme,
        onCancel: () {},
        onConfirm: () async {
          model.deleteSelectedMsg();
          model.updateMultiSelectStatus(false);
        },
      );
      return;
    }
    showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text(TIM_t("确定删除已选消息")),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, "cancel"),
            child: Text(TIM_t("取消")),
            isDefaultAction: false,
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                model.deleteSelectedMsg();
                model.updateMultiSelectStatus(false);
                Navigator.pop(context, "cancel");
              },
              child: Text(
                TIM_t("删除"),
                style: TextStyle(color: theme.cautionColor),
              ),
              isDefaultAction: false,
            )
          ],
        );
      },
    );
  }

  Widget _wideActionBar({
    required BuildContext context,
    required TUITheme theme,
    required TUIChatSeparateViewModel model,
  }) {
    return _panelShell(
      theme: theme,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _actionItem(
            theme: theme,
            iconAsset: 'images/forward.png',
            label: TIM_t("逐条转发"),
            iconSize: 26,
            onPressed: () => _handleForwardMessageWide(context, false, model),
          ),
          const SizedBox(width: 40),
          _actionItem(
            theme: theme,
            iconAsset: 'images/merge_forward.png',
            label: TIM_t("合并转发"),
            iconSize: 26,
            onPressed: () => _handleForwardMessageWide(context, true, model),
          ),
          const SizedBox(width: 40),
          _actionItem(
            theme: theme,
            iconAsset: 'images/delete.png',
            label: TIM_t("删除"),
            iconSize: 26,
            onPressed: () => _confirmDelete(context, theme, model, true),
          ),
          const SizedBox(width: 16),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 20,
            onPressed: () => model.updateMultiSelectStatus(false),
            icon: Icon(Icons.close, color: theme.darkTextColor, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;
    final TUIChatSeparateViewModel model =
        Provider.of<TUIChatSeparateViewModel>(context);
    final isDesktop =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 聊天窗口较窄时（分屏/小窗）用等分底栏，避免桌面版 Wrap 横向溢出。
        final useCompact = constraints.maxWidth < 520;
        if (useCompact) {
          return _compactActionBar(
            context: context,
            theme: theme,
            model: model,
            isDesktop: isDesktop,
          );
        }
        if (isDesktop) {
          return _wideActionBar(context: context, theme: theme, model: model);
        }
        return _compactActionBar(
          context: context,
          theme: theme,
          model: model,
          isDesktop: false,
        );
      },
    );
  }
}
