import 'dart:convert';

import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_at_mention.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/chat_id_mention_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/link_preview/common/utils.dart';

enum GroupMentionKind { member, chatIdOrGroup, atAll }

class GroupMentionOccurrence {
  final GroupMentionKind kind;
  final String? userId;
  final int start;
  final int end;
  final String displayText;

  const GroupMentionOccurrence({
    required this.kind,
    required this.start,
    required this.end,
    required this.displayText,
    this.userId,
  });

  bool get isMemberWithUserId =>
      kind == GroupMentionKind.member &&
      (userId?.trim().isNotEmpty ?? false);

  MentionWrapSpan toWrapSpan() => MentionWrapSpan(
        start: start,
        end: end,
        memberUserId: isMemberWithUserId ? userId!.trim() : null,
      );
}

class MentionTapTarget {
  final GroupMentionKind kind;
  final String? userId;
  final String rawToken;

  const MentionTapTarget.member(String this.userId)
      : kind = GroupMentionKind.member,
        rawToken = userId;

  const MentionTapTarget.chatIdOrGroup(this.rawToken)
      : kind = GroupMentionKind.chatIdOrGroup,
        userId = null;

  const MentionTapTarget.atAll()
      : kind = GroupMentionKind.atAll,
        userId = null,
        rawToken = '';

  bool get isMemberWithUserId =>
      kind == GroupMentionKind.member &&
      (userId?.trim().isNotEmpty ?? false);
}

class GroupMentionInsert {
  final String userId;
  final String showName;

  const GroupMentionInsert({
    required this.userId,
    required this.showName,
  });
}

class GroupMentionOccurrenceCodec {
  GroupMentionOccurrenceCodec._();

  static const String key = 'groupMentionOccurrences';
  static const int version = 1;

  static String mergeIntoCloudCustomData(
    String? existing,
    List<GroupMentionOccurrence> occurrences,
  ) {
    final members = occurrences
        .where((item) =>
            item.kind == GroupMentionKind.member ||
            item.kind == GroupMentionKind.atAll)
        .toList(growable: false);
    if (members.isEmpty) {
      return existing ?? '';
    }
    Map<String, dynamic> data = <String, dynamic>{};
    final raw = existing?.trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          data = Map<String, dynamic>.from(decoded);
        } else if (decoded is Map) {
          data = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        data = <String, dynamic>{};
      }
    }
    data[key] = <String, dynamic>{
      'v': version,
      'items': members
          .map(
            (item) => <String, dynamic>{
              'userId': item.userId ?? '',
              'start': item.start,
              'end': item.end,
              'displayText': item.displayText,
              'kind': item.kind == GroupMentionKind.atAll ? 'atAll' : 'member',
            },
          )
          .toList(growable: false),
    };
    return jsonEncode(data);
  }

  static List<GroupMentionOccurrence>? parse({
    required String text,
    String? cloudCustomData,
  }) {
    final raw = cloudCustomData?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    final payload = data?[key];
    if (payload is! Map) {
      return null;
    }
    final items = payload['items'];
    if (items is! List || items.isEmpty) {
      return null;
    }
    final occurrences = <GroupMentionOccurrence>[];
    for (final item in items) {
      if (item is! Map) {
        return null;
      }
      final start = item['start'];
      final end = item['end'];
      final displayText = item['displayText']?.toString() ?? '';
      final userId = item['userId']?.toString() ?? '';
      final kindRaw = item['kind']?.toString() ?? 'member';
      if (start is! int || end is! int) {
        return null;
      }
      if (start < 0 || end < start || end > text.length) {
        return null;
      }
      if (text.substring(start, end) != displayText) {
        return null;
      }
      final kind = kindRaw == 'atAll' || GroupAtMention.isAtAllToken(userId)
          ? GroupMentionKind.atAll
          : GroupMentionKind.member;
      occurrences.add(
        GroupMentionOccurrence(
          kind: kind,
          start: start,
          end: end,
          displayText: displayText,
          userId: userId.trim().isEmpty ? null : userId.trim(),
        ),
      );
    }
    return occurrences;
  }
}

