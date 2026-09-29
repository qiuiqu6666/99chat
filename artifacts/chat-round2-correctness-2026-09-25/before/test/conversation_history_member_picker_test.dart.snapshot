import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_result.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_conversation_member_picker_page.dart';

typedef _Page = V2TimValueCallback<V2TimGroupMemberInfoResult>;

_Page _page(List<V2TimGroupMemberFullInfo> members,
        {String next = '0', String desc = 'ok'}) =>
    V2TimValueCallback(
        code: 0,
        desc: desc,
        data:
            V2TimGroupMemberInfoResult(memberInfoList: members, nextSeq: next));

V2TimGroupMemberFullInfo member(String id) =>
    V2TimGroupMemberFullInfo(userID: id, nickName: id);

class _Groups implements GroupServices {
  _Groups(this.load);
  final Future<_Page> Function(String) load;
  final List<String> cursors = [];
  @override
  Future<_Page> getGroupMemberList(
      {required String groupID,
      required GroupMemberFilterTypeEnum filter,
      required String nextSeq,
      int count = 15,
      int offset = 0}) {
    cursors.add(nextSeq);
    return load(nextSeq);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Friends implements FriendshipServices {
  @override
  Future<List<V2TimUserStatus>> getUserStatus(
          {required List<String> userIDList}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  void Function(FlutterErrorDetails)? errorHandler;
  setUp(() {
    errorHandler = FlutterError.onError;
    SelfHostedGroupBridge.clear();
  });
  Future<void> frame(WidgetTester tester,
      [Duration duration = Duration.zero]) async {
    await tester.pump(duration);
    FlutterError.onError = errorHandler;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    FlutterError.onError = errorHandler;
  }

  tearDown(() => SelfHostedGroupBridge.clear());

  Future<void> mount(WidgetTester tester, _Groups groups,
      {GroupMemberCloudSearchInvoke? search}) async {
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(groups);
    await serviceLocator.unregister<FriendshipServices>();
    serviceLocator.registerSingleton<FriendshipServices>(_Friends());
    final handler = FlutterError.onError;
    errorHandler = handler;
    await tester.pumpWidget(MaterialApp(
      home: TIMUIKitConversationMemberPickerPage(
        groupId: '@TGS#history-pick',
        cloudSearchInvoke: search ??
            (_) async =>
                V2TimValueCallback(code: -1, desc: 'cloud unavailable'),
      ),
    ));
    FlutterError.onError = handler;
    await frame(tester);
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    FlutterError.onError = errorHandler;
    await frame(tester, const Duration(milliseconds: 350));
    await frame(tester);
  }

  V2TimValueCallback<V2GroupMemberInfoSearchResult> cloudPage(
          List<V2TimGroupMemberFullInfo> members,
          {String next = ''}) =>
      V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: V2GroupMemberInfoSearchResult(
            groupMemberSearchResultItems: {'@TGS#history-pick': members},
          )
            ..nextCursor = next
            ..isFinished = next.isEmpty);

  testWidgets('page failure retains rows and retries the missing cursor',
      (tester) async {
    var fail = true;
    final groups = _Groups((cursor) async {
      if (cursor == '0') return _page([member('first')], next: 'sdk:page2');
      if (fail) return V2TimValueCallback(code: -1, desc: 'offline');
      return _page([member('last')]);
    });
    await mount(tester, groups);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('群成员加载失败，点击重试'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('群成员加载失败，点击重试'));
    await settle(tester);
    expect(groups.cursors, ['0', 'sdk:page2', 'sdk:page2']);
    expect(find.text('last'), findsOneWidget);
    expect(find.text('群成员加载失败，点击重试'), findsNothing);
  });

  testWidgets('nickname and name card remain searchable when a remark is shown',
      (tester) async {
    final groups = _Groups((_) async => _page([
          V2TimGroupMemberFullInfo(
              userID: 'alias-user',
              friendRemark: 'Remark',
              nickName: 'OriginalName',
              nameCard: 'GroupCard'),
        ]));
    await mount(tester, groups);
    expect(find.text('Remark'), findsOneWidget);
    for (final keyword in ['OriginalName', 'GroupCard', 'alias-user']) {
      await tester.enterText(find.byType(TextField), keyword);
      FlutterError.onError = errorHandler;
      await frame(tester);
      expect(find.text('Remark'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loads every page and searches a member beyond the first 100',
      (tester) async {
    final groups = _Groups((cursor) async {
      final start = int.tryParse(cursor) ?? 0;
      return _page(
          [for (var i = start; i < start + 100; i++) member('member-$i')],
          next: start < 200 ? '${start + 100}' : '0');
    });
    await mount(tester, groups);
    expect(groups.cursors, ['0', '100', '200']);
    await query(tester, 'member-299');
    expect(
        find.descendant(
            of: find.byType(ListView), matching: find.text('member-299')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cache failure does not prevent fetching remote members',
      (tester) async {
    SelfHostedGroupBridge.configure(
        loadGroupsInfo: (_) async => [],
        loadCachedGroupMemberList: (_) async =>
            throw StateError('cache unavailable'));
    final groups = _Groups((_) async => _page([member('remote-member')]));
    await mount(tester, groups);
    expect(groups.cursors, ['0']);
    expect(find.text('remote-member'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cached fallback is incomplete and remote retry drops stale members',
      (tester) async {
    SelfHostedGroupBridge.configure(
        loadGroupsInfo: (_) async => [],
        loadCachedGroupMemberList: (_) async => [member('stale-member')]);
    var offline = true;
    final groups = _Groups((_) async => offline
        ? _page([member('cached-member')], desc: 'cached_page')
        : _page([member('fresh-member')]));
    await mount(tester, groups);
    expect(find.text('stale-member'), findsOneWidget);
    expect(find.text('cached-member'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-list-retry')), findsOneWidget);
    offline = false;
    await tester.tap(find.byKey(const ValueKey('member-list-retry')));
    await settle(tester);
    expect(groups.cursors, ['0', '0']);
    expect(find.text('stale-member'), findsNothing);
    expect(find.text('cached-member'), findsNothing);
    expect(find.text('fresh-member'), findsOneWidget);
  });

  testWidgets(
      'repeated cursor stops without an infinite loop or duplicate rows',
      (tester) async {
    final groups =
        _Groups((_) async => _page([member('same-member')], next: 'repeat'));
    await mount(tester, groups);
    expect(groups.cursors, ['0', 'repeat']);
    expect(find.text('same-member'), findsOneWidget);
    expect(find.text('群成员加载失败，点击重试'), findsOneWidget);
  });

  testWidgets('automatic batch limit leaves a working continuation',
      (tester) async {
    final groups = _Groups((cursor) async {
      final index = int.parse(cursor);
      return _page([member('member-$index')],
          next: index < 100 ? '${index + 1}' : '0');
    });
    await mount(tester, groups);
    expect(groups.cursors.length, 100);
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('member-list-retry')));
    await settle(tester);
    expect(groups.cursors.length, 101);
    await query(tester, 'member-100');
    expect(
        find.descendant(
            of: find.byType(ListView), matching: find.text('member-100')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'cloud search finds members while ordinary paging is still pending',
      (tester) async {
    final pending = Completer<_Page>();
    final groups = _Groups((cursor) async => cursor == '0'
        ? _page([member('first-member')], next: 'next')
        : await pending.future);
    await mount(tester, groups, search: (param) async {
      expect(param.groupIDList, ['@TGS#history-pick']);
      expect(param.keywordList, ['remote']);
      return cloudPage([member('remote-member')]);
    });
    await query(tester, 'remote');
    expect(find.text('remote-member'), findsOneWidget);
    pending.complete(_page([]));
    await frame(tester);
    expect(find.text('remote-member'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'old search replies cannot replace a new query or a cleared query',
      (tester) async {
    final old = Completer<V2TimValueCallback<V2GroupMemberInfoSearchResult>>();
    final groups = _Groups((_) async => _page([member('list-member')]));
    await mount(tester, groups,
        search: (param) async => param.keywordList.first == 'old'
            ? await old.future
            : cloudPage([member('new-member')]));
    await query(tester, 'old');
    await query(tester, 'new');
    expect(find.text('new-member'), findsOneWidget);
    expect(find.text('old-member'), findsNothing);
    await query(tester, '');
    old.complete(cloudPage([member('old-member')]));
    await frame(tester);
    expect(find.text('list-member'), findsOneWidget);
    expect(find.text('old-member'), findsNothing);
    expect(find.text('new-member'), findsNothing);
  });

  testWidgets('cloud result pagination continues and deduplicates members',
      (tester) async {
    final cursors = <String>[];
    final groups = _Groups((_) async => _page([]));
    await mount(tester, groups, search: (param) async {
      cursors.add(param.searchCursor);
      if ((param.searchCursor).isEmpty) {
        return cloudPage([member('match-one')], next: 'page-two');
      }
      return cloudPage([member('match-one'), member('match-two')]);
    });
    await query(tester, 'match');
    expect(find.text('match-one'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('member-search-more')));
    await settle(tester);
    expect(cursors, ['', 'page-two']);
    expect(find.text('match-one'), findsOneWidget);
    expect(find.text('match-two'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-search-more')), findsNothing);
  });

  testWidgets('search page failure retains results and offers a fresh retry',
      (tester) async {
    var fail = false;
    final groups =
        _Groups((_) async => V2TimValueCallback(code: -1, desc: 'offline'));
    await mount(tester, groups, search: (param) async {
      if (fail) return V2TimValueCallback(code: -1, desc: 'search offline');
      return cloudPage([member('found-member')], next: 'search-next');
    });
    await query(tester, 'found');
    fail = true;
    await tester.tap(find.byKey(const ValueKey('member-search-more')));
    await settle(tester);
    expect(find.text('found-member'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-search-retry')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('member-search-retry')));
    await frame(tester, const Duration(milliseconds: 350));
    await frame(tester);
    expect(find.text('found-member'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-search-retry')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a late member reply after closing the picker is ignored',
      (tester) async {
    final pending = Completer<_Page>();
    await mount(tester, _Groups((_) => pending.future));
    await tester.pumpWidget(const SizedBox());
    pending.complete(_page([member('late-member')]));
    await frame(tester);
    expect(tester.takeException(), isNull);
  });
}
