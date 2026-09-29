import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';

V2TimGroupMemberFullInfo _member(String id) =>
    V2TimGroupMemberFullInfo(userID: id);

V2TimValueCallback<V2GroupMemberInfoSearchResult> _ok({
  required String groupId,
  required List<V2TimGroupMemberFullInfo> members,
  bool isFinished = true,
  String nextCursor = '',
}) {
  return V2TimValueCallback<V2GroupMemberInfoSearchResult>(
    code: 0,
    desc: 'ok',
    data: V2GroupMemberInfoSearchResult(
      groupMemberSearchResultItems: {groupId: members},
    )
      ..isFinished = isFinished
      ..nextCursor = nextCursor,
  );
}

void main() {
  test('membersForGroup matches exact key, trim, then single-entry map', () {
    final alice = _member('alice');
    final exact = V2GroupMemberInfoSearchResult(
      groupMemberSearchResultItems: {
        'g1': [alice],
      },
    );
    expect(GroupMemberCloudSearch.membersForGroup(exact, 'g1').single.userID,
        'alice');
    expect(
        GroupMemberCloudSearch.membersForGroup(exact, ' g1 ').single.userID,
        'alice');

    final padded = V2GroupMemberInfoSearchResult(
      groupMemberSearchResultItems: {
        ' g1 ': [alice],
      },
    );
    expect(
        GroupMemberCloudSearch.membersForGroup(padded, 'g1').single.userID,
        'alice');

    final only = V2GroupMemberInfoSearchResult(
      groupMemberSearchResultItems: {
        'other': [alice],
      },
    );
    expect(
        GroupMemberCloudSearch.membersForGroup(only, 'g1').single.userID,
        'alice');
  });

  test('empty keyword or empty groupId does not invoke SDK', () async {
    var calls = 0;
    Future<V2TimValueCallback<V2GroupMemberInfoSearchResult>> invoke(
      V2TimGroupMemberSearchParam param,
    ) async {
      calls++;
      return _ok(groupId: 'g1', members: [_member('alice')]);
    }

    final emptyKeyword = await GroupMemberCloudSearch.searchPage(
      groupId: 'g1',
      keyword: '  ',
      invoke: invoke,
    );
    final emptyGroup = await GroupMemberCloudSearch.searchPage(
      groupId: '  ',
      keyword: 'alice',
      invoke: invoke,
    );
    expect(calls, 0);
    expect(emptyKeyword.usedCloud, isFalse);
    expect(emptyGroup.usedCloud, isFalse);
  });

  test('failed cloud search returns usedCloud false', () async {
    final page = await GroupMemberCloudSearch.searchPage(
      groupId: 'g1',
      keyword: 'alice',
      invoke: (_) async => V2TimValueCallback(
        code: 6014,
        desc: 'fail',
      ),
    );
    expect(page.usedCloud, isFalse);
    expect(page.members, isEmpty);
  });

  test('successful empty cloud list keeps usedCloud true', () async {
    final page = await GroupMemberCloudSearch.searchPage(
      groupId: 'g1',
      keyword: 'nobody',
      invoke: (_) async => _ok(groupId: 'g1', members: const []),
    );
    expect(page.usedCloud, isTrue);
    expect(page.members, isEmpty);
  });

  test('web skip does not invoke SDK', () async {
    var calls = 0;
    final page = await GroupMemberCloudSearch.searchPage(
      groupId: 'g1',
      keyword: 'alice',
      skipCloud: true,
      invoke: (_) async {
        calls++;
        return _ok(groupId: 'g1', members: [_member('alice')]);
      },
    );
    expect(calls, 0);
    expect(page.usedCloud, isFalse);
  });

  test('controller empty keyword does not request', () {
    fakeAsync((async) {
      var calls = 0;
      final controller = GroupMemberCloudSearchController(
        groupId: 'g1',
        invoke: (_) async {
          calls++;
          return _ok(groupId: 'g1', members: [_member('alice')]);
        },
      );
      controller.onKeywordChanged('  ');
      async.elapse(const Duration(milliseconds: 400));
      expect(calls, 0);
      expect(controller.usedCloud, isFalse);
      controller.dispose();
    });
  });

  test('controller discards stale generation', () {
    fakeAsync((async) {
      final completers =
          <Completer<V2TimValueCallback<V2GroupMemberInfoSearchResult>>>[];
      final controller = GroupMemberCloudSearchController(
        groupId: 'g1',
        invoke: (_) {
          final completer =
              Completer<V2TimValueCallback<V2GroupMemberInfoSearchResult>>();
          completers.add(completer);
          return completer.future;
        },
      );
      controller.onKeywordChanged('a');
      async.elapse(GroupMemberCloudSearch.debounce);
      controller.onKeywordChanged('b');
      async.elapse(GroupMemberCloudSearch.debounce);
      expect(completers.length, 2);
      completers[0].complete(
        _ok(groupId: 'g1', members: [_member('alice')]),
      );
      async.flushMicrotasks();
      expect(controller.members, isEmpty);
      completers[1].complete(
        _ok(groupId: 'g1', members: [_member('bob')]),
      );
      async.flushMicrotasks();
      expect(controller.usedCloud, isTrue);
      expect(controller.members.single.userID, 'bob');
      controller.dispose();
    });
  });

  test('controller passes original trim keyword and searchCount 100', () {
    fakeAsync((async) {
      late V2TimGroupMemberSearchParam captured;
      final controller = GroupMemberCloudSearchController(
        groupId: 'g1',
        invoke: (param) async {
          captured = param;
          return _ok(groupId: 'g1', members: [_member('alice')]);
        },
      );
      controller.onKeywordChanged('  Alice  ');
      async.elapse(GroupMemberCloudSearch.debounce);
      async.flushMicrotasks();
      expect(captured.keywordList, ['Alice']);
      expect(captured.searchCount, 100);
      expect(captured.groupIDList, ['g1']);
      controller.dispose();
    });
  });

  test('controller cloud failure uses local fallback members', () {
    fakeAsync((async) {
      final controller = GroupMemberCloudSearchController(
        groupId: 'g1',
        invoke: (_) async => V2TimValueCallback(
          code: 8010,
          desc: 'not entitled',
        ),
        localFallback: (keyword) async => [_member('stored_$keyword')],
      );
      controller.onKeywordChanged('发');
      async.elapse(GroupMemberCloudSearch.debounce);
      async.flushMicrotasks();
      expect(controller.usedCloud, isFalse);
      expect(controller.members.single.userID, 'stored_发');
      controller.dispose();
    });
  });
}
