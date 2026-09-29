import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_channel_metadata.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_list_controller.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_group_title_color.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/super_large_group_flame_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = GroupLocalStore.instance;
  final controller = MyGroupListController.instance;
  const owner = 'channel-cold-login-regression';
  MeGroupRecord record(bool? channel) => MeGroupRecord.fromJson({
        'groupId': 'channel-test',
        'groupType': 'Community',
        'groupName': '频道',
        if (channel != null) 'channel': channel,
      });
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    store.debugOwnerUserIdOverride = owner;
    await store.clearForOwner(owner);
  });
  tearDown(() async {
    await store.clearForOwner(owner);
    store.debugOwnerUserIdOverride = null;
  });
  testWidgets(
      'cold channel metadata updates directory and conversation badge without reopening',
      (tester) async {
    await tester.runAsync(() async {
      await store.replaceAll(ownerUserId: owner, records: [record(null)]);
      await controller.ensureLoaded(force: true);
      expect(controller.skeletons.single.isChannel, isFalse);
      await store.replaceAll(
          ownerUserId: owner,
          records: mergeGroupChannelMetadata(
              sdkRecords: [record(null)], businessRecords: [record(true)]));
      expect(controller.skeletons.single.isChannel, isTrue);
    });
    final title = buildGroupConversationListNickName(
        userId: null,
        name: '频道',
        fallbackTitleColor: Colors.black,
        groupType: 'Community',
        groupId: 'channel-test');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: title)));
    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    expect(find.byType(SuperLargeGroupFlameIcon), findsNothing);
    await tester.runAsync(() async {
      // A subsequent SDK snapshot must not erase the business channel marker.
      await store.replaceAll(ownerUserId: owner, records: [record(null)]);
      expect(store.readCached(groupId: 'channel-test')!.isChannel, isTrue);
      expect(controller.skeletons.single.isChannel, isTrue);
    });
  });
}
