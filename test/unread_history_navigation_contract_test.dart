import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('third_party/tencent_cloud_chat_uikit/lib/ui/views/'
          'TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('unread installs historical position before loading and uses spinner',
      () {
    final start =
        source.indexOf('Future<bool> _scrollToFirstUnreadFromTongue(');
    final body = source.substring(
        start, source.indexOf('void _showCantFindFirstUnread()', start));
    expect(body, contains('begin(showSpinner: true)'));
    expect(body, isNot(contains('retainViewport: false')));
    expect(body.indexOf('HistoryMessagePosition.notShowLatest'),
        lessThan(body.indexOf('await _jumpToFirstUnreadAroundWindow(')));
    expect(body, contains('_cancelForcePinScroll()'));
    expect(body, contains('_abortViewportInsertSlideForSupersede()'));
    expect(body, contains('finally'));
    expect(body, contains('await transition?.finish()'));
    expect(body.indexOf('_searchJumpStabilizeUntilMs = 0'),
        greaterThan(body.indexOf('await transition?.finish()')));
    expect(body.substring(body.indexOf('await transition?.finish()')),
        contains('setMemoryWindowSuppressed(convId, false)'));
    expect(body, contains('if (!current()) return false;'));
  });

  test('group unread uses the history around-loader before resolving an index',
      () {
    final start = source.indexOf("if ((target.strategy == 'group_read_seq'");
    final body = source.substring(
        start, source.indexOf("if (target.strategy == 'c2c_read_ts'", start));
    expect(body.indexOf('await widget.model.loadListForSpecificMessage('),
        lessThan(body.indexOf('targetGlobalIndex = _globalIndexForSeq(')));
    expect(body, contains('searchJumpRequest: request'));
    expect(body, contains('waitForSearchJumpLayout()'));
  });

  test(
      'unread verifies and highlights the same stable anchor as history search',
      () {
    final start = source.indexOf('Future<bool> _finishFirstUnreadJump(');
    final body = source.substring(start,
        source.indexOf('int? _globalIndexForFirstUnreadAfterSeq(', start));
    expect(body, contains('_entryUnreadOrigin = targetAnchor'));
    expect(body, contains('_globalIndexForAnchor(targetAnchor)'));
    expect(body, contains('await _centerOnGlobalIndex('));
    expect(body, contains('widget.model.jumpMsgID = jumpId'));
    expect(source, contains('final strictCenter = _entryUnreadOrigin != null'));
    expect(source, contains('if (currentIndex == null) return false;'));
    final scrollStart = source.indexOf('Future<void> _geomScrollToIndex(');
    final scrollBody = source.substring(scrollStart,
        source.indexOf('void _assignShortHistorySpacer(', scrollStart));
    expect(scrollBody, isNot(contains('Duration(milliseconds: 1)')));
  });

  test('unread measured handoff avoids hidden animation and timed settling',
      () {
    final start = source.indexOf('Future<bool> _centerOnGlobalIndex(');
    final body = source.substring(
        start, source.indexOf('void _scheduleScrollToFindingMsg()', start));
    expect(body, contains('if (_unreadWindowJumpInFlight && target != null)'));
    expect(body, contains('await _correctSearchJumpTargetToCenter(target)'));
    final settleStart =
        source.indexOf('Future<bool> _stabilizeCenteredSearchJumpTarget(');
    final settle = source.substring(settleStart, start);
    expect(settle, contains('unreadHandoff ? 3 : 4'));
    expect(settle, contains('if (!unreadHandoff)'));
  });

  test('unchanged cache extent does not rebuild rows on scroll start or end',
      () {
    final start = source.indexOf('void _setCompactHistoryCacheExtent(');
    final body = source.substring(
        start, source.indexOf('double _effectiveHistoryCacheExtent()', start));
    expect(body,
        contains('if (_effectiveHistoryCacheExtent() != previousExtent)'));
    expect(
        source,
        contains(
            'if (_entryUnreadOrigin != null || !_compactHistoryCacheExtent)'));
  });

  test('positioned unread window keeps newer-direction paging enabled', () {
    final modeStart = source.indexOf('bool _isSearchJumpHistoryMode(');
    final modeEnd = source.indexOf('bool _canProbeLatestHistory(', modeStart);
    final mode = source.substring(modeStart, modeEnd);
    expect(mode, contains('_entryUnreadOrigin != null'));

    final allowStart = source.indexOf('bool _allowsLatestHistoryPagination(');
    final allowEnd =
        source.indexOf('bool _shouldAttemptLatestHistoryLoad(', allowStart);
    final allow = source.substring(allowStart, allowEnd);
    expect(allow, contains('if (_isSearchJumpHistoryMode(globalModel))'));

    final notificationStart =
        source.indexOf('child: NotificationListener<ScrollNotification>');
    final notificationEnd =
        source.indexOf('child: LayoutBuilder(', notificationStart);
    final notifications = source.substring(notificationStart, notificationEnd);
    expect(notifications, contains('notification is OverscrollNotification'));
    expect(notifications, contains('_scheduleLoadLatest('));
  });
}
