import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_add_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';

class _EntryModel extends TUIGroupProfileModel {
  int entries = 0;
  int roles = 0;
  int contacts = 0;
  final gate = Completer<void>();
  bool loading = false;

  @override
  String get groupID => '@TGS#entry-ui';
  @override
  bool get isMemberEntryLoading => loading;
  @override
  Future<void> loadMemberPageOnEntry() async {
    entries++;
    loading = true;
    notifyListeners();
    await gate.future;
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> loadManagementMembers() async {
    roles++;
    notifyListeners();
  }

  @override
  Future<void> loadContactsForPicker() async {
    contacts++;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await ApiClient.instance.saveToken('token', userId: 'entry-ui');
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final previous = FlutterError.onError;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    FlutterError.onError = previous;
    await tester.pump();
    FlutterError.onError = previous;
    expect(tester.takeException(), isNull);
  }

  for (final remove in [false, true]) {
    testWidgets('${remove ? 'remove' : 'member list'} loads on every mount',
        (tester) async {
      final model = _EntryModel();
      Widget page() => remove
          ? DeleteGroupMemberPage(model: model)
          : GroupProfileMemberListPage(memberList: [], model: model);
      await pump(tester, page());
      expect(model.entries, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pump(tester, const SizedBox.shrink());
      await pump(tester, page());
      expect(model.entries, 2);
      await pump(tester, const SizedBox.shrink());
      model.gate.complete();
      await tester.pump();
      model.dispose();
    });
  }

  for (final title in ['添加管理员', '禁言成员']) {
    testWidgets('$title waits for entry data and retries after failure',
        (tester) async {
      var attempts = 0;
      await pump(
          tester,
          GroupProfileAddAdmin(
            groupID: '@TGS#entry-ui',
            memberList: const [],
            appbarTitle: title,
            loadMembersOnEntry: () async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
            },
          ));
      await tester.pump();
      expect(attempts, 1);
      expect(find.text('群成员加载失败，点击重试'), findsOneWidget);
      await tester.tap(find.text('群成员加载失败，点击重试'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('群成员加载失败，点击重试'), findsNothing);
      await pump(tester, const SizedBox.shrink());
    });
  }

  testWidgets(
      'setting managers loads roles without prefetching ordinary candidates',
      (tester) async {
    final model = _EntryModel();
    await pump(tester, GroupProfileSetManagerPage(model: model));
    expect(model.roles, 1);
    expect(model.entries, 0);
    await pump(tester, const SizedBox.shrink());
    model.dispose();
  });

  testWidgets(
      'invite lookup runs once per entry and old member window does not disable contacts',
      (tester) async {
    final model = _EntryModel()
      ..contactList = [
        V2TimFriendInfo(
            userID: 'friend',
            userProfile:
                V2TimUserFullInfo(userID: 'friend', nickName: 'Friend'))
      ]
      ..groupMemberList = [V2TimGroupMemberFullInfo(userID: 'friend')];
    var lookups = 0;
    final found = Completer<Set<String>>();
    await pump(
        tester,
        AddGroupMemberPage(
          model: model,
          existingMemberUserIdsLoader: (ids) {
            lookups++;
            expect(ids, ['friend']);
            return found.future;
          },
        ));
    expect(model.contacts, 1);
    expect(lookups, 1);
    found.complete({});
    await tester.pump();
    await tester.pump();
    final contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.groupMemberList, isEmpty);
    expect(contacts.disabledUserIds, isNot(contains('friend')));
    expect(model.entries, 0);
    await pump(tester, const SizedBox.shrink());
    model.dispose();
  });

  testWidgets(
      'invite membership failure shows retry instead of enabling unchecked contacts',
      (tester) async {
    final model = _EntryModel()
      ..contactList = [V2TimFriendInfo(userID: 'friend')];
    var attempts = 0;
    await pump(
        tester,
        AddGroupMemberPage(
          model: model,
          existingMemberUserIdsLoader: (_) async {
            attempts++;
            if (attempts == 1) throw StateError('offline');
            return {'friend'};
          },
        ));
    await tester.pump();
    expect(find.byType(ContactList), findsNothing);
    expect(find.text('群成员加载失败，点击重试'), findsOneWidget);
    await tester.tap(find.text('群成员加载失败，点击重试'));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    final contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.disabledUserIds, contains('friend'));
    await pump(tester, const SizedBox.shrink());
    model.dispose();
  });
}
