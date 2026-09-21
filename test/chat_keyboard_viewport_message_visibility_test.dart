import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'keyboard viewport changes retain bottom visibility for inbound messages',
      () {
    final model = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
      'tui_chat_global_model.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final chat = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'tim_uikit_chat.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(model.contains('beginKeyboardViewportTransition'), isTrue);
    expect(model.contains('endKeyboardViewportTransition'), isTrue);
    expect(model.contains('beginGeometryViewportTransition'), isTrue);
    expect(model.contains('endGeometryViewportTransition'), isTrue);
    expect(
      model.contains('_wasAtBottomBeforeKeyboardViewportChange(convID)'),
      isTrue,
    );
    expect(model.contains('_restoreKeyboardScrollAnchor'), isFalse);
    final finishStart = model.indexOf('void _finishKeyboardViewportTransition');
    final finishEnd = model.indexOf(
      'void _clearKeyboardViewportTransition',
      finishStart,
    );
    expect(finishStart, greaterThanOrEqualTo(0));
    expect(finishEnd, greaterThan(finishStart));
    final finish = model.substring(finishStart, finishEnd);
    expect(finish.contains('requestPinToBottom'), isFalse);
    expect(finish.contains('jumpTo'), isFalse);
    expect(finish.contains('receivedCount'), isFalse);
    expect(finish.contains('settleAtTrueLatestEnd'), isFalse);
    expect(finish.contains('setFollowingLatest'), isTrue);
    final appChat = File('lib/src/chat.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      appChat.contains('beginGeometryViewportTransition(convId)'),
      isTrue,
    );
    expect(
      appChat.contains('endGeometryViewportTransition(convId)'),
      isTrue,
    );
    expect(appChat.contains('_scheduleEndGeometryViewportTransition'), isTrue);
    expect(
      appChat.contains('currentSelectedConv.trim()'),
      isTrue,
    );
    final liveTapStart = appChat.indexOf('Future<void> _onGroupLiveBannerTap()');
    final liveTapEnd = appChat.indexOf('void _closeGroupLiveWatch()', liveTapStart);
    expect(liveTapStart, greaterThanOrEqualTo(0));
    expect(liveTapEnd, greaterThan(liveTapStart));
    final liveTap = appChat.substring(liveTapStart, liveTapEnd);
    expect(liveTap.contains('currentSelectedConv'), isTrue);
    expect(liveTap.contains('_resolvedConversationID()'), isFalse);
    expect(liveTap.contains('_scheduleEndGeometryViewportTransition(convId)'), isTrue);
    final liveCloseStart = appChat.indexOf('void _closeGroupLiveWatch()');
    final liveCloseEnd = appChat.indexOf('void _', liveCloseStart + 10);
    expect(liveCloseStart, greaterThanOrEqualTo(0));
    expect(liveCloseEnd, greaterThan(liveCloseStart));
    final liveClose = appChat.substring(liveCloseStart, liveCloseEnd);
    expect(liveClose.contains('currentSelectedConv'), isTrue);
    expect(liveClose.contains('_resolvedConversationID()'), isFalse);
    expect(
      liveClose.contains('_scheduleEndGeometryViewportTransition(convId)'),
      isTrue,
    );
    expect(
      chat.contains(
        'chatGlobalModel.beginKeyboardViewportTransition(_getConvID())',
      ),
      isTrue,
    );
    expect(
      chat.contains(
        'chatGlobalModel.endKeyboardViewportTransition(_getConvID())',
      ),
      isTrue,
    );
    // 几何闸门：用户拖拽可覆盖；离开会话必须归零 depth（协调器不补 onEnd）。
    expect(model.contains('void _resetGeometryViewportTransition('), isTrue);
    final leaveStart = model.indexOf('clearCurrentConversation({bool notify');
    final leaveEnd = model.indexOf('_currentConversationList.removeLast();', leaveStart);
    expect(leaveStart, greaterThanOrEqualTo(0));
    expect(leaveEnd, greaterThan(leaveStart));
    final leave = model.substring(leaveStart, leaveEnd);
    expect(leave.contains('_resetGeometryViewportTransition(leaving)'), isTrue);
    expect(leave.contains('_clearKeyboardViewportTransition(leaving)'), isFalse);
    final scrollStart = model.indexOf('void setChatListUserScrolling(bool scrolling)');
    final scrollEnd = model.indexOf('} else if (wasScrolling)', scrollStart);
    expect(scrollStart, greaterThanOrEqualTo(0));
    expect(scrollEnd, greaterThan(scrollStart));
    final scroll = model.substring(scrollStart, scrollEnd);
    expect(
      scroll.contains('noteUserDragOverridesGeometryViewportTransition(convId)'),
      isTrue,
    );
  });

  test('chat keyboard uses the system inset and does not intercept IME', () {
    final chat = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'tim_uikit_chat.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(chat, contains('resizeToAvoidBottomInset: false'));
    expect(chat.contains('MediaQuery.viewInsetsOf'), isFalse);
    expect(chat.contains('MediaQuery.removeViewInsets'), isFalse);
    expect(chat.contains('MediaQuery.of(context)'), isFalse);
    final metricsStart = chat.indexOf('void didChangeMetrics()');
    final metricsEnd = chat.indexOf('void initState()', metricsStart);
    expect(metricsStart, greaterThanOrEqualTo(0));
    expect(metricsEnd, greaterThan(metricsStart));
    final metrics = chat.substring(metricsStart, metricsEnd);
    expect(metrics, contains('applyFromView(view)'));
    expect(metrics.contains('setState('), isFalse);
    expect(metrics.contains('View.of('), isFalse);

    final narrow = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final insetFnStart = narrow.indexOf('double _keyboardInsetBottom()');
    expect(insetFnStart, greaterThanOrEqualTo(0));
    final insetFnEnd = narrow.indexOf('double _getBottomHeight()', insetFnStart);
    final insetFn = narrow.substring(insetFnStart, insetFnEnd);
    expect(insetFn, contains('effectiveInset'));
    expect(insetFn.contains('inset.value'), isFalse);

    final typeIdx = narrow.indexOf('keyboardType: TextInputType.text');
    expect(typeIdx, greaterThan(0));
    final tap = narrow.substring(typeIdx - 400, typeIdx);
    expect(tap, contains('_switchToKeyboard()'));
    // An explicit input tap returns to latest; passive focus/inset updates do not.
    expect(tap.contains('goDownBottom()'), isTrue);
    expect(tap.contains('requestFocus()'), isFalse);

    final focusStart = narrow.indexOf('void _onFocusChanged()');
    final focusEnd = narrow.indexOf('void initState()', focusStart);
    final focus = narrow.substring(focusStart, focusEnd);
    expect(focus.contains('goDownBottom()'), isFalse);

    final history = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(history.contains('ChatKeyboardLayoutScope'), isFalse);
    expect(history.contains('MediaQuery.viewInsetsOf'), isFalse);
    expect(
      history.contains(
        'KeyboardViewportTransitionCoordinator.active?.isAnimating == true',
      ),
      isTrue,
    );
    expect(history.contains('_listGeometryLatchHeld'), isTrue);
    expect(history.contains('_listGeometryStableMetrics >= 2'), isTrue);
    expect(history.contains("logBlocked('geometry_viewport')"), isTrue);

    final tongue = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/TIMUIKitTongue/'
      'tim_uikit_chat_history_message_list_tongue_container.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(tongue.contains('_settleLiveUnreadAtTrueLatestEnd()'), isTrue);
    final liveSettleStart =
        tongue.indexOf('void _settleLiveUnreadAtTrueLatestEnd()');
    final liveSettleEnd = tongue.indexOf('void _settleAtTrueLatestEnd()', liveSettleStart);
    expect(liveSettleStart, greaterThanOrEqualTo(0));
    expect(liveSettleEnd, greaterThan(liveSettleStart));
    final liveSettle = tongue.substring(liveSettleStart, liveSettleEnd);
    expect(liveSettle.contains('markMessageAsRead'), isFalse);
    expect(liveSettle.contains('_entryUnreadCount = 0'), isFalse);
    final tapSettleStart = tongue.indexOf('void _settleAtTrueLatestEnd()');
    final tapSettleEnd = tongue.indexOf('Future<void> scrollToLatestAndDismissUnreadCapsule()', tapSettleStart);
    expect(tapSettleStart, greaterThanOrEqualTo(0));
    expect(tapSettleEnd, greaterThan(tapSettleStart));
    final tapSettle = tongue.substring(tapSettleStart, tapSettleEnd);
    expect(tapSettle.contains('markMessageAsRead'), isTrue);
    final selectorStart = tongue.indexOf('Widget _buildTongueSelector(');
    expect(selectorStart, greaterThanOrEqualTo(0));
    final selector = tongue.substring(selectorStart, selectorStart + 8000);
    expect(selector.contains('_settleLiveUnreadAtTrueLatestEnd()'), isTrue);
    expect(
      selector.contains(
        'if (mounted && _atTrueLatestEndNow()) {\n'
        '                _settleAtTrueLatestEnd();',
      ),
      isFalse,
    );
  });

  test('Android MainActivity uses adjustNothing for IME', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final activityStart = manifest.indexOf('android:name=".MainActivity"');
    expect(activityStart, greaterThanOrEqualTo(0));
    final activityEnd = manifest.indexOf('</activity>', activityStart);
    expect(activityEnd, greaterThan(activityStart));
    final activity = manifest.substring(activityStart, activityEnd);
    expect(activity, contains('adjustNothing'));
    expect(activity.contains('adjustResize'), isFalse);
  });
}
