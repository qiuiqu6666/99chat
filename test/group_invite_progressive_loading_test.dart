import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_operation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_add_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';

class _InviteModel extends TUIGroupProfileModel {
  int contactLoads = 0;
  List<String>? invited;

  @override
  String get groupID => '@TGS#progressive-invite';

  @override
  Future<void> loadContactsForPicker() async {
    contactLoads++;
  }

  @override
  Future<V2TimValueCallback<List<V2TimGroupMemberOperationResult>>>
      inviteUserToGroup(List<String> userIDS) async {
    invited = userIDS;
    return V2TimValueCallback(code: 0, desc: 'ok', data: []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  void Function(FlutterErrorDetails)? testErrorHandler;
  DeviceType? testDeviceType;
  setUp(() {
    testErrorHandler = null;
    testDeviceType = null;
    ImSdkRelationshipDirectory.instance.reset();
    GroupMemberStore.instance.clear(notify: false);
  });

  Future<void> frame(WidgetTester tester) async {
    if (testDeviceType != null) TUIKitScreenUtils.deviceType = testDeviceType;
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(tester.takeException(), isNull);
  }

  tearDown(ImSdkRelationshipDirectory.instance.reset);
  tearDown(() => GroupMemberStore.instance.clear(notify: false));

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    testErrorHandler ??= FlutterError.onError;
    if (testDeviceType != null) TUIKitScreenUtils.deviceType = testDeviceType;
    final handler = FlutterError.onError;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    FlutterError.onError = handler;
    await frame(tester);
    FlutterError.onError = handler;
    expect(tester.takeException(), isNull);
  }

  _InviteModel modelWithFriends(int count) => _InviteModel()
    ..contactList = [
      for (var i = 0; i < count; i++)
        V2TimFriendInfo(
          userID: 'friend${i.toString().padLeft(5, '0')}',
          friendRemark: 'A${i.toString().padLeft(5, '0')}',
        ),
    ];

  testWidgets('removed contact can be selected and stays selectable on reentry',
      (tester) async {
    final model = modelWithFriends(2);
    Widget page() => AddGroupMemberPage(
          key: addGroupMemberKey,
          model: model,
          onClose: () {},
          existingMemberUserIdsLoader: (_) async =>
              {'friend00000', 'friend00001'},
        );
    await pumpPage(tester, page());
    await frame(tester);
    expect(tester.widget<ContactList>(find.byType(ContactList)).disabledUserIds,
        containsAll(['friend00000', 'friend00001']));

    GroupMemberStore.instance
        .removeMembers('group_${model.groupID}', ['@friend00000']);
    await tester.pump(const Duration(milliseconds: 50));
    await frame(tester);
    await frame(tester);
    var contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.disabledUserIds, isNot(contains('friend00000')));
    expect(contacts.disabledUserIds, contains('friend00001'));
    await tester.tap(find.text('A00000'));
    await frame(tester);
    expect(find.text('1/100'), findsOneWidget);
    // A stale response on the next entry must not restore the disabled badge.
    await pumpPage(tester, const SizedBox.shrink());
    await pumpPage(tester, page());
    await frame(tester);
    contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.disabledUserIds, isNot(contains('friend00000')));
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('1/100'), findsOneWidget);
    await addGroupMemberKey.currentState!.submitAdd();
    expect(model.invited, ['friend00000']);
    await pumpPage(tester, const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('10,000 friends paint and can submit after only the first batch',
      (tester) async {
    final model = modelWithFriends(10000);
    final first = Completer<Set<String>>();
    final remaining = Completer<Set<String>>();
    final batches = <List<String>>[];
    var closed = false;
    await pumpPage(
        tester,
        AddGroupMemberPage(
          key: addGroupMemberKey,
          model: model,
          onClose: () => closed = true,
          existingMemberUserIdsLoader: (ids) {
            batches.add(ids);
            return batches.length == 1 ? first.future : remaining.future;
          },
        ));
    expect(batches.single, hasLength(50));
    expect(find.byType(ContactList), findsNothing);

    first.complete({'friend00000'});
    await frame(tester);
    await frame(tester);
    final contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.contactList, hasLength(50));
    expect(contacts.disabledUserIds, contains('friend00000'));
    expect(remaining.isCompleted, isFalse);
    expect(find.text('A00001'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('49/100'), findsOneWidget);
    await addGroupMemberKey.currentState!.submitAdd();
    expect(model.invited, hasLength(49));
    expect(model.invited, isNot(contains('friend00000')));
    expect(closed, isTrue);

    await pumpPage(tester, const SizedBox.shrink());
    final requestedBeforeClose = batches.length;
    remaining.complete({});
    await frame(tester);
    expect(batches, hasLength(requestedBeforeClose));
    expect(tester.takeException(), isNull);
    model.dispose();
  });

  testWidgets(
      'background failure preserves selection and retries unchecked ids',
      (tester) async {
    final model = modelWithFriends(120);
    final second = Completer<Set<String>>();
    final batches = <List<String>>[];
    await pumpPage(
        tester,
        AddGroupMemberPage(
          model: model,
          existingMemberUserIdsLoader: (ids) {
            batches.add(ids);
            if (batches.length == 2) return second.future;
            return Future.value(<String>{});
          },
        ));
    await frame(tester);
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('50/100'), findsOneWidget);

    second.completeError(StateError('offline'));
    await frame(tester);
    await frame(tester);
    expect(find.byType(ContactList), findsOneWidget);
    expect(find.text('50/100'), findsOneWidget);
    await tester.tap(find.text('群成员加载失败，点击重试'));
    for (var i = 0; i < 5; i++) {
      await frame(tester);
    }
    expect(batches[2], batches[1]);
    expect(model.contactLoads, 1);
    expect(tester.widget<ContactList>(find.byType(ContactList)).contactList,
        hasLength(120));
    expect(find.text('50/100'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('100/100'), findsOneWidget);
    await tester.tap(find.text('取消全选'));
    await frame(tester);
    expect(find.text('0/100'), findsOneWidget);
    await pumpPage(tester, const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('search and late pending metadata reconcile the selection count',
      (tester) async {
    final model = modelWithFriends(3);
    final pending = Completer<Set<String>>();
    await pumpPage(
        tester,
        AddGroupMemberPage(
          model: model,
          existingMemberUserIdsLoader: (_) async => {},
          pendingReviewUserIdsLoader: () => pending.future,
        ));
    await frame(tester);
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('3/100'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A00001');
    await frame(tester);
    expect(find.text('3/100'), findsOneWidget);
    pending.complete({'friend00001'});
    await frame(tester);
    await frame(tester);
    expect(find.text('2/100'), findsOneWidget);
    expect(find.text('进群审核中'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await frame(tester);
    expect(find.text('2/100'), findsOneWidget);
    await pumpPage(tester, const SizedBox.shrink());
    model.dispose();
  });

  testWidgets(
      'cached friends load immediately and live changes invalidate a batch',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    RelationshipFriendEntry friend(int index) {
      final id = 'friend${index.toString().padLeft(5, '0')}';
      final name = 'A${index.toString().padLeft(5, '0')}';
      return RelationshipFriendEntry(
        userId: id,
        displayName: name,
        faceUrl: '',
        remark: name,
        sortKey: ImSdkRelationshipDirectory.sortKeyFor(
          id: id,
          displayName: name,
          azTag: 'A',
        ),
      );
    }

    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [for (var i = 0; i < 51; i++) friend(i)],
    );
    final model = _InviteModel();
    final oldBatch = Completer<Set<String>>();
    final freshBatch = Completer<Set<String>>();
    final batches = <List<String>>[];
    await pumpPage(
        tester,
        AddGroupMemberPage(
          model: model,
          existingMemberUserIdsLoader: (ids) {
            batches.add(ids);
            if (batches.length == 1) return Future.value(<String>{});
            return batches.length == 2 ? oldBatch.future : freshBatch.future;
          },
        ));
    await frame(tester);
    expect(model.contactLoads, 0);
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('50/100'), findsOneWidget);

    directory.applyFriendRemoves(['friend00000']);
    directory.applyFriendAdds([friend(51)]);
    await frame(tester);
    await frame(tester);
    expect(find.text('49/100'), findsOneWidget);
    oldBatch.complete({'friend00050'});
    await frame(tester);
    expect(batches.last, ['friend00050', 'friend00051']);
    expect(tester.widget<ContactList>(find.byType(ContactList)).contactList,
        hasLength(49));

    freshBatch.complete({'friend00051'});
    await frame(tester);
    await frame(tester);
    final contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.contactList, hasLength(51));
    expect(contacts.disabledUserIds, contains('friend00051'));
    expect(contacts.disabledUserIds, isNot(contains('friend00050')));
    await tester.tap(find.text('全选'));
    await frame(tester);
    expect(find.text('50/100'), findsOneWidget);
    await pumpPage(tester, const SizedBox.shrink());
    model.dispose();
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('selection count follows individual toggles at width $width',
        (tester) async {
      try {
        // Native macOS tests otherwise always select the desktop branch.
        final previousDeviceType = TUIKitScreenUtils.deviceType;
        addTearDown(() => TUIKitScreenUtils.deviceType = previousDeviceType);
        testDeviceType = width == 390 ? DeviceType.Mobile : DeviceType.Desktop;
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final model = modelWithFriends(2);
        await pumpPage(
            tester,
            AddGroupMemberPage(
              model: model,
              existingMemberUserIdsLoader: (_) async => {},
            ));
        await frame(tester);
        expect(find.text('0/100'), findsOneWidget);
        await tester.tap(find.text('全选'));
        await frame(tester);
        expect(find.text('2/100'), findsOneWidget);
        if (width == 390) {
          expect(find.text('${TIM_t("确定")} (2)'), findsOneWidget);
        }
        await tester.tap(find.text('A00000'));
        await frame(tester);
        expect(find.text('1/100'), findsOneWidget);
        await tester.tap(find.text('A00001'));
        await frame(tester);
        expect(find.text('0/100'), findsOneWidget);
        await pumpPage(tester, const SizedBox.shrink());
        model.dispose();
      } finally {
        FlutterError.onError = testErrorHandler;
      }
    });
  }
}
