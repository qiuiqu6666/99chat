import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global search opens conversation detail without autofocus', () {
    final source = File('lib/src/search.dart').readAsStringSync();
    final callbackStart = source.indexOf('onEnterSearchInConversation:');
    final callbackEnd = source.indexOf('\n                    onTapConversation:', callbackStart);

    expect(callbackStart, greaterThanOrEqualTo(0));
    expect(callbackEnd, greaterThan(callbackStart));

    final callback = source.substring(callbackStart, callbackEnd);
  expect(callback, contains('TIMUIKitSearchMsgDetail('));
  expect(callback, contains('builder: (context) => Search('));
  expect(RegExp(r'TIMUIKitSearchMsgDetail\([\s\S]*?isAutoFocus: false,')
    .hasMatch(callback), isTrue);
  expect(RegExp(r'builder: \(context\) => Search\([\s\S]*?isAutoFocus: false,')
    .hasMatch(callback), isTrue);
  });
}