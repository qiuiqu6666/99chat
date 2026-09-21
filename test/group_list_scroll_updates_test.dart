import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_list_controller.dart';

MeGroupRecord row(String id, String name) => MeGroupRecord(
    groupId: id,
    groupType: 'Public',
    groupName: name,
    displayAlias: '',
    avatarUrl: '',
    notice: '',
    memberCount: 2,
    myRole: 0,
    myNameCard: '',
    joinedAt: 1,
    updatedAt: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final store = GroupLocalStore.instance;
  final controller = MyGroupListController.instance;
  const owner = 'scroll_groups_test';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller.clearSession();
    store.debugOwnerUserIdOverride = owner;
    await store.clearForOwner(owner);
    await store.upsertAll(ownerUserId: owner, records: [row('g1', 'A')]);
    await controller.ensureLoaded(force: true);
  });
  tearDown(() {
    controller.clearSession();
    store.debugOwnerUserIdOverride = null;
  });

  test(
      'multiple commits retain the visible list during scrolling then apply once',
      () async {
    var notifications = 0;
    void onChange() => notifications++;
    controller.addListener(onChange);
    addTearDown(() => controller.removeListener(onChange));
    final original = controller.azShowList;
    controller.setScrolling(true);
    await store.upsertAll(ownerUserId: owner, records: [row('g2', 'B')]);
    await store.upsertAll(
        ownerUserId: owner, records: [row('g2', 'C'), row('g3', 'D')]);
    expect(identical(controller.azShowList, original), isTrue);
    expect(notifications, 0);
    controller.setScrolling(false);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(notifications, 1);
    expect(controller.skeletons.map((e) => e.groupName), ['A', 'C', 'D']);
  });

  test('account reset clears visible and pending rows immediately', () async {
    controller.setScrolling(true);
    await store.upsertAll(ownerUserId: owner, records: [row('g2', 'B')]);
    controller.setScrolling(false);
    controller.clearSession();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(controller.skeletons, isEmpty);
  });
}