class GroupMentionResolver {
  GroupMentionResolver._();

  static String identityFingerprint(List<GroupMentionOccurrence> occurrences) {
    return occurrences
        .map((item) =>
            '${item.kind.index}:${item.userId ?? ''}:${item.start}:${item.end}')
        .join(',');
  }

  static List<String> collectAliases({
    required String userId,
    String? friendRemark,
    String? nameCard,
    String? nickName,
    String? storeName,
    String? localRemark,
    String? localNick,
  }) {
    final values = <String>{
      localRemark?.trim() ?? '',
      friendRemark?.trim() ?? '',
      nameCard?.trim() ?? '',
      localNick?.trim() ?? '',
      storeName?.trim() ?? '',
      nickName?.trim() ?? '',
      userId.trim(),
    };
    values.removeWhere((value) => value.isEmpty);
    return values.toList(growable: false);
  }

  static Map<String, List<String>> aliasesForUserIds({
    required Iterable<String> userIds,
    required String groupId,
    List<V2TimGroupMemberFullInfo> chatMembers = const [],
  }) {
    final byId = <String, V2TimGroupMemberFullInfo>{};
    for (final member in chatMembers) {
      final id = member.userID.trim();
      if (id.isNotEmpty) {
        byId[id] = member;
      }
    }
    final map = <String, List<String>>{};
    for (final rawId in userIds) {
      final id = rawId.trim();
      if (id.isEmpty || GroupAtMention.isAtAllToken(id)) {
        continue;
      }
      final member = byId[id] ?? GroupMemberStore.instance.memberOf(groupId, id);
      final local = UserProfileLocalBridge.readCached(id);
      map[id] = collectAliases(
        userId: id,
        friendRemark: member?.friendRemark,
        nameCard: member?.nameCard,
        nickName: member?.nickName,
        storeName: DisplayNameStore.instance.c2c(id),
        localRemark: local?.remark,
        localNick: local?.nickname,
      );
    }
    return map;
  }

  static List<GroupMentionOccurrence> fromInsertions({
    required String text,
    required List<GroupMentionInsert> insertions,
  }) {
    var cursor = 0;
    final occurrences = <GroupMentionOccurrence>[];
    for (final item in insertions) {
      final showName = item.showName.trim();
      final userId = item.userId.trim();
      if (showName.isEmpty || userId.isEmpty) {
        continue;
      }
      final needle = '@$showName';
      final index = text.indexOf(needle, cursor);
      if (index < 0) {
        continue;
      }
      final end = index + needle.length;
      occurrences.add(
        GroupMentionOccurrence(
          kind: GroupAtMention.isAtAllToken(userId) ||
                  GroupAtMention.isAtAllToken(showName)
              ? GroupMentionKind.atAll
              : GroupMentionKind.member,
          start: index,
          end: end,
          displayText: text.substring(index, end),
          userId: userId,
        ),
      );
      cursor = end;
    }
    return occurrences;
  }

  static String wrapResolved(
    String text,
    List<GroupMentionOccurrence> occurrences,
  ) {
    return LinkUtils.wrapChatIdMentionsForExtendedText(
      text,
      occurrences: occurrences.map((item) => item.toWrapSpan()).toList(),
      identityFingerprint: identityFingerprint(occurrences),
    );
  }

  static List<GroupMentionOccurrence> resolveMessage(
    V2TimMessage message, {
    required String text,
    String groupId = '',
    List<V2TimGroupMemberFullInfo> chatMembers = const [],
  }) {
    final structured = _structuredUserIds(message.groupAtUserList);
    final memberIds = <String>{
      ...structured,
      if (structured.isEmpty) ...chatMembers.map((item) => item.userID.trim()),
      if (structured.isEmpty)
        ...GroupMemberStore.instance
            .membersForGroup(groupId)
            .map((item) => item.userID.trim()),
    }..removeWhere((id) => id.isEmpty);
    final aliases = aliasesForUserIds(
      userIds: memberIds,
      groupId: groupId,
      chatMembers: chatMembers,
    );
    return resolve(
      text: text,
      groupAtUserList: message.groupAtUserList,
      cloudCustomData: message.cloudCustomData,
      aliasesByUserId: structured.isEmpty ? const {} : aliases,
      legacyAliasesByUserId: structured.isEmpty ? aliases : const {},
    );
  }

