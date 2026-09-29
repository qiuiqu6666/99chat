import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/group_mention_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/chat_id_mention_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/link_preview/common/utils.dart';

void main() {
  group('GroupMentionResolver structured at list', () {
    test('single truncated @C unique-binds one at userId', () {
      const text = '@C 先生 Li的外部托 你好';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001'],
      );
      final members = occurrences
          .where((item) => item.kind == GroupMentionKind.member)
          .toList();
      expect(members, hasLength(1));
      expect(members.single.userId, '1001');
      expect(members.single.displayText, '@C');
    });

    test('alias expands span to full remark', () {
      const text = '@C 先生 Li的外部托 你好';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001'],
        aliasesByUserId: const {
          '1001': ['C 先生 Li的外部托'],
        },
      );
      final hit = occurrences.singleWhere(
        (item) => item.kind == GroupMentionKind.member,
      );
      expect(hit.userId, '1001');
      expect(hit.displayText, '@C 先生 Li的外部托');
      expect(text.substring(hit.start, hit.end), hit.displayText);
    });

    test('two mentions bind by alias not by at-list order', () {
      const text = '@C 先生 Li的外部托 你好 @张三 下午开会';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1002', '1001'],
        aliasesByUserId: const {
          '1001': ['C 先生 Li的外部托'],
          '1002': ['张三'],
        },
      );
      final members = occurrences
          .where((item) => item.kind == GroupMentionKind.member)
          .toList();
      expect(members, hasLength(2));
      expect(members[0].userId, '1001');
      expect(members[0].displayText, '@C 先生 Li的外部托');
      expect(members[1].userId, '1002');
      expect(members[1].displayText, '@张三');
    });

    test('two unknown mentions and one at id do not unique-bind', () {
      const text = '@C xxx @D yyy';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001'],
      );
      expect(
        occurrences.where((item) => item.isMemberWithUserId),
        isEmpty,
      );
    });

    test('at ALL is skipped and remaining unique member can bind', () {
      const text = '@C 先生 Li的外部托';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['__kImSDK_MesssageAtALL__', '1001'],
      );
      final members = occurrences
          .where((item) => item.kind == GroupMentionKind.member)
          .toList();
      expect(members, hasLength(1));
      expect(members.single.userId, '1001');
    });

    test('two IDs and one truncated span without alias do not bind', () {
      const text = '@C 先生 Li的外部托 你好';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001', '1002'],
      );
      expect(
        occurrences.where((item) => item.isMemberWithUserId),
        isEmpty,
      );
    });

    test('legacy longest match without structured ids', () {
      const text = '@C 先生 Li的外部托 你好';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        legacyAliasesByUserId: const {
          '1001': ['C 先生 Li的外部托'],
        },
      );
      final hit = occurrences.singleWhere((item) => item.isMemberWithUserId);
      expect(hit.userId, '1001');
      expect(hit.displayText, '@C 先生 Li的外部托');
    });

    test('no ids and no aliases stay unproven regex spans', () {
      const text = '@C 先生 Li的外部托';
      final occurrences = GroupMentionResolver.resolve(text: text);
      expect(
        occurrences.where((item) => item.isMemberWithUserId),
        isEmpty,
      );
    });

    test('TGS id is occupied before member unique-bind', () {
      const text = 'join @TGS#2HGQG6M5CD and @C 先生';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001'],
      );
      expect(
        occurrences.where((item) => item.kind == GroupMentionKind.chatIdOrGroup),
        hasLength(1),
      );
      expect(
        occurrences
            .where((item) => item.isMemberWithUserId)
            .single
            .userId,
        '1001',
      );
    });

    test('old-message alias can prove the same person twice', () {
      const text = '@冬🐲++++ hi @冬🐲++++';
      final occurrences = GroupMentionResolver.resolve(
        text: text,
        groupAtUserList: const ['1001'],
        aliasesByUserId: const {
          '1001': ['冬🐲++++'],
        },
      );
      final members = occurrences
          .where((item) => item.isMemberWithUserId)
          .toList();
      expect(members, hasLength(2));
      expect(members.every((item) => item.userId == '1001'), isTrue);
    });
  });

  group('GroupMentionOccurrenceCodec UTF-16 offsets', () {
    test('emoji prefix substring matches displayText', () {
      const text = '😀 @C 先生 Li';
      const display = '@C 先生 Li';
      final start = text.indexOf(display);
      final occurrence = GroupMentionOccurrence(
        kind: GroupMentionKind.member,
        start: start,
        end: start + display.length,
        displayText: display,
        userId: '1001',
      );
      expect(text.substring(occurrence.start, occurrence.end), display);
      final encoded = GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
        '{"messageReply":{"version":1}}',
        [occurrence],
      );
      expect(encoded.contains('messageReply'), isTrue);
      final parsed = GroupMentionOccurrenceCodec.parse(
        text: text,
        cloudCustomData: encoded,
      );
      expect(parsed, isNotNull);
      expect(parsed!.single.userId, '1001');
      expect(parsed.single.displayText, display);
    });

    test('wrong code-unit start discards entire metadata', () {
      const text = '😀 @C 先生 Li';
      const display = '@C 先生 Li';
      final encoded = GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
        null,
        [
          GroupMentionOccurrence(
            kind: GroupMentionKind.member,
            start: 2,
            end: 2 + display.length,
            displayText: display,
            userId: '1001',
          ),
        ],
      );
      expect(
        GroupMentionOccurrenceCodec.parse(
          text: text,
          cloudCustomData: encoded,
        ),
        isNull,
      );
    });

    test('insertions use UTF-16 offsets on trimmed send text', () {
      const text = '😀 @C 先生 Li的外部托 你好 @张三';
      final occurrences = GroupMentionResolver.fromInsertions(
        text: text,
        insertions: const [
          GroupMentionInsert(userId: '1001', showName: 'C 先生 Li的外部托'),
          GroupMentionInsert(userId: '1002', showName: '张三'),
        ],
      );
      expect(occurrences, hasLength(2));
      expect(occurrences[0].userId, '1001');
      expect(occurrences[1].userId, '1002');
      for (final item in occurrences) {
        expect(text.substring(item.start, item.end), item.displayText);
      }
    });

    test('new message keeps two occurrences for the same userId', () {
      const text = '@冬🐲++++ and @冬🐲++++';
      final occurrences = GroupMentionResolver.fromInsertions(
        text: text,
        insertions: const [
          GroupMentionInsert(userId: '1001', showName: '冬🐲++++'),
          GroupMentionInsert(userId: '1001', showName: '冬🐲++++'),
        ],
      );
      expect(occurrences, hasLength(2));
      expect(occurrences.every((item) => item.userId == '1001'), isTrue);
    });
  });

  group('wrap and tap token', () {
    test('member wrap tap token is userId not display C', () {
      const text = '@C 先生 Li的外部托';
      final wrapped = LinkUtils.wrapChatIdMentionsForExtendedText(
        text,
        occurrences: const [
          MentionWrapSpan(start: 0, end: 2, memberUserId: '1001'),
        ],
        identityFingerprint: 'm:1001:0:2',
      );
      expect(wrapped.contains('@C'), isTrue);
      expect(wrapped.contains('1001'), isTrue);
      expect(
        ChatIdMentionText.tapToken(
          ChatIdMentionText.encodeSpan('@C', memberUserId: '1001'),
        ),
        '1001',
      );
      expect(ChatIdMentionText.visibleText(
        ChatIdMentionText.encodeSpan('@C', memberUserId: '1001'),
      ), '@C');
    });

    test('chat-id wrap tap token stays parseRawId', () {
      const text = 'see @alice_01';
      final wrapped = LinkUtils.wrapChatIdMentionsForExtendedText(text);
      expect(
        wrapped.contains(
          '${ChatIdMentionText.flag}@alice_01${ChatIdMentionText.flag}',
        ),
        isTrue,
      );
      expect(ChatIdMentionText.tapToken('@alice_01'), 'alice_01');
    });
  });

  group('send-path merge', () {
    test('codec merge keeps messageReply beside occurrences', () {
      const reply = '{"messageReply":{"messageID":"m1","version":1}}';
      final merged = GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
        reply,
        const [
          GroupMentionOccurrence(
            kind: GroupMentionKind.member,
            start: 0,
            end: 2,
            displayText: '@C',
            userId: '1001',
          ),
        ],
      );
      final data = jsonDecode(merged) as Map<String, dynamic>;
      expect(data['messageReply'], isNotNull);
      expect(data['messageReply']['messageID'], 'm1');
      expect(data[GroupMentionOccurrenceCodec.key], isNotNull);
    });

    test('text-at reply field and recreater keep occurrence JSON', () {
      final model = File(
        'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
        'separate_models/tui_chat_separate_view_model.dart',
      ).readAsStringSync();
      final sendAtStart = model.indexOf(
        'Future<V2TimValueCallback<V2TimMessage>?> sendTextAtMessage(',
      );
      final sendAtEnd = model.indexOf(
        'Future<V2TimValueCallback<V2TimMessage>?> sendCustomMessage(',
        sendAtStart,
      );
      final sendAt = model.substring(sendAtStart, sendAtEnd);
      expect(
        sendAt.contains('GroupMentionOccurrenceCodec.mergeIntoCloudCustomData'),
        isTrue,
      );
      expect(sendAt.contains('groupAtUserList: atUserList'), isTrue);

      final replyStart = model.indexOf(
        'Future<V2TimValueCallback<V2TimMessage>?> sendReplyMessage(',
      );
      final replyEnd = model.indexOf(
        'void _notifyCreateMessageFailed(',
        replyStart,
      );
      final reply = model.substring(replyStart, replyEnd);
      expect(reply.contains('"messageReply"'), isTrue);
      expect(
        reply.contains('GroupMentionOccurrenceCodec.mergeIntoCloudCustomData'),
        isTrue,
      );
      expect(reply.contains('groupAtUserList:'), isTrue);

      final field = File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
        'TIMUIKitTextField/tim_uikit_text_field.dart',
      ).readAsStringSync();
      expect(field.contains('GroupMentionResolver.fromInsertions'), isTrue);
      expect(field.contains('mentionOccurrences: mentionOccurrences'), isTrue);

      final recreater = File(
        'lib/src/services/im/outgoing_message_recreator.dart',
      ).readAsStringSync();
      expect(recreater.contains('created.cloudCustomData'), isTrue);
    });
  });
}
