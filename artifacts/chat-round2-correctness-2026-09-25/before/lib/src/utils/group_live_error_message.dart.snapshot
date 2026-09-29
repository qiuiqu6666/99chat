import 'package:intl/intl.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';

class GroupLiveErrorMessage {
  GroupLiveErrorMessage._();

  static String from(Object error) {
    if (error is GroupLiveApiException) {
      return _fromCode(error.code, fallback: error.message);
    }
    return AppI18n.current.t(
      zhHans: '群直播请求失败，请稍后重试',
      zhHant: '群直播請求失敗，請稍後重試',
      en: 'Group live request failed. Try again later.',
      ja: 'グループ配信のリクエストに失敗しました。',
      ko: '그룹 라이브 요청에 실패했습니다.',
    );
  }

  /// When [sessionDetail] shows the slot is over, skip `push-info` and use this.
  static String? blockedPushInfoMessage(GroupLiveSession session) {
    switch (session.status) {
      case GroupLiveStatus.ended:
        return endedSessionMessage(session);
      case GroupLiveStatus.banned:
        return AppI18n.current.t(
          zhHans: '直播已被平台禁播，请重新预约',
          zhHant: '直播已被平台禁播，請重新預約',
          en: 'This live was banned. Please schedule again.',
          ja: '配信は停止されました。再度予約してください。',
          ko: '라이브가 중단되었습니다. 다시 예약해 주세요.',
        );
      case GroupLiveStatus.scheduled:
      case GroupLiveStatus.authorized:
      case GroupLiveStatus.live:
      case GroupLiveStatus.unknown:
        return null;
    }
  }

  static String endedSessionMessage(GroupLiveSession session) {
    switch (session.endReason) {
      case GroupLiveEndReason.scheduleExpired:
        return AppI18n.current.t(
          zhHans: '超时未推流，预约已过期，请重新预约',
          zhHant: '超時未推流，預約已過期，請重新預約',
          en: 'Expired — no stream started in time. Please schedule again.',
          ja: '期限内に配信がなく失効しました。再度予約してください。',
          ko: '推流 없이 만료되었습니다. 다시 예약해 주세요.',
        );
      case GroupLiveEndReason.revoked:
        return AppI18n.current.t(
          zhHans: '预约已撤销，请重新预约',
          zhHant: '預約已撤銷，請重新預約',
          en: 'Schedule was revoked. Please schedule again.',
          ja: '予約が取り消されました。再度予約してください。',
          ko: '예약이 취소되었습니다. 다시 예약해 주세요.',
        );
      case GroupLiveEndReason.adminBan:
        return AppI18n.current.t(
          zhHans: '直播已被平台禁播，请重新预约',
          zhHant: '直播已被平台禁播，請重新預約',
          en: 'This live was banned. Please schedule again.',
          ja: '配信は停止されました。再度予約してください。',
          ko: '라이브가 중단되었습니다. 다시 예약해 주세요.',
        );
      case GroupLiveEndReason.disconnect:
        return AppI18n.current.t(
          zhHans: '推流已中断且场次已结束，请重新预约',
          zhHant: '推流已中斷且場次已結束，請重新預約',
          en: 'Streaming stopped and the session ended. Please schedule again.',
          ja: '配信が中断されセッションが終了しました。再度予約してください。',
          ko: '推流가 중단되어 라이브가 종료되었습니다. 다시 예약해 주세요.',
        );
      case GroupLiveEndReason.normal:
      case GroupLiveEndReason.ownerStop:
      case GroupLiveEndReason.adminStop:
      case GroupLiveEndReason.unknown:
      case null:
        return AppI18n.current.t(
          zhHans: '直播已结束，如需再次开播请重新预约',
          zhHant: '直播已結束，如需再次開播請重新預約',
          en: 'This live has ended. Schedule again to go live.',
          ja: '配信は終了しました。再度配信するには予約し直してください。',
          ko: '라이브가 종료되었습니다. 다시 방송하려면 새로 예약해 주세요.',
        );
    }
  }

