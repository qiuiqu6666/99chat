// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_grouping.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field_controller.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_list_stable_keys.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tim_ui_kit_sticker_plugin/utils/tim_custom_face_data.dart';

enum LoadingPlace {
  none,
  top,
  bottom,
}

class TIMUIKitHistoryMessageListContainer extends StatefulWidget {
  final Widget Function(BuildContext, V2TimMessage?)? itemBuilder;
  final AutoScrollController? scrollController;
  final String conversationID;
  final Function(String? userId, String? nickName)?
      onLongPressForOthersHeadPortrait;
  final Function(String? userId, String? nickName)? onAtUserWhenReply;
  final List<V2TimGroupAtInfo?>? groupAtInfoList;
  final V2TimMessage? initFindingMsg;
  final MessageAnchor? searchJumpAnchor;

  /// message item builder, works for customize all message types and row layout.
  final MessageItemBuilder? messageItemBuilder;

  /// Optional UI-only projection. The callback may add local overlay rows to
  /// the formal message snapshot without changing pagination or Writer state.
  final List<V2TimMessage?> Function(
    String conversationID,
    List<V2TimMessage?> formalMessages,
  )? messageListProjectionBuilder;
  final Listenable? messageListProjectionListenable;

  /// The controller for text field.
  final TIMUIKitInputTextFieldController? textFieldController;

  /// the builder for avatar
  final Widget Function(BuildContext context, V2TimMessage message)?
      userAvatarBuilder;

  /// the builder for tongue
  final TongueItemBuilder? tongueItemBuilder;

  final Widget? Function(V2TimMessage message, Function() closeTooltip,
      [Key? key, BuildContext? context])? extraTipsActionItemBuilder;

  /// conversation type
  final ConvType conversationType;

  /// Avatar and name in message reaction tap callback.
  final void Function(String userID, TapDownDetails tapDetails)? onTapAvatar;

  /// Avatar and name in message reaction secondary tap callback.
  final void Function(String userID, TapDownDetails tapDetails)?
      onSecondaryTapAvatar;

  @Deprecated(
      "Nickname will not show in one-to-one chat, if you tend to control it in group chat, please use `isShowSelfNameInGroup` and `isShowOthersNameInGroup` from `config: TIMUIKitChatConfig` instead")
  final bool showNickName;

  final TIMUIKitHistoryMessageListConfig? mainHistoryListConfig;

  /// tool tips panel configuration, long press message will show tool tips panel
  final ToolTipsConfig? toolTipsConfig;

  final List<CustomEmojiFaceData> customEmojiStickerList;

  final bool isAllowScroll;

  final V2TimConversation conversation;

  final V2TimGroupMemberFullInfo? groupMemberInfo;

  /// This parameter accepts a custom widget to be displayed when the mouse hovers over a message,
  /// replacing the default message hover action bar.
  /// Applicable only on desktop platforms.
  /// If provided, the default message action functionality will appear in the right-click context menu instead.
  final Widget? Function(V2TimMessage message)? customMessageHoverBarOnDesktop;

