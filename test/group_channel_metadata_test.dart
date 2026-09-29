import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_channel_metadata.dart';

MeGroupRecord row(String id, {bool? channel, String name = 'name'}) =>
    MeGroupRecord.fromJson({
      'groupId': id,
      'groupType': 'Community',
      'groupName': name,
      if (channel != null) 'channel': channel
    });

void main() {
  test(
      'cold IM Community becomes channel from REST without changing IM identity',
      () {
    final result = mergeGroupChannelMetadata(
        sdkRecords: [row('chan', name: 'IM name')],
        businessRecords: [row('chan', channel: true, name: 'older name')]);
    expect(result.single.isChannel, isTrue);
    expect(result.single.groupName, 'IM name');
    expect(result.single.groupType, 'Community');
  });
  test(
      'REST-only channels survive incomplete IM list; ordinary REST groups do not enter it',
      () {
    final result = mergeGroupChannelMetadata(sdkRecords: [], businessRecords: [
      row('channel', channel: true),
      row('ordinary', channel: false)
    ]);
    expect(result.map((e) => e.groupId), ['channel']);
  });
  test(
      'missing business field preserves cached channel and explicit false remains explicit',
      () {
    final cached = row('channel', channel: true);
    expect(
        mergeGroupChannelMetadata(
            sdkRecords: [cached],
            businessRecords: [row('channel')]).single.isChannel,
        isTrue);
    expect(
        mergeGroupChannelMetadata(
            sdkRecords: [cached],
            businessRecords: [row('channel', channel: false)]).single.isChannel,
        isFalse);
  });
  test('equivalent SDK and API ids merge into a single channel', () {
    final result = mergeGroupChannelMetadata(
        sdkRecords: [row('@TGS#_chan')],
        businessRecords: [row('chan', channel: true)]);
    expect(result.length, 1);
    expect(result.single.isChannel, isTrue);
  });
}
