import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reply quote pins to latest only through onAtUserWhenReply', () {
    final chat = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'tim_uikit_chat.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final portraitStart = chat.indexOf('onLongPressForOthersHeadPortrait:');
    final replyStart = chat.indexOf('onAtUserWhenReply:');
    final historyConfigStart = chat.indexOf('mainHistoryListConfig:');
    expect(portraitStart, greaterThanOrEqualTo(0));
    expect(replyStart, greaterThan(portraitStart));
    expect(historyConfigStart, greaterThan(replyStart));

    final portrait = chat.substring(portraitStart, replyStart);
    expect(portrait.contains('pinToLatest'), isFalse);

    final reply = chat.substring(replyStart, historyConfigStart);
    expect(reply.contains('pinToLatest: true'), isTrue);
  });

  test('longPressToAt records pinToLatestAfterAt with default false', () {
    final controller = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field_controller.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final start = controller.indexOf(
      'longPressToAt(String? userName, String? userID, {bool pinToLatest = false})',
    );
    expect(start, greaterThanOrEqualTo(0));
    final end = controller.indexOf('setTextField(String text', start);
    expect(end, greaterThan(start));
    final method = controller.substring(start, end);
    expect(method.contains('pinToLatestAfterAt = pinToLatest'), isTrue);
  });

  test('longPressToAt handler pins before mentioning and after clearing the flag', () {
    final field = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final start = field.indexOf('if (actionType == ActionType.longPressToAt)');
    final end = field.indexOf('} else if (actionType == ActionType.setTextField)', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = field.substring(start, end);
    expect(branch.contains('_pinToLatestThenMention('), isTrue);
    expect(branch.contains('goDownBottom()'), isFalse);
    expect(branch.contains('fromOutgoingSend: true'), isFalse);

    final flagRead = branch.indexOf(
      'widget.controller?.pinToLatestAfterAt ?? false',
    );
    final flagClear = branch.indexOf('pinToLatestAfterAt = false');
    final pinCall = branch.indexOf('_pinToLatestThenMention(');
    final elseMention = branch.indexOf('} else {');
    expect(flagRead, greaterThanOrEqualTo(0));
    expect(flagClear, greaterThan(flagRead));
    expect(pinCall, greaterThan(flagClear));
    expect(elseMention, greaterThan(pinCall));

    final helperStart = field.indexOf(
      'Future<void> _pinToLatestThenMention(String? userID, String? nickName)',
    );
    final helperEnd = field.indexOf(
      'mentionMemberInMessage(String? userID, String? nickName)',
      helperStart,
    );
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    final helper = field.substring(helperStart, helperEnd);
    expect(
      helper.contains('completeContextMenuViewportRestore(widget.conversationID)'),
      isTrue,
    );
    expect(helper.contains('endOfFrame'), isTrue);
    expect(helper.contains('await _goDownBottomImpl()'), isTrue);
    final restoreAt = helper.indexOf('completeContextMenuViewportRestore');
    final frameAt = helper.indexOf('endOfFrame');
    final pinAt = helper.indexOf('await _goDownBottomImpl()');
    final mentionAt = helper.indexOf('mentionMemberInMessage(userID, nickName)');
    expect(restoreAt, greaterThanOrEqualTo(0));
    expect(frameAt, greaterThan(restoreAt));
    expect(pinAt, greaterThan(frameAt));
    expect(mentionAt, greaterThan(pinAt));

    final mentionStart = field.indexOf(
      'mentionMemberInMessage(String? userID, String? nickName)',
    );
    final mentionEnd = field.indexOf('bool shouldRemoveAtTag(', mentionStart);
    expect(mentionStart, greaterThanOrEqualTo(0));
    expect(mentionEnd, greaterThan(mentionStart));
    final mentionBody = field.substring(mentionStart, mentionEnd);
    expect(mentionBody.contains('goDownBottom'), isFalse);
  });

  test('input return delegates to the shared viewport transaction after composition guard', () {
    final field = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final helperStart = field.indexOf('Future<void> _returnToLatestAfterInput({');
    final helperEnd = field.indexOf('_onCursorChange()', helperStart);
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    final helper = field.substring(helperStart, helperEnd);

    final dispatchAt = helper.indexOf('await widget.model.requestLatestViewportReturn()');
    expect(dispatchAt, greaterThanOrEqualTo(0));
    final beforeDispatch = helper.substring(0, dispatchAt);
    expect(beforeDispatch.contains('_hasActiveTextComposition'), isTrue);
    expect(beforeDispatch.contains('!allowKeyboardReturn &&'), isTrue);
    expect(
      beforeDispatch.contains(
        'KeyboardViewportTransitionCoordinator.active?.isAnimating == true',
      ),
      isTrue,
    );
    expect(helper.contains('jumpTo('), isFalse);
    expect(helper.contains('reloadNewestMessageWindow('), isFalse);
    expect(helper.contains('acknowledgeHistoryWindowReturnToLatest('), isFalse);
  });

  test('tooltip and hover reply do not call goDownBottom directly', () {
    final tooltip = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_message_tooltip.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final replyCaseStart = tooltip.indexOf('case "replyMessage":');
    final replyCaseEnd = tooltip.indexOf('default:', replyCaseStart);
    expect(replyCaseStart, greaterThanOrEqualTo(0));
    expect(replyCaseEnd, greaterThan(replyCaseStart));
    expect(
      tooltip.substring(replyCaseStart, replyCaseEnd).contains('goDownBottom'),
      isFalse,
    );

    final item = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final hoverStart = item.indexOf('model.repliedMessage = widget.message;');
    final hoverEnd = item.indexOf(
      'if (resolvedToolTipsConfig.showForwardMessage &&',
      hoverStart,
    );
    expect(hoverStart, greaterThanOrEqualTo(0));
    expect(hoverEnd, greaterThan(hoverStart));
    expect(
      item.substring(hoverStart, hoverEnd).contains('goDownBottom'),
      isFalse,
    );
  });

  test('narrow focus changes still do not pin to latest', () {
    final narrow = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final focusStart = narrow.indexOf('void _onFocusChanged()');
    final focusEnd = narrow.indexOf('void initState()', focusStart);
    expect(focusStart, greaterThanOrEqualTo(0));
    expect(focusEnd, greaterThan(focusStart));
    expect(
      narrow.substring(focusStart, focusEnd).contains('goDownBottom()'),
      isFalse,
    );
  });
}