  const TIMUIKitHistoryMessageListContainer({
    Key? key,
    this.itemBuilder,
    this.scrollController,
    required this.conversationID,
    required this.conversationType,
    this.userAvatarBuilder,
    this.onLongPressForOthersHeadPortrait,
    this.onAtUserWhenReply,
    this.groupAtInfoList,
    this.messageItemBuilder,
    this.messageListProjectionBuilder,
    this.messageListProjectionListenable,
    this.tongueItemBuilder,
    this.extraTipsActionItemBuilder,
    this.isAllowScroll = true,
    this.onTapAvatar,
    @Deprecated(
        "Nickname will not show in one-to-one chat, if you tend to control it in group chat, please use `isShowSelfNameInGroup` and `isShowOthersNameInGroup` from `config: TIMUIKitChatConfig` instead")
    this.showNickName = true,
    this.initFindingMsg,
    this.searchJumpAnchor,
    this.mainHistoryListConfig,
    this.toolTipsConfig,
    this.customEmojiStickerList = const [],
    this.textFieldController,
    required this.conversation,
    this.onSecondaryTapAvatar,
    this.groupMemberInfo,
    this.customMessageHoverBarOnDesktop,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      _TIMUIKitHistoryMessageListContainerState();
}

class _TIMUIKitHistoryMessageListContainerState
    extends TIMUIKitState<TIMUIKitHistoryMessageListContainer> {
  late TIMUIKitHistoryMessageListController _historyMessageListController;
  final _listStableKeys = ChatListStableKeys();
  final Map<String, _CachedHistoryMessageRow> _messageRowCache =
      <String, _CachedHistoryMessageRow>{};
  String? _messageRowCacheConversationID;

  Future<bool> requestForData(String? lastMsgID, LoadDirection direction,
      TUIChatSeparateViewModel model,
      [int? count, int? lastSeq, V2TimMessage? lastMsg]) async {
    final listPosition =
        model.globalModel.getMessageListPosition(model.conversationID);
    final allowLatest = direction == LoadDirection.latest &&
        (model.haveMoreLatestData ||
            listPosition == HistoryMessagePosition.notShowLatest ||
            listPosition == HistoryMessagePosition.inTwoScreen ||
            listPosition == HistoryMessagePosition.awayTwoScreen);
    if (direction == LoadDirection.previous || allowLatest) {
      ChatHistoryTrace.log(
        'request_for_data',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'lastMsgID': lastMsgID,
          'lastSeq': lastSeq,
          'count': count ?? HistoryMessageDartConstant.getCount,
          'allowLatest': allowLatest,
          'haveMoreData': model.haveMoreData,
          'haveMoreLatestData': model.haveMoreLatestData,
        },
      );
      final loaded = await model.loadChatRecord(
        direction: direction,
        count: count ?? HistoryMessageDartConstant.getCount,
        lastMsgID: lastMsgID,
        lastMsgSeq: lastSeq ?? -1,
        lastMsg: lastMsg,
      );
      ChatHistoryTrace.log(
        'request_for_data_result',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'loaded': loaded,
          'haveMoreData': model.haveMoreData,
          'haveMoreLatestData': model.haveMoreLatestData,
          'listLen': model.globalModel.rawMessageCount(model.conversationID),
        },
      );
      return loaded;
    } else {
      ChatHistoryTrace.log(
        'request_for_data_rejected',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'allowLatest': allowLatest,
        },
      );
      return false;
    }
  }

  Widget Function(BuildContext, V2TimMessage)? _getTopRowBuilder(
      TUIChatSeparateViewModel model) {
    if (widget.messageItemBuilder?.messageNickNameBuilder != null) {
      return (BuildContext context, V2TimMessage message) {
        return widget.messageItemBuilder!.messageNickNameBuilder!(
            context, message, model);
      };
    }
    return null;
  }

  Widget Function(BuildContext, V2TimMessage)? _getBottomRowBuilder() {
    final builder = widget.messageItemBuilder?.messageBottomRowBuilder;
    if (builder == null) {
      return null;
    }
    return (BuildContext context, V2TimMessage message) {
      return builder(context, message) ?? const SizedBox.shrink();
    };
  }

  @override
  void initState() {
    super.initState();
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageListContainer',
      phase: 'initState',
      stateHash: identityHashCode(this),
      conv: widget.conversation.conversationID,
      keyDebug: widget.key?.toString(),
    );
    _historyMessageListController = TIMUIKitHistoryMessageListController(
        scrollController: widget.scrollController);
  }

  @override
  void didUpdateWidget(
    covariant TIMUIKitHistoryMessageListContainer oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationID != widget.conversationID) {
      _messageRowCache.clear();
      _messageRowCacheConversationID = null;
    }
  }

  @override
  void deactivate() {
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageListContainer',
      phase: 'deactivate',
      stateHash: identityHashCode(this),
      conv: widget.conversation.conversationID,
      keyDebug: widget.key?.toString(),
      ancestors: _ancestorChain(),
    );
    super.deactivate();
  }

  @override
  void dispose() {
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageListContainer',
      phase: 'dispose',
      stateHash: identityHashCode(this),
      conv: widget.conversation.conversationID,
      keyDebug: widget.key?.toString(),
    );
    _messageRowCache.clear();
    super.dispose();
  }

  String _ancestorChain() {
    if (!mounted) return 'unmounted';
    final types = <String>[];
    context.visitAncestorElements((element) {
      types.add(element.widget.runtimeType.toString());
      return types.length < 8;
    });
    return types.join('>');
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final chatConfig = Provider.of<TIMUIKitChatConfig>(context);
    final TUIChatSeparateViewModel model =
        Provider.of<TUIChatSeparateViewModel>(context, listen: false);

    Widget buildProjectedList() {
      return TIMUIKitHistoryMessageListSelector(
        conversationID: model.conversationID,
        builder: (context, messageList, child) {
          final overlayResult = widget.messageListProjectionBuilder?.call(
                model.conversationID,
                messageList,
              ) ??
              messageList;
          // Business overlays are derived UI rows. A custom builder must not
          // mutate Sliver structure after publication; the normal path reuses
          // GlobalModel's exact immutable display projection without a copy.
          final projectedMessageList = identical(overlayResult, messageList)
              ? messageList
              : List<V2TimMessage?>.unmodifiable(overlayResult);
          // IMP(ProjOutTrace)：打印 projectionBuilder 实际返回值
          // ignore: avoid_print
          if (ChatHistoryTrace.enabled) {
            debugPrint(
              '[ChatHistory][ProjOutTrace] stage=projected_result conv=${model.conversationID} '
              'inputLen=${messageList.length} projectedLen=${projectedMessageList.length} '
              'isSameInstance=${identical(projectedMessageList, messageList)}',
            );
          }
          Object groupingKey(V2TimMessage message) {
            final id = (message.msgID ?? message.id ?? '').trim();
            return id.isEmpty ? message : id;
          }

          final groupIndices = <Object, int>{
            for (var i = 0; i < projectedMessageList.length; i++)
              if (projectedMessageList[i] != null)
                groupingKey(projectedMessageList[i]!): i,
          };
          if (_messageRowCacheConversationID != model.conversationID) {
            _messageRowCache.clear();
            _messageRowCacheConversationID = model.conversationID;
          }
          final liveRowKeys = <String>{
            for (final message in projectedMessageList)
              if (message != null) _historyMessageRowKey(message),
          };
          _messageRowCache.removeWhere(
            (key, _) => !liveRowKeys.contains(key),
          );
          final rowConfigToken = Object.hashAll(<Object?>[
            identityHashCode(widget.messageItemBuilder),
            identityHashCode(widget.groupMemberInfo),
            identityHashCode(widget.textFieldController),
            identityHashCode(widget.userAvatarBuilder),
            identityHashCode(widget.customEmojiStickerList),
            identityHashCode(widget.customMessageHoverBarOnDesktop),
            identityHashCode(widget.onTapAvatar),
            identityHashCode(widget.onSecondaryTapAvatar),
            identityHashCode(widget.onLongPressForOthersHeadPortrait),
            identityHashCode(widget.onAtUserWhenReply),
            identityHashCode(widget.extraTipsActionItemBuilder),
            chatConfig.isShowAvatar,
            chatConfig.isAtWhenReply,
            chatConfig.isAllowClickAvatar,
            chatConfig.isAllowLongPressMessage,
            chatConfig.isUseMessageReaction,
          ]);
          return TIMUIKitHistoryMessageList(
            key: _listStableKeys.historyFor(model.conversationID),
            conversation: widget.conversation,
            model: model,
            isAllowScroll: widget.isAllowScroll,
            controller: _historyMessageListController,
            groupAtInfoList: widget.groupAtInfoList,
            mainHistoryListConfig: widget.mainHistoryListConfig,
            itemBuilder: (context, message) {
              final resolvedMessage = message!;
              final index = groupIndices[groupingKey(resolvedMessage)];
              final canGroup =
                  widget.messageItemBuilder?.renderingDirectionCallback == null;
              final continuesPrevious = canGroup &&
                  index != null &&
                  index + 1 < projectedMessageList.length &&
                  ChatMessageGrouping.joins(
                    projectedMessageList[index + 1],
                    resolvedMessage,
                  );
              final joinsNext = canGroup &&
                  index != null &&
                  index > 0 &&
                  ChatMessageGrouping.joins(
                    resolvedMessage,
                    projectedMessageList[index - 1],
                  );
              final rowKey = _historyMessageRowKey(resolvedMessage);
              final signature = Object.hashAll(<Object?>[
                _historyMessagePresentationSignature(resolvedMessage),
                continuesPrevious,
                joinsNext,
                rowConfigToken,
              ]);
              final cached = _messageRowCache[rowKey];
              if (cached != null && cached.signature == signature) {
                return cached.widget;
              }
              final row = TIMUIKitHistoryMessageListItem(
                continuesPrevious: continuesPrevious,
                padding: EdgeInsets.only(bottom: joinsNext ? 5 : 12),
                customMessageHoverBarOnDesktop:
                    widget.customMessageHoverBarOnDesktop,
                groupMemberInfo: widget.groupMemberInfo,
                textFieldController: widget.textFieldController,
                userAvatarBuilder: widget.userAvatarBuilder,
                customEmojiStickerList: widget.customEmojiStickerList,
                topRowBuilder: _getTopRowBuilder(model),
                bottomRowBuilder: _getBottomRowBuilder(),
                onScrollToIndex: _historyMessageListController.scrollToIndex,
                onScrollToIndexBegin:
                    _historyMessageListController.scrollToIndexBegin,
                toolTipsConfig: widget.toolTipsConfig ??
                    ToolTipsConfig(
                        additionalItemBuilder:
                            widget.extraTipsActionItemBuilder),
                message: resolvedMessage,
                showAvatar: chatConfig.isShowAvatar,
                onSecondaryTapForOthersPortrait: widget.onSecondaryTapAvatar,
                onTapForOthersPortrait: widget.onTapAvatar,
                messageItemBuilder: widget.messageItemBuilder,
                onLongPressForOthersHeadPortrait:
                    widget.onLongPressForOthersHeadPortrait,
                onAtUserWhenReply: widget.onAtUserWhenReply,
                allowAtUserWhenReply: chatConfig.isAtWhenReply,
                allowAvatarTap: chatConfig.isAllowClickAvatar,
                allowLongPress: chatConfig.isAllowLongPressMessage,
                isUseMessageReaction: chatConfig.isUseMessageReaction,
                renderingDirectionCallback:
                    widget.messageItemBuilder?.renderingDirectionCallback,
              );
              _messageRowCache[rowKey] = _CachedHistoryMessageRow(
                signature: signature,
                widget: row,
              );
              return row;
            },
            tongueItemBuilder: widget.tongueItemBuilder,
            initFindingMsg: widget.initFindingMsg,
            searchJumpAnchor: widget.searchJumpAnchor,
            messageList: projectedMessageList,
            onLoadMore: (String? a, LoadDirection direction,
                [int? b, int? lastSeq, V2TimMessage? lastMsg]) async {
              ChatHistoryTrace.log(
                'on_load_more_invoked',
                conversationID: model.conversationID,
                extras: <String, Object?>{
                  'direction': direction.name,
                  'lastMsgID': a,
                  'lastSeq': lastSeq,
                  'count': b,
                  'haveMoreData': model.haveMoreData,
                  'haveMoreLatestData': model.haveMoreLatestData,
                  'listLen':
                      model.globalModel.rawMessageCount(model.conversationID),
                },
              );
              final loaded = await requestForData(
                a,
                direction,
                model,
                b,
                lastSeq,
                lastMsg,
              );
              ChatHistoryTrace.log(
                'on_load_more_returned',
                conversationID: model.conversationID,
                extras: <String, Object?>{
                  'direction': direction.name,
                  'loaded': loaded,
                  'haveMoreData': model.haveMoreData,
                  'haveMoreLatestData': model.haveMoreLatestData,
                  'listLen':
                      model.globalModel.rawMessageCount(model.conversationID),
                },
              );
              return loaded;
            },
          );
        },
      );
    }

    final overlayListenable = widget.messageListProjectionListenable;
    if (overlayListenable == null ||
        widget.messageListProjectionBuilder == null) {
      return buildProjectedList();
    }
    return ListenableBuilder(
      listenable: overlayListenable,
      builder: (context, child) => buildProjectedList(),
    );
  }
}