  static List<GroupMentionOccurrence> resolve({
    required String text,
    List<String>? groupAtUserList,
    String? cloudCustomData,
    Map<String, List<String>> aliasesByUserId = const {},
    Map<String, List<String>> legacyAliasesByUserId = const {},
  }) {
    if (text.isEmpty || !text.contains('@')) {
      return const [];
    }
    final occupied = <_Span>[];
    _occupyUrls(text, occupied);

    final structuredIds = _structuredUserIds(groupAtUserList);
    final metadata = GroupMentionOccurrenceCodec.parse(
      text: text,
      cloudCustomData: cloudCustomData,
    );
    if (metadata != null) {
      final occurrences = <GroupMentionOccurrence>[
        ..._chatIdOccurrences(text, occupied, allowNonTgs: false),
      ];
      for (final item in metadata) {
        if (_overlaps(occupied, item.start, item.end)) {
          continue;
        }
        occupied.add(_Span(item.start, item.end));
        occurrences.add(item);
      }
      occurrences.addAll(
        _chatIdOccurrences(text, occupied, allowNonTgs: true),
      );
      occurrences.sort((a, b) => a.start.compareTo(b.start));
      return occurrences;
    }

    final occurrences = <GroupMentionOccurrence>[
      ..._chatIdOccurrences(text, occupied, allowNonTgs: false),
    ];

    if (structuredIds.isNotEmpty) {
      occurrences.addAll(
        _bindStructuredMembers(
          text: text,
          occupied: occupied,
          candidateIds: structuredIds,
          aliasesByUserId: aliasesByUserId,
        ),
      );
      occurrences.addAll(
        _chatIdOccurrences(text, occupied, allowNonTgs: true),
      );
      occurrences.sort((a, b) => a.start.compareTo(b.start));
      return occurrences;
    }

    occurrences.addAll(
      _chatIdOccurrences(text, occupied, allowNonTgs: true),
    );
    if (legacyAliasesByUserId.isNotEmpty) {
      occurrences.addAll(
        _bindStructuredMembers(
          text: text,
          occupied: occupied,
          candidateIds: legacyAliasesByUserId.keys.toList(growable: false),
          aliasesByUserId: legacyAliasesByUserId,
        ),
      );
    }
    occurrences.addAll(_regexMemberFallbacks(text, occupied));
    occurrences.sort((a, b) => a.start.compareTo(b.start));
    return occurrences;
  }

