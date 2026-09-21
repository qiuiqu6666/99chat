import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_share_picker_page.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_windows_image_clipboard.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_img_trace.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_clipboard_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_media_navigation.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/forward_message_screen.dart';

/// 主窗承接独立小窗「更多」动作：前往消息 / 显示所有图片 / 删除。
class DesktopMediaPopoutHost {
  DesktopMediaPopoutHost._();

  static void Function(V2TimConversation conversation, MessageAnchor? anchor)?
      navigateToChat;

  static Future<dynamic> handleAction(Map<String, dynamic> args) async {
    final action = '${args['action'] ?? ''}'.trim();
    ChatImgTrace.log('[ChatImg] event=popout_host_action action=$action');
    if (action == 'copy') {
      return _copy(args);
    }
    final conversationID = '${args['conversationID'] ?? ''}'.trim();
    final typeIndex = args['conversationType'] is int
        ? args['conversationType'] as int
        : int.tryParse('${args['conversationType']}') ?? ConvType.c2c.index;
    if (action == 'forward') {
      return _forward(args, conversationID, typeIndex);
    }
    if (conversationID.isEmpty) {
      ChatImgTrace.log('[ChatImg] event=popout_host_action_skip empty_conv');
      return false;
    }
    final conversation = _conversationFor(conversationID, typeIndex);
    if (action == 'goToMessage') {
      navigateToChat?.call(conversation, _anchorFor(args, conversation));
      return true;
    }
    if (action == 'showAllImages') {
      navigateToChat?.call(conversation, null);
      final context = AppNavigator.context;
      if (context == null || !context.mounted) {
        return false;
      }
      await pushConversationMediaFilePage(context, conversation: conversation);
      return true;
    }
    if (action == 'delete') {
      final msgID = '${args['messageID'] ?? ''}'.trim();
      if (msgID.isEmpty) {
        return false;
      }
      final model = TUIChatSeparateViewModel();
      model.conversationID = conversationID;
      model.conversationType =
          typeIndex == ConvType.group.index ? ConvType.group : ConvType.c2c;
      await model.deleteMsg(msgID);
      return true;
    }
    return false;
  }

  static Future<bool> _copy(Map<String, dynamic> args) async {
    final local = '${args['localPath'] ?? ''}'.trim();
    try {
      Uint8List? bytes;
      if (local.isNotEmpty && File(local).existsSync()) {
        bytes = Uint8List.fromList(await File(local).readAsBytes());
      } else {
        final url = '${args['url'] ?? ''}'.trim();
        if (url.isEmpty) {
          ToastUtils.toast(TIM_t('复制失败'));
          return false;
        }
        final resolved = MediaUrlResolver.resolve(url) ?? url;
        final response = await Dio().get<List<int>>(
          resolved,
          options: Options(
            responseType: ResponseType.bytes,
            headers: MediaUrlResolver.authHeadersFor(resolved),
          ),
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          ToastUtils.toast(TIM_t('复制失败'));
          return false;
        }
        bytes = Uint8List.fromList(data);
      }
      var ok = await copyBytesToWindowsImageClipboard(bytes);
      if (!ok && local.isNotEmpty && File(local).existsSync()) {
        ok = await copyDesktopMediaFile(local);
      }
      ToastUtils.toast(ok ? TIM_t('已复制') : TIM_t('复制失败'));
      ChatImgTrace.log('[ChatImg] event=popout_host_copy ok=$ok');
      return ok;
    } catch (error) {
      ChatImgTrace.log('[ChatImg] event=popout_host_copy_error error=$error');
      ToastUtils.toast(TIM_t('复制失败'));
      return false;
    }
  }

