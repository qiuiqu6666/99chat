import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_authorize_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_online_live_scaffold.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_routing.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_info_resolver.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_live_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';

const BoxDecoration _pushInfoBackgroundDecoration = BoxDecoration(
  image: DecorationImage(
    image: AssetImage('assets/livebg.webp'),
    fit: BoxFit.cover,
  ),
);

class GroupLivePushInfoPage extends StatefulWidget {
  const GroupLivePushInfoPage({
    super.key,
    required this.liveSessionId,
    this.initialSession,
    this.groupId,
  });

  final String liveSessionId;
  final GroupLiveSession? initialSession;
  final String? groupId;

  static Future<void> open(
    BuildContext context, {
    required String liveSessionId,
    GroupLiveSession? initialSession,
    String? groupId,
  }) {
    return Navigator.of(context).push<void>(
      AppMaterialPageRoute(
        builder: (_) => GroupLivePushInfoPage(
          liveSessionId: liveSessionId,
          initialSession: initialSession,
          groupId: groupId,
        ),
      ),
    );
  }

  @override
  State<GroupLivePushInfoPage> createState() => _GroupLivePushInfoPageState();
}

class _GroupLivePushInfoPageState extends State<GroupLivePushInfoPage> {
  GroupLivePushInfo? _info;
  GroupLiveSession? _session;
  bool _loading = true;
  bool _submitting = false;
  bool _refreshing = false;
  bool _pendingSchedule = false;
  bool _canManageLive = false;
  bool _errorReschedulable = false;
  String? _error;
  String? _errorSubtitle;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    unawaited(_load());
  }

  Future<void> _load({bool refreshing = false}) async {
    setState(() {
      if (refreshing) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
      _errorSubtitle = null;
      _errorReschedulable = false;
      if (!refreshing) {
        _pendingSchedule = false;
      }
    });
    try {
      final session = await GroupLiveApi.instance.sessionDetail(
        liveSessionId: widget.liveSessionId,
      );
      final groupId = _groupId.isNotEmpty ? _groupId : session.groupId.trim();
      final userId = GroupLiveRouting.currentUserId();
      final role = groupId.isEmpty
          ? GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER
          : (await GroupInfoResolver.instance.myRole(groupId)) ??
              GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;

      if (!mounted) return;

      final canView = GroupLiveRouting.canViewPushInfoScreen(
        session: session,
        currentUserId: userId,
        role: role,
      );
      final canManage = GroupRolePolicy.isManagerRole(role);

      if (!canView) {
        setState(() {
          _session = session;
          _canManageLive = canManage;
          _loading = false;
          _refreshing = false;
          _error = GroupLiveErrorMessage.pushInfoAccessDenied();
        });
        return;
      }

      final blocked = GroupLiveErrorMessage.blockedPushInfoMessage(session);
      if (blocked != null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[GroupLive] push-info skipped: status=${session.status.wire} '
            'endReason=${session.endReason?.name ?? 'null'} '
            'expireAt=${session.expireAt?.toIso8601String() ?? 'null'}',
          );
        }
        if (!mounted) return;
        setState(() {
          _session = session;
          _canManageLive = canManage;
          _loading = false;
          _refreshing = false;
          _error = blocked;
          _errorSubtitle = GroupLiveErrorMessage.sessionTimingSubtitle(session);
          _errorReschedulable =
              canManage && GroupLiveErrorMessage.canRescheduleAfterEnd(session);
        });
        return;
      }

      try {
        final info = await GroupLiveApi.instance.pushInfo(
          liveSessionId: widget.liveSessionId,
        );
        if (!mounted) return;
        setState(() {
          _info = info;
          _session = session;
          _canManageLive = canManage;
          _pendingSchedule = false;
          _loading = false;
          _refreshing = false;
        });
        return;
      } on GroupLiveApiException catch (e) {
        final code = e.code.trim().toUpperCase();
        if (code == 'LIVE_NOT_AUTHORIZED_YET' ||
            session.status == GroupLiveStatus.scheduled) {
          if (!mounted) return;
          setState(() {
            _session = session;
            _canManageLive = canManage;
            _pendingSchedule = true;
            _loading = false;
            _refreshing = false;
          });
          return;
        }
        if (code == 'LIVE_SESSION_EXPIRED') {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[GroupLive] push-info LIVE_SESSION_EXPIRED '
              'status=${session.status.wire} '
              'expireAt=${session.expireAt?.toIso8601String() ?? 'null'}',
            );
          }
          if (!mounted) return;
          setState(() {
            _session = session;
            _canManageLive = canManage;
            _loading = false;
            _refreshing = false;
            _error = GroupLiveErrorMessage.from(
              GroupLiveApiException('LIVE_SESSION_EXPIRED', ''),
            );
            _errorSubtitle =
                GroupLiveErrorMessage.sessionTimingSubtitle(session);
            _errorReschedulable = canManage;
          });
          return;
        }
        rethrow;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = GroupLiveErrorMessage.from(e);
      });
    }
  }

  Future<void> _openReschedule() async {
    final groupId = _groupId;
    if (groupId.isEmpty || !mounted) return;
    await GroupLiveAuthorizePage.openScheduleReplacing(
      context,
      groupId: groupId,
    );
  }

  /// 结束直播 = 删除本次直播配置；若已在推流则先结束推流（stop），否则撤销预约（revoke）。
  Future<void> _endLive() async {
    final session = _session;
    final groupId = _groupId;
    if (session == null || !_canManageLive || groupId.isEmpty) return;

    final i18n = AppI18n.of(context);
    final isLive = session.isLive;
    final confirmed = await AppDialog.confirm(
      title: i18n.t(
        zhHans: '结束直播',
        zhHant: '結束直播',
        en: 'End live',
        ja: '配信終了',
        ko: '라이브 종료',
      ),
      message: isLive
          ? i18n.t(
              zhHans: '确定结束本次直播吗？将同时结束推流，推流地址随即失效。',
              zhHant: '確定結束本次直播嗎？將同時結束推流，推流地址隨即失效。',
              en: 'End this live? Streaming will stop and credentials will become invalid.',
              ja: 'この配信を終了しますか？配信も停止し、URLは無効になります。',
              ko: '이 라이브를 종료할까요? 推流도 함께 종료되며 주소가 무효화됩니다.',
            )
          : i18n.t(
              zhHans: '确定结束本次直播吗？结束后推流地址将失效，需重新配置。',
              zhHant: '確定結束本次直播嗎？結束後推流地址將失效，需重新配置。',
              en: 'End this live? Streaming credentials will become invalid.',
              ja: 'この配信を終了しますか？終了後は配信URLが無効になります。',
              ko: '이 라이브를 종료할까요? 종료 후 推流 정보가 무효화됩니다.',
            ),
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
      confirmText: i18n.t(
        zhHans: '结束',
        zhHant: '結束',
        en: 'End',
        ja: '終了',
        ko: '종료',
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      if (isLive) {
        await GroupLiveApi.instance.stop(groupId: groupId);
      } else {
        await GroupLiveApi.instance.revoke(groupId: groupId);
      }
      if (!mounted) return;
      ToastUtils.toast(i18n.t(
        zhHans: isLive ? '已结束直播并停止推流' : '已结束直播',
        zhHant: isLive ? '已結束直播並停止推流' : '已結束直播',
        en: isLive ? 'Live ended and streaming stopped' : 'Live ended',
        ja: isLive ? '配信を終了し、推流も停止しました' : '配信を終了しました',
        ko: isLive ? '라이브와 推流를 종료했습니다' : '라이브를 종료했습니다',
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.toast(GroupLiveErrorMessage.from(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _canEndLive {
    final session = _session;
    if (session == null || !_canManageLive) return false;
    return session.status == GroupLiveStatus.scheduled ||
        session.status == GroupLiveStatus.authorized ||
        session.isLive;
  }

  Widget? _buildBottomButton(AppI18n i18n) {
    if (!_canEndLive) return null;
    return GroupLivePrimaryButton(
      label: i18n.t(
        zhHans: '结束直播',
        zhHant: '結束直播',
        en: 'End live',
        ja: '配信終了',
        ko: '라이브 종료',
      ),
      loading: _submitting,
      onPressed: () => unawaited(_endLive()),
    );
  }

  Widget _obsGuideLink(AppI18n i18n) {
    const blue = GroupLiveOnlineLiveScaffold.primaryBlue;
    return Material(
      color: const Color(0xFFEAF3FF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => showGroupLiveObsGuideSheet(
          context,
          hint: _info?.obsHint,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i18n.t(
                  zhHans: '芯象配置',
                  zhHant: '芯象配置',
                  en: 'Xinxian setup',
                  ja: '芯象の設定',
                  ko: '芯象 설정',
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: blue,
                ),
              ),
              const Icon(Icons.chevron_right, size: 16, color: blue),
            ],
          ),
        ),
      ),
    );
  }

  String get _groupId =>
      widget.groupId?.trim() ??
      _session?.groupId.trim() ??
      widget.initialSession?.groupId.trim() ??
      '';

  String get _pushUrl {
    final server = _info?.rtmpServer.trim() ?? '';
    final streamKey = _info?.streamKey.trim() ?? '';
    if (server.isEmpty) return streamKey;
    if (streamKey.isEmpty) return server;
    return '${server.replaceFirst(RegExp(r'/+$'), '')}/'
        '${streamKey.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Widget _buildPendingScheduleBody(AppI18n i18n) {
    final cs = GroupLivePageColors.of(context);
    final pendingHint = i18n.t(
      zhHans: '正在获取推流地址',
      zhHant: '正在取得推流地址',
      en: 'Loading streaming URL',
      ja: '配信URLを取得しています',
      ko: '推流 주소를 불러오는 중',
    );
    final timingHint = GroupLiveErrorMessage.sessionTimingSubtitle(
      _session ??
          GroupLiveSession(
            liveSessionId: widget.liveSessionId,
            groupId: _groupId,
            roomName: '',
            anchorUserId: '',
            status: GroupLiveStatus.scheduled,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GroupLiveOnlineLiveHeader(),
        const SizedBox(height: 24),
        GroupLiveFormSection(
          title: i18n.t(
            zhHans: '直播设置',
            zhHant: '直播設置',
            en: 'Live settings',
            ja: '配信設定',
            ko: '라이브 설정',
          ),
          trailing: _obsGuideLink(i18n),
          children: [
            GroupLiveCopyField(
              label: i18n.t(
                zhHans: '推流地址',
                zhHant: '推流地址',
                en: 'Streaming URL',
                ja: '配信URL',
                ko: '推流 주소',
              ),
              value: pendingHint,
              onCopy: () {},
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          timingHint ??
              i18n.t(
                zhHans: '推流地址可在开播前获取，到点后点击刷新重新加载',
                zhHant: '推流地址可在開播前取得，到點後點擊重新整理再次載入',
                en: 'Streaming URL is available before start. Refresh after the scheduled time.',
                ja: '配信URLは開始前に取得できます。開始時刻後に更新してください。',
                ko: '방송 전에도 推流 주소를 받을 수 있습니다. 시작 시간 후 새로고침하세요.',
              ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.subText),
        ),
      ],
    );
  }

  Widget? _buildPendingBottomButton(AppI18n i18n) {
    if (!_pendingSchedule) return null;
    final refreshButton = GroupLivePrimaryButton(
      label: i18n.t(
        zhHans: '刷新状态',
        zhHant: '刷新狀態',
        en: 'Refresh',
        ja: '更新',
        ko: '새로고침',
      ),
      loading: _refreshing,
      onPressed: _refreshing ? null : () => unawaited(_load(refreshing: true)),
    );
    if (!_canEndLive) {
      return refreshButton;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupLivePrimaryButton(
          label: i18n.t(
            zhHans: '结束直播',
            zhHant: '結束直播',
            en: 'End live',
            ja: '配信終了',
            ko: '라이브 종료',
          ),
          loading: _submitting,
          onPressed: () => unawaited(_endLive()),
        ),
        const SizedBox(height: 10),
        refreshButton,
      ],
    );
  }

  Widget _buildErrorBody(AppI18n i18n) {
    final cs = GroupLivePageColors.of(context);
    final session = _session;
    if (_errorReschedulable && session != null) {
      final expired = session.endReason == GroupLiveEndReason.scheduleExpired ||
          (_error?.contains('过期') ?? false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupLiveOnlineLiveHeader(),
          const SizedBox(height: 120),
          _ExpiredScheduleCard(
            title: expired
                ? i18n.t(
                    zhHans: '预约已过期，请重新预约',
                    zhHant: '預約已過期，請重新預約',
                    en: 'Reservation expired. Please schedule again.',
                    ja: '予約の有効期限が切れました。',
                    ko: '예약이 만료되었습니다. 다시 예약해 주세요.',
                  )
                : (_error ?? ''),
            scheduledStartAt: session.scheduledStartAt,
            expireAt: session.expireAt,
            roomName: session.roomName,
            description: session.description,
          ),
        ],
      );
    }
    return Column(
      children: [
        const GroupLiveOnlineLiveHeader(),
        const SizedBox(height: 24),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: cs.text,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_errorSubtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorSubtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.subText),
          ),
        ],
      ],
    );
  }

  Widget? _buildErrorBottomButton(AppI18n i18n) {
    if (_errorReschedulable && _groupId.isNotEmpty) {
      return GroupLivePrimaryButton(
        label: i18n.t(
          zhHans: '重新预约',
          zhHant: '重新預約',
          en: 'Schedule again',
          ja: '再度予約',
          ko: '다시 예약',
        ),
        onPressed: () => unawaited(_openReschedule()),
      );
    }
    return GroupLivePrimaryButton(
      label: i18n.t(
        zhHans: '重试',
        zhHant: '重試',
        en: 'Retry',
        ja: '再試行',
        ko: '재시도',
      ),
      onPressed: () => unawaited(_load()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);

    if (_loading) {
      return const GroupLiveOnlineLiveScaffold(
        backgroundColor: Colors.transparent,
        backgroundDecoration: _pushInfoBackgroundDecoration,
        body: Center(
          child: Padding(
            padding: EdgeInsets.only(top: 120),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_pendingSchedule) {
      return GroupLiveOnlineLiveScaffold(
        backgroundColor: Colors.transparent,
        backgroundDecoration: _pushInfoBackgroundDecoration,
        body: _buildPendingScheduleBody(i18n),
        bottomButton: _buildPendingBottomButton(i18n),
      );
    }

    if (_error != null) {
      return GroupLiveOnlineLiveScaffold(
        backgroundColor: Colors.transparent,
        backgroundDecoration: _pushInfoBackgroundDecoration,
        body: _buildErrorBody(i18n),
        bottomButton: _buildErrorBottomButton(i18n),
      );
    }

    return GroupLiveOnlineLiveScaffold(
      backgroundColor: Colors.transparent,
      backgroundDecoration: _pushInfoBackgroundDecoration,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupLiveOnlineLiveHeader(),
          const SizedBox(height: 80),
          _PushInfoSettingsCard(
            pushUrl: _pushUrl,
            guide: _obsGuideLink(i18n),
            onCopy: () => groupLiveCopyToClipboard(
              context,
              label: '推流地址',
              value: _pushUrl,
            ),
          ),
        ],
      ),
      bottomButton: _buildBottomButton(i18n),
    );
  }
}

class _PushInfoSettingsCard extends StatelessWidget {
  const _PushInfoSettingsCard({
    required this.pushUrl,
    required this.guide,
    required this.onCopy,
  });

  final String pushUrl;
  final Widget guide;
  final VoidCallback onCopy;

  static const _blue = GroupLiveOnlineLiveScaffold.primaryBlue;
  static const _title = Color(0xFF1A1D24);
  static const _sub = Color(0xFF8A8F99);
  static const _field = Color(0xFFF4F6F8);

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final url = pushUrl.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14002D6B),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _circleIcon(Icons.settings_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n.t(
                    zhHans: '直播设置',
                    zhHant: '直播設置',
                    en: 'Live settings',
                    ja: '配信設定',
                    ko: '라이브 설정',
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _title,
                  ),
                ),
              ),
              guide,
            ],
          ),
          const SizedBox(height: 16),
          _labeledIconRow(
            Icons.link_rounded,
            i18n.t(
              zhHans: '推流地址',
              zhHant: '推流地址',
              en: 'Streaming URL',
              ja: '配信URL',
              ko: '推流 주소',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.fromLTRB(16, 0, 58, 0),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FB),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      url.isEmpty ? '—' : url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _title,
                      ),
                    ),
                  ),
                ),
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: const Color(0x1A002D6B),
                  child: InkWell(
                    onTap: url.isEmpty ? null : onCopy,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color:
                                url.isEmpty ? const Color(0xFFC0C4CC) : _blue,
                          ),
                          Text(
                            i18n.t(
                              zhHans: '复制',
                              zhHant: '複製',
                              en: 'Copy',
                              ja: 'コピー',
                              ko: '복사',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color:
                                  url.isEmpty ? const Color(0xFFC0C4CC) : _blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labeledIconRow(
                      Icons.widgets_outlined,
                      i18n.t(
                        zhHans: '二维码',
                        zhHant: '二維碼',
                        en: 'QR code',
                        ja: 'QRコード',
                        ko: 'QR 코드',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (url.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FF),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.maxWidth;
                            return QrImageView(
                              data: url,
                              version: QrVersions.auto,
                              size: size,
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.zero,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F8FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.center_focus_strong_outlined,
                            size: 22,
                            color: _blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.t(
                                zhHans: '使用芯象扫描二维码\n快速填写推流地址',
                                zhHant: '使用芯象掃描二維碼\n快速填寫推流地址',
                                en: 'Scan the QR in Xinxian\nto fill the streaming URL',
                                ja: '芯象でQRを読み取り\n配信URLを入力',
                                ko: '芯象에서 QR을 스캔해\n推流 주소를 입력',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: _title,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F8FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _iconText(
                            Icons.lightbulb_outline_rounded,
                            i18n.t(
                              zhHans: '温馨提示',
                              zhHant: '溫馨提示',
                              en: 'Tips',
                              ja: 'ヒント',
                              ko: '안내',
                            ),
                            bold: true,
                          ),
                          const SizedBox(height: 10),
                          _tipLine(
                            '1',
                            i18n.t(
                              zhHans: '请在其他直播应用中填写以上推流地址开始直播',
                              zhHant: '請在其他直播應用中填寫以上推流地址開始直播',
                              en: 'Paste this URL in another live app to start.',
                              ja: '他の配信アプリにこのURLを入力して開始。',
                              ko: '다른 방송 앱에 이 주소를 입력해 시작하세요.',
                            ),
                          ),
                          _tipLine(
                            '2',
                            i18n.t(
                              zhHans: '支持OBS、抖音直播伴侣等主流直播软件',
                              zhHant: '支持OBS、抖音直播伴侶等主流直播軟件',
                              en: 'Works with OBS, Douyin Live and similar apps.',
                              ja: 'OBSやライブ配信アプリなどに対応。',
                              ko: 'OBS, 더우인 라이브 등 주요 앱을 지원합니다.',
                            ),
                          ),
                          _tipLine(
                            '3',
                            i18n.t(
                              zhHans: '直播过程请保持网络稳定',
                              zhHant: '直播過程請保持網絡穩定',
                              en: 'Keep a stable network while live.',
                              ja: '配信中は安定した回線を維持してください。',
                              ko: '방송 중에는 네트워크를 안정적으로 유지하세요.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _circleIcon(IconData icon) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF3FF),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: _blue),
    );
  }

  static Widget _labeledIconRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _blue),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _title,
          ),
        ),
      ],
    );
  }

  static Widget _iconText(IconData icon, String text, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _blue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: bold ? _title : _sub,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _tipLine(String index, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _blue,
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: _sub,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiredScheduleCard extends StatelessWidget {
  const _ExpiredScheduleCard({
    required this.title,
    required this.roomName,
    required this.description,
    this.scheduledStartAt,
    this.expireAt,
  });

  final String title;
  final String roomName;
  final String description;
  final DateTime? scheduledStartAt;
  final DateTime? expireAt;

  static const _blue = GroupLiveOnlineLiveScaffold.primaryBlue;
  static const _titleColor = Color(0xFF1A1D24);
  static const _sub = Color(0xFF8A8F99);
  static const _chip = Color(0xFFF4F8FF);

  static String _fmt(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14002D6B),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: _chip,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned(
                      top: 8,
                      child: Icon(
                        Icons.calendar_today_outlined,
                        size: 22,
                        color: _blue,
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: _chip,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          size: 15,
                          color: _blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i18n.t(
                        zhHans: '选择新的直播时间，开启你的精彩直播',
                        zhHant: '選擇新的直播時間，開啟你的精彩直播',
                        en: 'Pick a new time and start your next live.',
                        ja: '新しい開始時刻を選んで配信を始めましょう。',
                        ko: '새 방송 시간을 선택하고 라이브를 시작하세요.',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: _sub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _timeRow(
            Icons.live_tv_rounded,
            i18n.t(
                zhHans: '直播间昵称',
                zhHant: '直播間暱稱',
                en: 'Room name',
                ja: '配信名',
                ko: '방송 이름'),
            roomName.trim().isNotEmpty
                ? roomName.trim()
                : i18n.t(
                    zhHans: '未设置',
                    zhHant: '未設定',
                    en: 'Not set',
                    ja: '未設定',
                    ko: '미설정'),
          ),
          const SizedBox(height: 8),
          _timeRow(
            Icons.notes_rounded,
            i18n.t(
                zhHans: '直播描述',
                zhHant: '直播描述',
                en: 'Description',
                ja: '配信の説明',
                ko: '방송 설명'),
            description.trim().isNotEmpty
                ? description.trim()
                : i18n.t(
                    zhHans: '未设置',
                    zhHant: '未設定',
                    en: 'Not set',
                    ja: '未設定',
                    ko: '미설정'),
          ),
          const SizedBox(height: 8),
          _timeRow(
            Icons.play_arrow_rounded,
            i18n.t(
              zhHans: '预计开播',
              zhHant: '預計開播',
              en: 'Scheduled',
              ja: '開始予定',
              ko: '예상 시작',
            ),
            _fmt(scheduledStartAt),
          ),
          const SizedBox(height: 8),
          _timeRow(
            Icons.schedule_rounded,
            i18n.t(
              zhHans: '有效期至',
              zhHant: '有效期至',
              en: 'Valid until',
              ja: '有効期限',
              ko: '유효 기간',
            ),
            _fmt(expireAt),
          ),
        ],
      ),
    );
  }

  static Widget _timeRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _blue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '|',
              style: TextStyle(color: Color(0xFFD0D5DD)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                color: _titleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