  static List<String> _structuredUserIds(List<String>? groupAtUserList) {
    if (groupAtUserList == null || groupAtUserList.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    final seen = <String>{};
    for (final raw in groupAtUserList) {
      final id = raw.trim();
      if (id.isEmpty || GroupAtMention.isAtAllToken(id)) {
        continue;
      }
      if (id == V2TimGroupAtInfo.c_api_tag) {
        continue;
      }
      if (seen.add(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  static void _occupyUrls(String text, List<_Span> occupied) {
    for (final match in LinkUtils.urlReg.allMatches(text)) {
      occupied.add(_Span(match.start, match.end));
    }
  }

  static List<GroupMentionOccurrence> _chatIdOccurrences(
    String text,
    List<_Span> occupied, {
    required bool allowNonTgs,
  }) {
    final occurrences = <GroupMentionOccurrence>[];
    for (final match in LinkUtils.chatIdMentionReg.allMatches(text)) {
      if (_overlaps(occupied, match.start, match.end)) {
        continue;
      }
      final display = match.group(0) ?? '';
      if (!_isReservedChatIdDisplay(display, allowNonTgs: allowNonTgs)) {
        continue;
      }
      occupied.add(_Span(match.start, match.end));
      occurrences.add(
        GroupMentionOccurrence(
          kind: GroupMentionKind.chatIdOrGroup,
          start: match.start,
          end: match.end,
          displayText: display,
        ),
      );
    }
    return occurrences;
  }

  static bool _isReservedChatIdDisplay(
    String display, {
    required bool allowNonTgs,
  }) {
    if (display.toUpperCase().contains('TGS#')) {
      return true;
    }
    if (!allowNonTgs) {
      return false;
    }
    final token =
        display.startsWith('@') ? display.substring(1) : display;
    return ChatIdFormat.isUserUidToken(token);
  }

  static List<GroupMentionOccurrence> _bindStructuredMembers({
    required String text,
    required List<_Span> occupied,
    required List<String> candidateIds,
    required Map<String, List<String>> aliasesByUserId,
  }) {
    final bound = <GroupMentionOccurrence>[];
    final boundUserIds = <String>{};
    final atIndexes = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x40) {
        continue;
      }
      if (_overlaps(occupied, i, i + 1)) {
        continue;
      }
      atIndexes.add(i);
    }

    for (final start in atIndexes) {
      if (_overlaps(occupied, start, start + 1)) {
        continue;
      }
      final match = _longestUniqueAliasMatch(
        text: text,
        atIndex: start,
        candidateIds: candidateIds,
        aliasesByUserId: aliasesByUserId,
      );
      if (match == null) {
        continue;
      }
      occupied.add(_Span(match.start, match.end));
      boundUserIds.add(match.userId!);
      bound.add(match);
    }

    final unboundSpans = <_Span>[];
    for (final match in LinkUtils.groupAtMentionReg.allMatches(text)) {
      if (_overlaps(occupied, match.start, match.end)) {
        continue;
      }
      unboundSpans.add(_Span(match.start, match.end));
    }
    final remainingIds =
        candidateIds.where((id) => !boundUserIds.contains(id)).toList();
    if (unboundSpans.length == 1 && remainingIds.length == 1) {
      final span = unboundSpans.single;
      final userId = remainingIds.single;
      occupied.add(span);
      bound.add(
        GroupMentionOccurrence(
          kind: GroupMentionKind.member,
          start: span.start,
          end: span.end,
          displayText: text.substring(span.start, span.end),
          userId: userId,
        ),
      );
    }
    return bound;
  }

  static GroupMentionOccurrence? _longestUniqueAliasMatch({
    required String text,
    required int atIndex,
    required List<String> candidateIds,
    required Map<String, List<String>> aliasesByUserId,
  }) {
    var bestLength = 0;
    final winners = <String>{};
    for (final userId in candidateIds) {
      final aliases = aliasesByUserId[userId] ?? const <String>[];
      for (final alias in aliases) {
        if (alias.isEmpty) {
          continue;
        }
        final end = atIndex + 1 + alias.length;
        if (end > text.length) {
          continue;
        }
        if (text.substring(atIndex + 1, end) != alias) {
          continue;
        }
        if (alias.length > bestLength) {
          bestLength = alias.length;
          winners
            ..clear()
            ..add(userId);
        } else if (alias.length == bestLength) {
          winners.add(userId);
        }
      }
    }
    if (bestLength <= 0 || winners.length != 1) {
      return null;
    }
    final end = atIndex + 1 + bestLength;
    return GroupMentionOccurrence(
      kind: GroupMentionKind.member,
      start: atIndex,
      end: end,
      displayText: text.substring(atIndex, end),
      userId: winners.single,
    );
  }

  static List<GroupMentionOccurrence> _regexMemberFallbacks(
    String text,
    List<_Span> occupied,
  ) {
    final occurrences = <GroupMentionOccurrence>[];
    for (final match in LinkUtils.groupAtMentionReg.allMatches(text)) {
      if (_overlaps(occupied, match.start, match.end)) {
        continue;
      }
      occupied.add(_Span(match.start, match.end));
      occurrences.add(
        GroupMentionOccurrence(
          kind: GroupMentionKind.member,
          start: match.start,
          end: match.end,
          displayText: match.group(0) ?? '',
        ),
      );
    }
    return occurrences;
  }

  static bool _overlaps(List<_Span> occupied, int start, int end) {
    for (final span in occupied) {
      if (start < span.end && end > span.start) {
        return true;
      }
    }
    return false;
  }
}

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}
