import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening a group chat starts the notice sheet when the route transition ends',
      () {
    final chat =
        File('lib/src/chat.dart').readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      chat,
      contains(
        '_seedGroupDisplayFromMemory();\n    _armOpenGroupNoticeAfterTransition();',
      ),
    );
    expect(chat, contains('_waitForCurrentRouteTransition()'));
    expect(chat, contains('_presentOpenGroupNoticeAfterTransition('));
    expect(chat, contains('_presentResolvedGroupNotice('));
    expect(chat, isNot(contains('GroupNoticePageOverlay(')));
    expect(chat, isNot(contains('_presentGroupNoticeInPage(')));

    final presentAfterTransition = chat.indexOf(
      'Future<void> _presentOpenGroupNoticeAfterTransition(',
    );
    final wait = chat.indexOf(
      'await _waitForCurrentRouteTransition();',
      presentAfterTransition,
    );
    final present = chat.indexOf(
      'await _presentResolvedGroupNotice(resolved);',
      presentAfterTransition,
    );
    expect(wait, greaterThan(presentAfterTransition));
    expect(present, greaterThan(wait));
  });
}