String _historyMessageRowKey(V2TimMessage message) {
  final msgID = message.msgID?.trim() ?? '';
  if (msgID.isNotEmpty) return 'msg:$msgID';
  final id = message.id?.trim() ?? '';
  if (id.isNotEmpty) return 'id:$id';
  final seq = message.seq?.trim() ?? '';
  if (seq.isNotEmpty) {
    return 'seq:${message.groupID ?? message.userID ?? ''}:$seq';
  }
  return 'local:${identityHashCode(message)}';
}

int _historyMessagePresentationSignature(V2TimMessage message) {
  return Object.hashAll(<Object?>[
    message.msgID,
    message.id,
    message.seq,
    message.timestamp,
    message.status,
    message.elemType,
    message.isSelf,
    message.isRead,
    message.isPeerRead,
    message.needReadReceipt,
    message.sender,
    message.userID,
    message.groupID,
    message.faceUrl,
    message.nameCard,
    message.localCustomInt,
    message.localCustomData,
    identityHashCode(message.textElem),
    identityHashCode(message.imageElem),
    identityHashCode(message.videoElem),
    identityHashCode(message.soundElem),
    identityHashCode(message.fileElem),
    identityHashCode(message.customElem),
    identityHashCode(message.faceElem),
    identityHashCode(message.locationElem),
    identityHashCode(message.mergerElem),
    identityHashCode(message.groupTipsElem),
  ]);
}

class _CachedHistoryMessageRow {
  const _CachedHistoryMessageRow({
    required this.signature,
    required this.widget,
  });

  final int signature;
  final Widget widget;
}
