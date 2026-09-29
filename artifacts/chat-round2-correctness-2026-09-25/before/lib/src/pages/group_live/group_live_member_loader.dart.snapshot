import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class GroupLiveMemberPage {
  const GroupLiveMemberPage(this.members, this.nextCursor);
  final List<RedPacketMember> members;
  final String nextCursor;
}

typedef GroupLiveMemberPageLoader = Future<GroupLiveMemberPage> Function(
    String cursor);

/// Fresh SDK pages only: a local fallback cannot establish membership coverage.
GroupLiveMemberPageLoader groupLiveMemberPageLoader(String groupId) {
  String? resolvedGroupId;
  final identity = SessionIdentityService.instance.capture();
  return (cursor) async {
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      throw StateError('Account changed');
    }
    final candidates = resolvedGroupId == null
        ? ChatIdFormat.imGroupIdCandidates(groupId)
        : <String>[resolvedGroupId!];
    for (final candidate in candidates) {
      final response = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getGroupMemberList(
            groupID: candidate,
            filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
            count: 100,
            nextSeq: cursor,
          )
          .timeout(const Duration(seconds: 15));
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        throw StateError('Account changed');
      }
      if (response.code != 0 || response.data == null) continue;
      resolvedGroupId = candidate;
      return GroupLiveMemberPage(
        (response.data!.memberInfoList ?? [])
            .map(RedPacketMember.fromGroupMember)
            .toList(growable: false),
        response.data!.nextSeq ?? '0',
      );
    }
    throw StateError('Unable to load group members');
  };
}

/// Owns one picker visit. Retry resumes the failed cursor; reopening starts fresh.
class GroupLiveMemberLoader extends ChangeNotifier {
  GroupLiveMemberLoader(this.loadPage);
  final GroupLiveMemberPageLoader loadPage;
  final Map<String, RedPacketMember> _members = {};
  final Set<String> _completedCursors = {};
  String _cursor = '0';
  bool loading = false;
  bool complete = false;
  bool failed = false;
  bool _disposed = false;

  List<RedPacketMember> get members => _members.values.toList(growable: false);

  Future<void> load() async {
    if (_disposed || loading || complete) return;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      while (!_disposed && !complete) {
        final page = await loadPage(_cursor);
        if (_disposed) return;
        final next = page.nextCursor.trim();
        final terminal = next.isEmpty || next == '0';
        if (!terminal &&
            (next == _cursor || _completedCursors.contains(next))) {
          throw StateError('Group member cursor did not advance');
        }
        for (final member in page.members) {
          final id = member.userId.trim();
          if (id.isNotEmpty) _members[id] = member;
        }
        _completedCursors.add(_cursor);
        complete = terminal;
        _cursor = next;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) failed = true;
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
