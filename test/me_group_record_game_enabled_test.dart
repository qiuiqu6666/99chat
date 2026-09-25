import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';

void main() {
  group('MeGroupRecord.gameEnabled', () {
    Map<String, dynamic> groupJson([Map<String, dynamic>? extra]) {
      return <String, dynamic>{
        'groupId': '@TGS#test',
        'groupType': 'Public',
        'groupName': '测试群',
        ...?extra,
      };
    }

    test('parses camelCase and snake_case values', () {
      expect(
        MeGroupRecord.fromJson(
          groupJson(<String, dynamic>{'gameEnabled': true}),
        ).gameEnabled,
        isTrue,
      );
      expect(
        MeGroupRecord.fromJson(
          groupJson(<String, dynamic>{'game_enabled': 1}),
        ).gameEnabled,
        isTrue,
      );
    });

    test('defaults missing and invalid values to false', () {
      expect(MeGroupRecord.fromJson(groupJson()).gameEnabled, isFalse);
      expect(
        MeGroupRecord.fromJson(
          groupJson(<String, dynamic>{'gameEnabled': 'invalid'}),
        ).gameEnabled,
        isFalse,
      );
    });

    test('copyWith preserves and updates value', () {
      final record = MeGroupRecord.fromJson(
        groupJson(<String, dynamic>{'gameEnabled': true}),
      );
      expect(record.copyWith().gameEnabled, isTrue);
      expect(record.copyWith(gameEnabled: false).gameEnabled, isFalse);
    });
  });

  test('Community channel marker survives partial IM profile updates', () {
    final channel = MeGroupRecord.fromJson({
      'groupId': '@TGS#channel',
      'groupType': 'Community',
      'groupName': '公告频道',
      'channel': true,
    });
    expect(channel.isChannel, isTrue);
    expect(channel.copyWith(groupName: '新名称').isChannel, isTrue);
    final partial = MeGroupRecord.fromJson({
      'groupId': '@TGS#channel',
      'groupType': 'Community',
      'groupName': '新名称',
    });
    expect(partial.resolvingMissingFieldsFrom(channel).isChannel, isTrue);
    expect(MeGroupRecord.fromJson({
      'groupId': '@TGS#super',
      'groupType': 'Community',
      'groupName': '超级大群',
    }).isChannel, isFalse);
  });
}