  static Future<bool> _forward(
    Map<String, dynamic> args,
    String conversationID,
    int typeIndex,
  ) async {
    final context = AppNavigator.context;
    if (context == null || !context.mounted) {
      ToastUtils.toast(TIM_t('转发失败'));
      return false;
    }
    try {
      appWindow.show();
    } catch (_) {}
    final convType =
        typeIndex == ConvType.group.index ? ConvType.group : ConvType.c2c;
    if (conversationID.isNotEmpty) {
      final msgID = '${args['messageID'] ?? ''}'.trim();
      final model = TUIChatSeparateViewModel();
      model.conversationID = conversationID;
      model.conversationType = convType;
      model.updateMultiSelectStatus(true);
      final found = _findMessage(model, msgID);
      if (found != null) {
        model.setMessageItemChecked(found, true);
      }
      if (model.getSelectedMessageList().isNotEmpty) {
        ChatImgTrace.log('[ChatImg] event=popout_host_forward mode=message');
        unawaited(
          _showWideDialog<void>(
            context: context,
            title: TIM_t('转发'),
            confirmText: TIM_t('发送'),
            onConfirm: () {
              forwardMessageScreenKey.currentState?.handleForwardMessage();
            },
            body: (dialogContext, close) {
              return ForwardMessageScreen(
                key: forwardMessageScreenKey,
                conversationType: convType,
                model: model,
                onClose: close,
              );
            },
          ),
        );
        return true;
      }
    }
    ChatImgTrace.log('[ChatImg] event=popout_host_forward mode=share_picker');
    unawaited(_forwardAsImage(context, args));
    return true;
  }

  static V2TimMessage? _findMessage(
    TUIChatSeparateViewModel model,
    String msgID,
  ) {
    if (msgID.isEmpty) {
      return null;
    }
    for (final item in model.getOriginMessageList()) {
      if ((item.msgID ?? '').trim() == msgID ||
          (item.id ?? '').trim() == msgID) {
        return item;
      }
    }
    final global = serviceLocator<TUIChatGlobalModel>();
    for (final item in global.rawMessageList(model.conversationID) ??
        const <V2TimMessage>[]) {
      if ((item.msgID ?? '').trim() == msgID ||
          (item.id ?? '').trim() == msgID) {
        return item;
      }
    }
    return null;
  }

