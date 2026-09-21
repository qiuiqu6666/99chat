import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String model;

  setUpAll(() {
    model = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_separate_view_model.dart',
    ).readAsStringSync();
  });

  test('delete commits through Writer before SDK commit', () {
    final start = model.indexOf('deleteMsg(String msgID');
    expect(start, greaterThanOrEqualTo(0));
    final commitStart = model.indexOf('Future<void> _commitDeleteToSdk');
    expect(commitStart, greaterThan(start));
    final body = model.substring(start, commitStart);
    expect(body.contains('commitMessageDelta'), isTrue);
    expect(body.contains('MessageDeltaKind.delete'), isTrue);
    expect(body.contains('_commitDeleteToSdk'), isTrue);
    expect(
      body.indexOf('commitMessageDelta'),
      lessThan(body.indexOf('_commitDeleteToSdk')),
    );
    expect(body.contains('await _messageService.deleteMessages'), isFalse);
  });

  test('self-revoke commits through Writer and does not modifyMessage first',
      () {
    final start = model.indexOf('Future<Object?> revokeMsg(');
    expect(start, greaterThanOrEqualTo(0));
    final commitStart = model.indexOf('Future<void> _commitRevokeToSdk');
    expect(commitStart, greaterThan(start));
    final body = model.substring(start, commitStart);
    expect(body.contains('commitMessageDelta'), isTrue);
    expect(body.contains('MessageDeltaKind.revoke'), isTrue);
    expect(body.contains('_revokedMessageCopy'), isTrue);
    expect(body.contains('_commitRevokeToSdk'), isTrue);
    expect(
      body.contains('mergedAliasMessageList') ||
          body.contains('_findRevokeTarget'),
      isTrue,
    );
    expect(
      body.indexOf('commitMessageDelta'),
      lessThan(body.indexOf('_commitRevokeToSdk')),
    );
    expect(
      body.contains('if (chatConfig.isGroupAdminRecallEnabled)'),
      isFalse,
    );
  });

  test('admin revoke still uses modifyMessage only when isAdmin', () {
    final start = model.indexOf('Future<void> _commitRevokeToSdk');
    expect(start, greaterThanOrEqualTo(0));
    final end = model.indexOf('  setMessageItemChecked(', start);
    expect(end, greaterThan(start));
    final body = model.substring(start, end);
    expect(
      body.contains('isAdmin &&') && body.contains('modifyMessage'),
      isTrue,
    );
    expect(body.contains('revokeMessage'), isTrue);
    final revokeCallStart = body.indexOf('revokeMessage(');
    expect(revokeCallStart, greaterThanOrEqualTo(0));
    final revokeCallEnd = body.indexOf(');', revokeCallStart);
    expect(revokeCallEnd, greaterThan(revokeCallStart));
    expect(
      body.substring(revokeCallStart, revokeCallEnd).contains('message:'),
      isTrue,
    );
  });
}
