import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/src/pages/group_live/group_live_push_info_page.dart').readAsStringSync();
  test('expired card receives room metadata from the current session', () {
    final call = source.substring(source.indexOf('_ExpiredScheduleCard('),
        source.indexOf('return Column(', source.indexOf('_ExpiredScheduleCard(')));
    expect(call, contains('roomName: session.roomName'));
    expect(call, contains('description: session.description'));
  });
  test('expired card displays both fields and handles empty values', () {
    final card = source.substring(source.indexOf('class _ExpiredScheduleCard'));
    expect(card, contains("zhHans: '直播间昵称'"));
    expect(card, contains("zhHans: '直播描述'"));
    expect(card, contains('roomName.trim().isNotEmpty'));
    expect(card, contains('description.trim().isNotEmpty'));
    expect(card, contains("zhHans: '未设置'"));
    expect(card, isNot(contains('TextOverflow.ellipsis')));
  });
}