  static Future<T?> _showWideDialog<T>({
    required BuildContext context,
    required String title,
    required Widget Function(BuildContext dialogContext, VoidCallback close) body,
    String? confirmText,
    VoidCallback? onConfirm,
  }) {
    final navContext = AppNavigator.key.currentContext ?? context;
    final media = MediaQuery.sizeOf(navContext);
    final width =
        media.width < 640 ? (media.width - 48).clamp(320.0, 560.0) : 560.0;
    final height = (media.height * 0.78).clamp(480.0, 640.0);
    final theme = _themeOf(navContext);
    final background =
        theme.wideBackgroundColor ?? theme.conversationItemBgColor ?? Colors.white;
    return showDialog<T>(
      context: navContext,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: const Color(0x8A000000),
      builder: (dialogContext) {
        void close() {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
          }
        }

        return Dialog(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: width, height: height),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: theme.darkTextColor ?? const Color(0xFF111827),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: close,
                        icon: Icon(
                          Icons.close_rounded,
                          color: theme.weakTextColor ?? const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: (theme.weakDividerColor ?? const Color(0xFFE8EAED))
                      .withValues(alpha: 0.85),
                ),
                Expanded(child: body(dialogContext, close)),
                if (confirmText != null) ...[
                  Divider(
                    height: 1,
                    color: (theme.weakDividerColor ?? const Color(0xFFE8EAED))
                        .withValues(alpha: 0.85),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: close,
                          child: Text(TIM_t('取消')),
                        ),
                        if (onConfirm != null) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: onConfirm,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  theme.primaryColor ?? const Color(0xFF147AFF),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(confirmText),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static TUITheme _themeOf(BuildContext context) {
    try {
      return Provider.of<DefaultThemeData>(context, listen: false).theme;
    } catch (_) {
      return DefTheme.blueTheme;
    }
  }

  static Future<bool> _forwardAsImage(
    BuildContext context,
    Map<String, dynamic> args,
  ) async {
    final theme = _themeOf(context);
    ConversationShareTarget? picked;
    await _showWideDialog<void>(
      context: context,
      title: TIM_t('转发'),
      body: (dialogContext, close) {
        return ConversationSharePickerPage(
          theme: theme,
          embedded: true,
          onPicked: (target) {
            picked = target;
            Navigator.of(dialogContext, rootNavigator: true).pop();
          },
        );
      },
    );
    final target = picked;
    if (target == null || !context.mounted) {
      return false;
    }
    try {
      final local = '${args['localPath'] ?? ''}'.trim();
      var path = local;
      if (path.isEmpty || !File(path).existsSync()) {
        final url = '${args['url'] ?? ''}'.trim();
        if (url.isEmpty) {
          ToastUtils.toast(TIM_t('转发失败'));
          return false;
        }
        final resolved = MediaUrlResolver.resolve(url) ?? url;
        final response = await Dio().get<List<int>>(
          resolved,
          options: Options(
            responseType: ResponseType.bytes,
            headers: MediaUrlResolver.authHeadersFor(resolved),
          ),
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          ToastUtils.toast(TIM_t('转发失败'));
          return false;
        }
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}/media_forward_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(data, flush: true);
        path = file.path;
      }
      final created = await TIMUIKitCore.getSDKInstance()
          .getMessageManager()
          .createImageMessage(
            imagePath: path,
            imageName: 'image.jpg',
          );
      final sent = created.code == 0 &&
          await ChatExternalMessageSender.sendCreatedMessage(
            messageInfo: created.data?.messageInfo,
            receiverUserId: target.userID,
            groupId: target.groupID,
            reason: 'media_popout_image_forwarded',
          );
      ToastUtils.toast(sent ? TIM_t('已转发') : TIM_t('转发失败'));
      return sent;
    } catch (error) {
      ChatImgTrace.log('[ChatImg] event=popout_host_forward_error error=$error');
      ToastUtils.toast(TIM_t('转发失败'));
      return false;
    }
  }

  static V2TimConversation _conversationFor(String conversationID, int typeIndex) {
    final model = serviceLocator<TUIConversationViewModel>();
    final cached = model.getConversation(conversationID);
    if (cached != null) {
      return cached;
    }
    final isGroup = typeIndex == ConvType.group.index ||
        conversationID.toUpperCase().startsWith('GROUP');
    return V2TimConversation(
      conversationID: conversationID,
      type: isGroup ? 2 : 1,
      userID: isGroup
          ? null
          : conversationID.replaceFirst(RegExp(r'^c2c_', caseSensitive: false), ''),
      groupID: isGroup
          ? conversationID.replaceFirst(RegExp(r'^group_', caseSensitive: false), '')
          : null,
    );
  }

  static MessageAnchor _anchorFor(
    Map<String, dynamic> args,
    V2TimConversation conversation,
  ) {
    String? clean(String key) {
      final text = '${args[key] ?? ''}'.trim();
      return text.isEmpty ? null : text;
    }

    final conversationID = conversation.conversationID.trim();
    return MessageAnchor(
      conversationID:
          conversationID.isEmpty ? conversationIDOfArgs(args) : conversationID,
      convType: conversation.type ?? 1,
      msgID: clean('messageID'),
      localID: clean('localID'),
      seq: clean('seq'),
      timestamp: args['timestamp'] is int
          ? args['timestamp'] as int
          : int.tryParse('${args['timestamp'] ?? ''}'),
      sender: clean('sender'),
      elemType: args['elemType'] is int
          ? args['elemType'] as int
          : int.tryParse('${args['elemType'] ?? ''}'),
    );
  }

  static String conversationIDOfArgs(Map<String, dynamic> args) {
    return '${args['conversationID'] ?? ''}'.trim();
  }
}
