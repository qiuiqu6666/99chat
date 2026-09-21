import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/group_leave_navigation.dart';

Route<void> _route({String? name}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox.shrink(),
  );
}

String _buttonAreaSource() {
  return File(
    'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/'
    'widgets/tim_uikit_group_button_area.dart',
  ).readAsStringSync();
}

String _methodSlice(String src, String startMarker, String endMarker) {
  final start = src.indexOf(startMarker);
  final end = src.indexOf(endMarker, start + startMarker.length);
  expect(start, greaterThanOrEqualTo(0), reason: startMarker);
  expect(end, greaterThan(start), reason: endMarker);
  return src.substring(start, end);
}

void main() {
  test('leave return target recognizes myGroupList and home', () {
    final myGroups = _route(name: AppRoutes.myGroupList);
    final home = _route(name: '/homePage');
    final chat = _route(name: AppRoutes.chat);

    expect(GroupLeaveNavigation.isMyGroupListRoute(myGroups), isTrue);
    expect(GroupLeaveNavigation.isLeaveReturnTarget(myGroups), isTrue);
    expect(GroupLeaveNavigation.isLeaveReturnTarget(home), isTrue);
    expect(GroupLeaveNavigation.isLeaveReturnTarget(chat), isFalse);
  });

  test('quit and dismiss navigate before unawaited remote leave', () {
    final src = _buttonAreaSource();
    expect(src.contains('_completeLeaveSuccess'), isFalse);
    expect(src.contains('_handleLeaveResult'), isFalse);

    final quit = _methodSlice(src, '_quitGroup(BuildContext', '_dismissGroup(');
    final quitNav = quit.indexOf('_navigateAwayAfterConfirmed');
    final quitRemote = quit.indexOf('unawaited(_processRemoteLeaveOrDismiss');
    expect(quitNav, greaterThanOrEqualTo(0));
    expect(quitRemote, greaterThan(quitNav));

    final dismiss = _methodSlice(
      src,
      '_dismissGroup(BuildContext',
      '_transmitOwner(',
    );
    final dismissNav = dismiss.indexOf('_navigateAwayAfterConfirmed');
    final dismissRemote =
        dismiss.indexOf('unawaited(_processRemoteLeaveOrDismiss');
    expect(dismissNav, greaterThanOrEqualTo(0));
    expect(dismissRemote, greaterThan(dismissNav));
  });

  test('remote cleanup does not navigate', () {
    final src = _buttonAreaSource();
    final cleanup = _methodSlice(
      src,
      'Future<void> _cleanupAfterRemoteSuccess()',
      'Future<void> _processRemoteLeaveOrDismiss',
    );
    expect(cleanup.contains('didLeaveGroup'), isFalse);
    expect(cleanup.contains('popUntil'), isFalse);
  });
}