  /// Optional subtitle with schedule / expiry timestamps from session detail.
  static String? sessionTimingSubtitle(GroupLiveSession session) {
    final lines = <String>[];
    final scheduled = session.scheduledStartAt?.toLocal();
    if (scheduled != null) {
      final text = DateFormat('yyyy-MM-dd HH:mm').format(scheduled);
      lines.add(
        AppI18n.current.t(
          zhHans: '预计开播：$text',
          zhHant: '預計開播：$text',
          en: 'Scheduled start: $text',
          ja: '開始予定：$text',
          ko: '예상 시작: $text',
        ),
      );
    }
    final expire = session.expireAt?.toLocal();
    if (expire != null) {
      final text = DateFormat('yyyy-MM-dd HH:mm').format(expire);
      lines.add(
        AppI18n.current.t(
          zhHans: '有效期至：$text',
          zhHant: '有效期至：$text',
          en: 'Valid until: $text',
          ja: '有効期限：$text',
          ko: '유효 기간: $text',
        ),
      );
    }
    if (lines.isEmpty) {
      return null;
    }
    return lines.join('\n');
  }

  static bool canRescheduleAfterEnd(GroupLiveSession session) {
    return session.status == GroupLiveStatus.ended ||
        session.status == GroupLiveStatus.banned ||
        session.endReason == GroupLiveEndReason.scheduleExpired ||
        session.endReason == GroupLiveEndReason.revoked;
  }

  /// authorize / schedule / revoke / stop 等管理操作权限不足。
  static String notGroupAdminForManagement() {
    return AppI18n.current.t(
      zhHans: '仅群主或管理员可以操作群直播',
      zhHant: '僅群主或管理員可以操作群直播',
      en: 'Only the group owner or admins can manage group live.',
      ja: 'グループオーナーまたは管理者のみ操作できます。',
      ko: '그룹장 또는 관리자만 그룹 라이브를 관리할 수 있습니다.',
    );
  }

  /// push-info 页面本地权限拦截（指定主播 / 群主 / 管理员）。
  static String pushInfoAccessDenied() {
    return AppI18n.current.t(
      zhHans: '仅指定主播、群主或管理员可以获取推流地址',
      zhHant: '僅指定主播、群主或管理員可以取得推流地址',
      en: 'Only the designated anchor, owner, or admins can fetch push info.',
      ja: '指定アンカー・オーナー・管理者のみ配信URLを取得できます。',
      ko: '지정 앵커, 그룹장 또는 관리자만推流 주소를 받을 수 있습니다.',
    );
  }

