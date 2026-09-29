import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_change_journal.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_folder_unread_index.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_fingerprint.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_content_patch.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';

V2TimConversation _row(String id, {int unread = 0}) =>
    V2TimConversation(conversationID: id, unreadCount: unread);

class _CountedText extends V2TimTextElem {
  _CountedText() : super(text: 'before');
  int encodes = 0;
  @override
  Map<String, dynamic> toJson() {
    encodes++;
    return super.toJson();
  }
}

void main() {
  test('separate consumers retain all deltas until their own revision', () {
    final journal = ConversationChangeJournal();
    journal.record(1, {'c2c_a'});
    journal.record(2, {'c2c_b'});
    journal.record(3, {'c2c_a'});
    expect(journal.changesSince(0), {'c2c_a', 'c2c_b'});
    expect(journal.changesSince(2), {'c2c_a'});
    expect(journal.changesSince(3), isEmpty);
  });

  test('overflow, structural changes and reset require a full fallback', () {
    final journal = ConversationChangeJournal(capacity: 2);
    journal.record(1, {'a'});
    journal.record(2, {'b'});
    journal.record(3, {'c'});
    expect(journal.changesSince(0), isNull);
    expect(journal.changesSince(1), {'b', 'c'});
    journal.record(4, null);
    expect(journal.changesSince(3), isNull);
    journal.reset(revision: 5);
    expect(journal.changesSince(4), isNull);
    expect(journal.changesSince(5), isEmpty);
  });

  test('only one changed visible row is read from a 5000-row projection', () {
    final rows = List.generate(5000, (i) => _row('c2c_$i'));
    final positions = {for (var i = 0; i < rows.length; i++) 'c2c_$i': i};
    final replacement = _row('c2c_3000', unread: 4);
    var reads = 0;
    final result = patchConversationContents(
      current: rows,
      positions: positions,
      changedIds: {'c2c_3000', 'c2c_other'},
      lookup: (id) {
        reads++;
        return replacement;
      },
    )!;
    expect(reads, 1);
    expect(result[3000], same(replacement));
    expect(rows[3000].unreadCount, 0);
    expect(result[2999], same(rows[2999]));
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('unrelated changes preserve the view without allocation or lookups', () {
    final rows = [_row('c2c_a')];
    final result = patchConversationContents(
      current: rows,
      positions: {'c2c_a': 0},
      changedIds: {'c2c_b'},
      lookup: (_) => throw StateError('unrelated lookup'),
    );
    expect(result, same(rows));
  });

  test('deleted or reidentified rows request full reconstruction', () {
    final rows = [_row('c2c_a')];
    for (final result in [null, _row('c2c_different')]) {
      expect(
          patchConversationContents(
            current: rows,
            positions: {'c2c_a': 0},
            changedIds: {'c2c_a'},
            lookup: (_) => result,
          ),
          isNull);
    }
  });

  test('preview scheduling reads observed IDs and includes folder supplements',
      () {
    final rows = {for (var i = 0; i < 5000; i++) 'c2c_$i': _row('c2c_$i')};
    final supplements = {'c2c_folder': _row('c2c_folder')};
    var reads = 0;
    final resolved = resolveObservedConversationRows(
      observedIds: ['c2c_4000', 'c2c_folder', 'c2c_missing'],
      lookup: (id) {
        reads++;
        return rows[id] ?? supplements[id];
      },
    ).toList();
    expect(reads, 3);
    expect(
        resolved.map((row) => row.conversationID), ['c2c_4000', 'c2c_folder']);
  });

  test('a preview capture encodes once and detects the next in-place edit', () {
    final text = _CountedText();
    final message = V2TimMessage.fromJson({
      'message_msg_id': 'same',
      'message_server_time': 1700000000,
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..textElem = text;
    ConversationPreviewToken capture() => ConversationPreviewToken(
          message: message,
          conversationKey: 'c2c_a',
          listRevision: 0,
          projectionRevision: 0,
        );
    final first = capture();
    expect(text.encodes, 1);
    final fingerprint = first.messageFingerprint;
    expect(first.messageFingerprint, fingerprint);
    expect(text.encodes, 1);
    text.text = 'after';
    final second = capture();
    expect(text.encodes, 2);
    expect(second.messageFingerprint, isNot(fingerprint));
    expect(second.token, isNot(first.token));
  });

  test(
      'one folder member update queries only that member and touches its folders',
      () {
    final index = ConversationFolderUnreadIndex();
    index.rebuild({
      for (var f = 0; f < 50; f++)
        'folder$f': List.generate(100, (i) => 'c2c_${f * 100 + i}'),
      'shared': ['c2c_2000'],
    });
    index.applyCounts({for (var i = 0; i < 5000; i++) 'c2c_$i': 1});
    expect(index.queryIdsForChanges({'c2c_2000', 'c2c_outside'}), {'c2c_2000'});
    expect(index.applyCounts({'c2c_2000': 3}), {'folder20', 'shared'});
    expect(index.totals['folder20'], 102);
    expect(index.totals['shared'], 3);
    expect(index.totals['folder21'], 100);
  });

  test('folder aliases deduplicate and C2C/group identities remain separate',
      () {
    final index = ConversationFolderUnreadIndex();
    index.rebuild({
      'people': ['c2c_same', 'same'],
      'groups': ['group_same', 'group_@TGS#alias', '@TGS#alias'],
    });
    index.applyCounts({'c2c_same': 2, 'group_same': 5, 'group_@TGS#alias': 7});
    expect(index.totals, {'people': 2, 'groups': 12});
    expect(index.queryIdsForChanges({'c2c_same'}), {'c2c_same'});
    expect(index.queryIdsForChanges({'group_same'}), {'group_same'});
    index.applyCounts({'group_same': 0});
    expect(index.totals, {'people': 2, 'groups': 7});
  });

  test('folder membership rebuild removes departed and archived contributions',
      () {
    final index = ConversationFolderUnreadIndex();
    index.rebuild({
      'old': ['c2c_a', 'c2c_b']
    });
    index.applyCounts({'c2c_a': 3, 'c2c_b': 7});
    index.rebuild({
      'new': ['c2c_a'],
      'empty': []
    });
    index.applyCounts({'c2c_a': 3});
    expect(index.queryIdsForChanges({'c2c_b'}), isEmpty);
    expect(index.totals, {'new': 3, 'empty': 0});
    index.rebuild({});
    expect(index.totals, isEmpty);
  });
}
