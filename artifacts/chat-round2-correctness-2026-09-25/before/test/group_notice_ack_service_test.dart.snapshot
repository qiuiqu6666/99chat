import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_ack_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  group('GroupNoticeAckService.buildSignature', () {
    test('uses group id, notice updated time, and notice body', () {
      expect(
        GroupNoticeAckService.buildSignature(
          groupId: '@TGS#ABC',
          notice: '欢迎新成员',
          noticeUpdatedAtMs: 1718456400000,
        ),
        '@TGS#ABC|1718456400000|欢迎新成员',
      );
    });
  });

  group('GroupNoticeAckService.isAcknowledged', () {
    const groupId = '@TGS#ABC';
    const notice = '欢迎新成员';
    final current = GroupNoticeAckService.buildSignature(
      groupId: groupId,
      notice: notice,
      noticeUpdatedAtMs: 1718456400000,
    );

    test('matches current signature', () {
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: current,
          currentSignature: current,
          groupId: groupId,
          notice: notice,
        ),
        isTrue,
      );
    });

    test('matches legacy normal signature', () {
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: '$groupId|10001|1718456400|$notice',
          currentSignature: current,
          groupId: groupId,
          notice: notice,
        ),
        isTrue,
      );
    });

    test('matches legacy push signature', () {
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: '$groupId|push|1718456400123|$notice',
          currentSignature: current,
          groupId: groupId,
          notice: notice,
        ),
        isTrue,
      );
    });

    test('does not match different notice body', () {
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: '$groupId|push|1718456400123|旧公告',
          currentSignature: current,
          groupId: groupId,
          notice: notice,
        ),
        isFalse,
      );
    });
  });

  group('GroupNoticeAckService.saveAckSignature after self edit', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SessionIdentityService.instance.invalidate();
    });

    test('saved self-edit signature is acknowledged for same notice body',
        () async {
      const groupId = '@TGS#ABC';
      const notice = '新公告正文';
      final saved = GroupNoticeAckService.buildSignature(
        groupId: groupId,
        notice: notice,
        noticeUpdatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await GroupNoticeAckService.instance.saveAckSignature(groupId, saved);
      final acked =
          await GroupNoticeAckService.instance.getAckSignature(groupId);
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: acked,
          currentSignature: GroupNoticeAckService.buildSignature(
            groupId: groupId,
            notice: notice,
            noticeUpdatedAtMs: 999,
          ),
          groupId: groupId,
          notice: notice,
        ),
        isTrue,
      );
      expect(
        GroupNoticeAckService.isAcknowledged(
          ackedSignature: acked,
          currentSignature: '$groupId|push|1718456400123|$notice',
          groupId: groupId,
          notice: notice,
        ),
        isTrue,
      );
    });
  });
}