  static String _fromCode(String code, {required String fallback}) {
    switch (code.trim().toUpperCase()) {
      case 'UNAUTHORIZED':
        return AppI18n.current.t(
          zhHans: '请先登录',
          zhHant: '請先登入',
          en: 'Please sign in first.',
          ja: '先にログインしてください。',
          ko: '먼저 로그인해 주세요.',
        );
      case 'NOT_GROUP_ADMIN':
        return AppI18n.current.t(
          zhHans: '无权限',
          zhHant: '無權限',
          en: 'No permission',
          ja: '権限がありません',
          ko: '권한이 없습니다',
        );
      case 'NOT_GROUP_OWNER':
        return notGroupAdminForManagement();
      case 'NOT_DESIGNATED_ANCHOR':
        return AppI18n.current.t(
          zhHans: '仅指定主播可以获取推流地址',
          zhHant: '僅指定主播可以取得推流地址',
          en: 'Only the designated anchor can fetch push info.',
          ja: '指定アンカーのみ配信URLを取得できます。',
          ko: '지정된 앵커만推流 주소를 받을 수 있습니다.',
        );
      case 'GROUP_LIVE_SLOT_TAKEN':
        return AppI18n.current.t(
          zhHans: '本群已有预约/直播',
          zhHant: '本群已有預約/直播',
          en: 'This group already has a scheduled or live session.',
          ja: 'このグループには既に予約または配信があります。',
          ko: '이 그룹에 이미 예약/라이브가 있습니다.',
        );
      case 'ANCHOR_IN_CALL':
        return AppI18n.current.t(
          zhHans: '该成员正在通话',
          zhHant: '該成員正在通話',
          en: 'This member is in a call.',
          ja: 'このメンバーは通話中です。',
          ko: '해당 멤버가 통화 중입니다.',
        );
      case 'LIVE_NOT_AUTHORIZED_YET':
        return AppI18n.current.t(
          zhHans: '尚未到开播时间，请稍后再获取推流地址',
          zhHant: '尚未到開播時間，請稍後再取得推流地址',
          en: 'It is not time to go live yet. Try again later.',
          ja: 'まだ配信開始時刻ではありません。',
          ko: '아직 방송 시작 시간이 아닙니다.',
        );
      case 'LIVE_NOT_LIVE':
        return AppI18n.current.t(
          zhHans: '直播尚未开始',
          zhHant: '直播尚未開始',
          en: 'The live session has not started yet.',
          ja: '配信はまだ開始されていません。',
          ko: '라이브가 아직 시작되지 않았습니다.',
        );
      case 'LIVE_SESSION_EXPIRED':
        return AppI18n.current.t(
          zhHans: '预约已过期，请重新预约',
          zhHant: '預約已過期，請重新預約',
          en: 'The scheduled session expired. Please schedule again.',
          ja: '予約の有効期限が切れました。',
          ko: '예약이 만료되었습니다.',
        );
      case 'ROOM_NAME_REQUIRED':
        return AppI18n.current.t(
          zhHans: '请填房间名',
          zhHant: '請填房間名',
          en: 'Room name is required.',
          ja: 'ルーム名を入力してください。',
          ko: '방 이름을 입력해 주세요.',
        );
      case 'ROOM_NAME_TOO_LONG':
        return AppI18n.current.t(
          zhHans: '房间名过长',
          zhHant: '房間名過長',
          en: 'Room name is too long.',
          ja: 'ルーム名が長すぎます。',
          ko: '방 이름이 너무 깁니다.',
        );
      case 'DESCRIPTION_TOO_LONG':
        return AppI18n.current.t(
          zhHans: '描述最多 30 字',
          zhHant: '描述最多 30 字',
          en: 'Description can be at most 30 characters.',
          ja: '説明は30文字以内です。',
          ko: '설명은 최대 30자입니다.',
        );
      case 'SCHEDULE_TOO_SOON':
      case 'SCHEDULE_IN_PAST':
      case 'SCHEDULE_TOO_FAR':
        return AppI18n.current.t(
          zhHans: '时间不合法',
          zhHant: '時間不合法',
          en: 'Invalid schedule time.',
          ja: '開始時刻が正しくありません。',
          ko: '시간이 올바르지 않습니다.',
        );
      case 'CANNOT_TIP_SELF':
        return AppI18n.current.t(
          zhHans: '不能给自己打赏',
          zhHant: '不能給自己打賞',
          en: 'You cannot tip yourself.',
          ja: '自分自身に投げ銭できません。',
          ko: '본인에게 후원할 수 없습니다.',
        );
      case 'INSUFFICIENT_BALANCE':
        return AppI18n.current.t(
          zhHans: '余额不足',
          zhHant: '餘額不足',
          en: 'Insufficient balance.',
          ja: '残高不足です。',
          ko: '잔액이 부족합니다.',
        );
      case 'PAY_PIN_INVALID':
        return AppI18n.current.t(
          zhHans: '支付密码错误',
          zhHant: '支付密碼錯誤',
          en: 'Incorrect payment PIN.',
          ja: '支払いPINが正しくありません。',
          ko: '결제 비밀번호가 올바르지 않습니다.',
        );
      case 'PAY_PIN_NOT_SET':
        return AppI18n.current.t(
          zhHans: '请先设置支付密码',
          zhHant: '請先設定支付密碼',
          en: 'Please set a payment PIN first.',
          ja: '先に支払いPINを設定してください。',
          ko: '먼저 결제 비밀번호를 설정해 주세요.',
        );
      case 'CSS_NOT_CONFIGURED':
      case 'GROUP_LIVE_DISABLED':
        return AppI18n.current.t(
          zhHans: '群直播功能暂未开放',
          zhHant: '群直播功能暫未開放',
          en: 'Group live is not available yet.',
          ja: 'グループ配信は現在利用できません。',
          ko: '그룹 라이브 기능을 아직 사용할 수 없습니다.',
        );
      default:
        if (fallback.trim().isNotEmpty) {
          return fallback.trim();
        }
        return AppI18n.current.t(
          zhHans: '群直播请求失败，请稍后重试',
          zhHant: '群直播請求失敗，請稍後重試',
          en: 'Group live request failed. Try again later.',
          ja: 'グループ配信のリクエストに失敗しました。',
          ko: '그룹 라이브 요청에 실패했습니다.',
        );
    }
  }
}
