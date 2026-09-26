import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
    'TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  String methodSlice(String startMarker, String endMarker) {
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);
    expect(start, greaterThanOrEqualTo(0), reason: startMarker);
    expect(end, greaterThan(start), reason: endMarker);
    return source.substring(start, end);
  }

  test('historyOrigin prefers at-jump over unread and search anchors', () {
    final start = source.indexOf('final historyOrigin = _atJumpOrigin ??');
    expect(start, greaterThanOrEqualTo(0));
    final slice = source.substring(start, start + 220);
    expect(slice, contains('_atJumpOrigin ??'));
    expect(slice, contains('_entryUnreadOrigin ??'));
    expect(slice, contains('widget.searchJumpAnchor ??'));
  });

  test('at-seq far jump retains viewport then loads around-seq', () {
    final jump = methodSlice(
      'Future<bool> _onScrollToIndexBySeq(String targetSeq) async {',
      '  Future<bool> _centerOnAtMeSeq(',
    );
    expect(jump, contains('begin(showSpinner: true)'));
    expect(
      jump.indexOf('begin(showSpinner: true)'),
      lessThan(jump.indexOf('loadListForSpecificMessage(')),
    );
    expect(jump, contains('await transition?.finish()'));
    expect(jump, contains('AtMeJump.pickVisibleIndex'));
    expect(jump, contains('_renderedVisibleMessages = null'));
  });

  test('successful at-jump does not release center ownership', () {
    final jump = methodSlice(
      'Future<bool> _onScrollToIndexBySeq(String targetSeq) async {',
      '  Future<bool> _centerOnAtMeSeq(',
    );
    final successAt = jump.indexOf("'at_me_around_jump_success'");
    expect(successAt, greaterThanOrEqualTo(0));
    final successPath = jump.substring(successAt, jump.indexOf('return true;'));
    expect(successPath.contains('_releaseAtJumpCenterOwnership'), isFalse);
    expect(successPath.contains('_atJumpOrigin = null'), isFalse);
  });

  test('at-jump center is released only by gesture, leave, unread, dispose', () {
    expect(source.contains('Timer') && source.contains('_atJumpOrigin'), isTrue);
    expect(
      source.contains(RegExp(r'Timer\([^)]*\)[\s\S]{0,80}_atJumpOrigin\s*=\s*null')),
      isFalse,
    );
    expect(
      source.contains(
        RegExp(r'Timer\([^)]*\)[\s\S]{0,120}_releaseAtJumpCenterOwnership'),
      ),
      isFalse,
    );

    final drag = methodSlice(
      'if (notification is ScrollStartNotification &&',
      '_userScrollGestureActive = true;',
    );
    expect(drag, contains('dragDetails != null'));
    expect(drag, contains('_releaseAtJumpCenterOwnership()'));

    final didUpdate = methodSlice(
      'void didUpdateWidget(TIMUIKitHistoryMessageList oldWidget) {',
      'final newestSideAbsorbed = _onMessageListMaybeInserted(',
    );
    expect(didUpdate, contains('_releaseAtJumpCenterOwnership(notify: false)'));
    expect(didUpdate, contains('oldWidget.model.conversationID'));
    expect(didUpdate, contains('widget.searchJumpAnchor'));

    final unread = methodSlice(
      'Future<bool> _scrollToFirstUnreadFromTongue(int requestedUnreadCount) async {',
      'final previousPosition = globalModel.getMessageListPosition(convId);',
    );
    expect(unread, contains('_releaseAtJumpCenterOwnership()'));

    final dispose = methodSlice(
      'void dispose() {',
      '_initialMountGeneration++;',
    );
    expect(dispose, contains('_releaseAtJumpCenterOwnership(notify: false)'));
  });
}
