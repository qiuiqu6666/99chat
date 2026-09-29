import 'dart:async';

import 'group_live_member_loader.dart';
import 'group_live_member_picker_page.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_online_live_scaffold.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_push_info_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_routing.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_info_resolver.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_live_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';

String _groupLiveAuthorizeCurrentUserId() {
  try {
    final id = TIMUIKitCore.getInstance().loginInfo.userID.trim();
    if (id.isNotEmpty) return id;
  } catch (_) {}
  return SessionManager.instance.state.userId?.trim() ?? '';
}

class GroupLiveAuthorizePage extends StatefulWidget {
  const GroupLiveAuthorizePage._({
    required this.groupId,
    this.initialSession,
    this.manageOnly = false,
  });

  final String groupId;
  final GroupLiveSession? initialSession;
  final bool manageOnly;

  static Future<void> openSchedule(BuildContext context,
      {required String groupId}) {
    return Navigator.of(context).push<void>(
      AppMaterialPageRoute(
        builder: (_) => GroupLiveAuthorizePage._(groupId: groupId),
      ),
    );
  }

  static Future<void> openScheduleReplacing(
    BuildContext context, {
    required String groupId,
  }) {
    return Navigator.of(context).pushReplacement(
      AppMaterialPageRoute<void>(
        builder: (_) => GroupLiveAuthorizePage._(groupId: groupId),
      ),
    );
  }

  static Widget buildManage({
    required String groupId,
    GroupLiveSession? initialSession,
  }) {
    return GroupLiveAuthorizePage._(
      groupId: groupId,
      initialSession: initialSession,
      manageOnly: true,
    );
  }

  static Future<void> openManage(
    BuildContext context, {
    required String groupId,
    GroupLiveSession? initialSession,
  }) {
    return Navigator.of(context).push<void>(
      AppMaterialPageRoute(
        builder: (_) => GroupLiveAuthorizePage._(
          groupId: groupId,
          initialSession: initialSession,
          manageOnly: true,
        ),
      ),
    );
  }

  @override
  State<GroupLiveAuthorizePage> createState() => _GroupLiveAuthorizePageState();
}

class _GroupLiveAuthorizePageState extends State<GroupLiveAuthorizePage> {
  final _roomNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  RedPacketMember? _anchor;
  DateTime? _scheduledAt;
  GroupLiveSession? _session;
  bool _submitting = false;
  bool _loadingMembers = false;
  bool _startImmediately = true;
  bool? _isOwner;
  bool _isManager = false;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    if (_session != null) {
      _roomNameController.text = _session!.roomName;
      _descriptionController.text = _session!.description;
      if (_session!.scheduledStartAt != null) {
        _scheduledAt = _session!.scheduledStartAt!.toLocal();
      }
    }
    unawaited(_loadRole());
    unawaited(_seedAnchorFromSession());
  }

  Future<void> _seedAnchorFromSession() async {
    final session = _session;
    if (session == null) return;
    final anchorId = session.anchorUserId.trim();
    if (anchorId.isEmpty) return;
    List<RedPacketMember> members;
    try {
      members = await _loadLocalMembers(anchorId);
    } catch (_) {
      members = const [];
    }
    if (!mounted || _anchor != null) return;
    for (final member in members) {
      if (member.userId.trim() == anchorId) {
        setState(() => _anchor = member);
        return;
      }
    }
    setState(
      () => _anchor = RedPacketMember(userId: anchorId, name: anchorId),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    final role = await GroupInfoResolver.instance.myRole(widget.groupId);
    if (!mounted) return;
    setState(() {
      _isOwner = GroupRolePolicy.isOwnerRole(role);
      _isManager = GroupRolePolicy.isManagerRole(role);
    });
  }

  Future<List<RedPacketMember>> _loadLocalMembers(String userId) async {
    final groupId = ChatIdFormat.canonicalGroupStorageId(widget.groupId);
    if (groupId.isEmpty) {
      return const [];
    }
    final local =
        await GroupMemberLocalStore.instance.readRecordsByUserIds(
          groupId: groupId, userIds: [userId],
        );
    return local
        .map(
          (record) => RedPacketMember(
            userId: record.userId,
            name: record.friendRemark.trim().isNotEmpty
                ? record.friendRemark.trim()
                : record.displayName,
            publicName: record.nickname,
            avatar: record.avatarUrl,
          ),
        )
        .where((member) => member.userId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _pickAnchor() async {
    if (_loadingMembers) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loadingMembers = true);
    try {
      final picked = await Navigator.of(context).push<RedPacketMember>(
        AppMaterialPageRoute(
          builder: (_) => GroupLiveMemberPickerPage(
            loadPage: groupLiveMemberPageLoader(widget.groupId),
          ),
        ),
      );
      if (picked != null && mounted) {
        setState(() => _anchor = picked);
      }
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  bool _isScheduleTimeTooSoon(DateTime scheduledAt) {
    return scheduledAt.isBefore(groupLiveScheduleMinimumDate());
  }

  Future<void> _pickTime() async {
    final initial = _scheduledAt ?? groupLiveScheduleMinimumDate();
    final picked = await showGroupLiveScheduleTimePicker(
      context,
      initialDateTime: initial,
      minimumDate: groupLiveScheduleMinimumDate(),
      maximumDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startImmediately = false;
      _scheduledAt = picked;
    });
  }

  Future<void> _authorize() async {
    final roomName = _roomNameController.text.trim();
    final anchorId = _anchor?.userId.trim() ?? '';
    final scheduledAt = _startImmediately ? null : _scheduledAt;
    if (roomName.isEmpty || anchorId.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '请填写直播间名称并选择主播',
        zhHant: '請填寫直播間名稱並選擇主播',
        en: 'Enter a room name and pick an anchor.',
        ja: 'ルーム名とアンカーを入力してください。',
        ko: '라이브룸 이름과 앵커를 설정해 주세요.',
      ));
      return;
    }
    if (!_startImmediately && scheduledAt == null) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '请设置开播时间',
        zhHant: '請設置開播時間',
        en: 'Set a start time.',
        ja: '開始時刻を設定してください。',
        ko: '시작 시간을 설정해 주세요.',
      ));
      return;
    }
    if (scheduledAt != null && _isScheduleTimeTooSoon(scheduledAt)) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '开播时间需晚于当前时间至少 1 分钟',
        zhHant: '開播時間需晚於當前時間至少 1 分鐘',
        en: 'Start time must be at least 1 minute from now.',
        ja: '開始時刻は現在から1分以上後に設定してください。',
        ko: '시작 시간은 현재보다 최소 1분 이후여야 합니다.',
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final description = _descriptionController.text.trim();
      final session = await GroupLiveApi.instance.authorize(
        groupId: widget.groupId,
        anchorUserId: anchorId,
        roomName: roomName,
        scheduledStartAt: scheduledAt?.toUtc(),
        description: description.isEmpty ? null : description,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _roomNameController.text = session.roomName;
        _descriptionController.text = session.description;
        if (session.scheduledStartAt != null) {
          _scheduledAt = session.scheduledStartAt!.toLocal();
        }
      });
      try {
        await GroupLiveApi.instance.current(groupId: widget.groupId);
      } catch (_) {}
      if (!mounted) return;
      await GroupLiveRouting.routeAfterAuthorize(
        context,
        session: session,
        groupId: widget.groupId,
      );
    } catch (e) {
      if (!mounted) return;
      ToastUtils.toast(GroupLiveErrorMessage.from(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _updateSchedule() async {
    final scheduledAt = _scheduledAt;
    if (scheduledAt == null) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '请设置预计开播时间',
        zhHant: '請設置預計開播時間',
        en: 'Set a scheduled start time.',
        ja: '開始予定時刻を設定してください。',
        ko: '예상 시작 시간을 설정해 주세요.',
      ));
      return;
    }
    if (_isScheduleTimeTooSoon(scheduledAt)) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '开播时间需晚于当前时间至少 1 分钟',
        zhHant: '開播時間需晚於當前時間至少 1 分鐘',
        en: 'Start time must be at least 1 minute from now.',
        ja: '開始時刻は現在から1分以上後に設定してください。',
        ko: '시작 시간은 현재보다 최소 1분 이후여야 합니다.',
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = await GroupLiveApi.instance.updateSchedule(
        groupId: widget.groupId,
        roomName: _roomNameController.text.trim(),
        scheduledStartAt: scheduledAt.toUtc(),
      );
      if (!mounted) return;
      setState(() => _session = session);
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '已更新预约',
        zhHant: '已更新預約',
        en: 'Schedule updated',
        ja: '予約を更新しました',
        ko: '예약 업데이트됨',
      ));
    } catch (e) {
      if (!mounted) return;
      ToastUtils.toast(GroupLiveErrorMessage.from(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 结束直播 = 删除配置；若已在推流则同时结束推流。
  Future<void> _endLive() async {
    final session = _session;
    if (session == null) return;
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
              zhHans: '确定结束本次直播吗？结束后需重新配置。',
              zhHant: '確定結束本次直播嗎？結束後需重新配置。',
              en: 'End this live? You will need to set it up again.',
              ja: 'この配信を終了しますか？終了後は再設定が必要です。',
              ko: '이 라이브를 종료할까요? 종료 후 다시 설정해야 합니다.',
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
        await GroupLiveApi.instance.stop(groupId: widget.groupId);
      } else {
        await GroupLiveApi.instance.revoke(groupId: widget.groupId);
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

  Future<void> _openPushInfo() async {
    final session = _session;
    if (session == null) return;
    await GroupLivePushInfoPage.open(
      context,
      liveSessionId: session.liveSessionId,
      initialSession: session,
      groupId: widget.groupId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final isManage = widget.manageOnly && _session != null;
    final canEditSchedule = _session?.status == GroupLiveStatus.scheduled;
    final canEndLive = _session != null &&
        (_session!.status == GroupLiveStatus.scheduled ||
            _session!.status == GroupLiveStatus.authorized ||
            _session!.isLive);
    final selfId = _groupLiveAuthorizeCurrentUserId();
    final isAnchor = _session != null &&
        selfId.isNotEmpty &&
        selfId == _session!.anchorUserId.trim();
    final canOpenPush = _session != null &&
        (_session!.status == GroupLiveStatus.authorized ||
            _session!.status == GroupLiveStatus.live) &&
        (_isOwner == true || _isManager || isAnchor);

    if (!isManage) {
      return GroupLiveOnlineLiveScaffold(
        backgroundColor: Colors.transparent,
        backgroundDecoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/livebg.webp'),
            fit: BoxFit.cover,
          ),
        ),
        bodyPadding: EdgeInsets.zero,
        extendBodyBehindAppBar: true,
        actions: [
          TextButton.icon(
            onPressed: () => showGroupLiveObsGuideSheet(context),
            icon: const Icon(
              Icons.help_outline,
              size: 16,
              color: Color(0xFF8A8F99),
            ),
            label: Text(
              i18n.t(
                zhHans: '直播教程',
                zhHant: '直播教程',
                en: 'Live guide',
                ja: '配信ガイド',
                ko: '라이브 가이드',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8A8F99),
              ),
            ),
          ),
        ],
        body: _CreateLiveForm(
          roomNameController: _roomNameController,
          descriptionController: _descriptionController,
          anchor: _anchor,
          loadingMembers: _loadingMembers,
          startImmediately: _startImmediately,
          scheduledAt: _scheduledAt,
          onPickAnchor: () => unawaited(_pickAnchor()),
          onStartImmediately: () {
            setState(() {
              _startImmediately = true;
              _scheduledAt = groupLiveScheduleMinimumDate();
            });
          },
          onStartScheduled: () => unawaited(_pickTime()),
        ),
        bottomButton: _CreateLiveSubmitButton(
          loading: _submitting,
          onPressed: () => unawaited(_authorize()),
        ),
      );
    }

    return GroupLiveOnlineLiveScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupLiveScheduleHeader(),
          const SizedBox(height: 24),
          GroupLiveFormSection(
            title: i18n.t(
              zhHans: '直播设置',
              zhHant: '直播設置',
              en: 'Live settings',
              ja: '配信設定',
              ko: '라이브 설정',
            ),
            children: [
              GroupLiveRoomNameField(
                controller: _roomNameController,
                enabled: canEditSchedule,
              ),
              GroupLiveDescriptionField(
                controller: _descriptionController,
                enabled: canEditSchedule,
              ),
              GroupLiveScheduleField(
                label: i18n.t(
                  zhHans: '预计开播时间',
                  zhHant: '預計開播時間',
                  en: 'Scheduled start',
                  ja: '開始予定',
                  ko: '예상 시작 시간',
                ),
                value: _scheduledAt == null
                    ? ''
                    : DateFormat('yyyy-MM-dd HH:mm')
                        .format(_scheduledAt!.toLocal()),
                placeholder: i18n.t(
                  zhHans: '可设置预计开播时间',
                  zhHant: '可設置預計開播時間',
                  en: 'Set scheduled start time',
                  ja: '開始予定時刻を設定',
                  ko: '예상 시작 시간 설정',
                ),
                trailing: GroupLiveFieldTrailing.calendar,
                onTap: canEditSchedule ? () => unawaited(_pickTime()) : null,
              ),
              if (canOpenPush)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => unawaited(_openPushInfo()),
                      child: Text(
                        i18n.t(
                          zhHans: '查看推流地址',
                          zhHant: '查看推流地址',
                          en: 'View push info',
                          ja: '配信URLを見る',
                          ko: '推流 주소 보기',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomButton: _buildBottomButton(
        i18n: i18n,
        isManage: isManage,
        canEditSchedule: canEditSchedule,
        canEndLive: canEndLive,
      ),
    );
  }

  Widget? _buildBottomButton({
    required AppI18n i18n,
    required bool isManage,
    required bool canEditSchedule,
    required bool canEndLive,
  }) {
    if (!isManage) {
      return GroupLivePrimaryButton(
        label: i18n.t(
          zhHans: '预约直播',
          zhHant: '預約直播',
          en: 'Schedule live',
          ja: '配信を予約',
          ko: '라이브 예약',
        ),
        loading: _submitting,
        onPressed: () => unawaited(_authorize()),
      );
    }
    if (canEditSchedule) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canEndLive)
            TextButton(
              onPressed: _submitting ? null : () => unawaited(_endLive()),
              child: Text(
                i18n.t(
                  zhHans: '结束直播',
                  zhHant: '結束直播',
                  en: 'End live',
                  ja: '配信終了',
                  ko: '라이브 종료',
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFEF5350),
                ),
              ),
            ),
          GroupLivePrimaryButton(
            label: i18n.t(
              zhHans: '保存修改',
              zhHant: '保存修改',
              en: 'Save changes',
              ja: '保存',
              ko: '저장',
            ),
            loading: _submitting,
            onPressed: () => unawaited(_updateSchedule()),
          ),
        ],
      );
    }
    if (canEndLive) {
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
    return null;
  }
}

class _CreateLiveForm extends StatelessWidget {
  const _CreateLiveForm({
    required this.roomNameController,
    required this.descriptionController,
    required this.anchor,
    required this.loadingMembers,
    required this.startImmediately,
    required this.scheduledAt,
    required this.onPickAnchor,
    required this.onStartImmediately,
    required this.onStartScheduled,
  });

  final TextEditingController roomNameController;
  final TextEditingController descriptionController;
  final RedPacketMember? anchor;
  final bool loadingMembers;
  final bool startImmediately;
  final DateTime? scheduledAt;
  final VoidCallback onPickAnchor;
  final VoidCallback onStartImmediately;
  final VoidCallback onStartScheduled;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Transform.translate(
      offset: const Offset(0, -24),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Image.asset(
            'assets/live2.webp',
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
                  Text(
                    i18n.t(
                      zhHans: '直播设置',
                      zhHant: '直播設置',
                      en: 'Live settings',
                      ja: '配信設定',
                      ko: '라이브 설정',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1D24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i18n.t(
                        zhHans: '简单几步，快速开启直播',
                        zhHant: '簡單幾步，快速開啟直播',
                        en: 'A few steps to go live',
                        ja: '数ステップで配信開始',
                        ko: '몇 단계로 빠르게 시작',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9AA1AD),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _CreateLabeledField(
                icon: Icons.title,
                label: i18n.t(
                  zhHans: '直播间名称',
                  zhHant: '直播間名稱',
                  en: 'Room name',
                  ja: 'ルーム名',
                  ko: '라이브룸 이름',
                ),
                child: _CreateCounterField(
                  controller: roomNameController,
                  maxLength: GroupLiveRoomNameField.maxLength,
                  hint: i18n.t(
                    zhHans: '请输入直播间名称',
                    zhHant: '請輸入直播間名稱',
                    en: 'Enter a room name (e.g. 99CHAT official)',
                    ja: 'ルーム名を入力（例：99CHAT公式）',
                    ko: '라이브룸 이름을 입력하세요',
                  ),
                ),
              ),
              _CreateLabeledField(
                icon: Icons.article,
                label: i18n.t(
                  zhHans: '直播描述（可选）',
                  zhHant: '直播描述（可選）',
                  en: 'Description (optional)',
                  ja: '説明（任意）',
                  ko: '설명(선택)',
                ),
                child: _CreateCounterField(
                  controller: descriptionController,
                  maxLength: GroupLiveDescriptionField.maxLength,
                  hint: i18n.t(
                    zhHans: '介绍一下你的直播内容，吸引更多观众',
                    zhHant: '介紹一下你的直播內容，吸引更多觀眾',
                    en: 'Introduce the stream to attract viewers',
                    ja: '配信内容を紹介して視聴者を集めましょう',
                    ko: '라이브 내용을 소개해 시청자를 모으세요',
                  ),
                ),
              ),
              _CreateLabeledField(
                icon: Icons.person,
                label: i18n.t(
                  zhHans: '主播',
                  zhHant: '主播',
                  en: 'Anchor',
                  ja: 'アンカー',
                  ko: '앵커',
                ),
                child: _CreateAnchorRow(
                  anchor: anchor,
                  loading: loadingMembers,
                  placeholder: loadingMembers
                      ? i18n.t(
                          zhHans: '加载中…',
                          zhHant: '載入中…',
                          en: 'Loading…',
                          ja: '読み込み中…',
                          ko: '로딩 중…',
                        )
                      : i18n.t(
                          zhHans: '请选择主播',
                          zhHant: '請選擇主播',
                          en: 'Select anchor',
                          ja: 'アンカーを選択',
                          ko: '앵커 선택',
                        ),
                  onTap: loadingMembers ? null : onPickAnchor,
                ),
              ),
              _CreateLabeledField(
                icon: Icons.calendar_today_outlined,
                label: i18n.t(
                  zhHans: '预计开播时间',
                  zhHant: '預計開播時間',
                  en: 'Start time',
                  ja: '開始予定',
                  ko: '예상 시작 시간',
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StartModeCard(
                            selected: startImmediately,
                            icon: Icons.bolt_rounded,
                            title: i18n.t(
                              zhHans: '立即开播',
                              zhHant: '立即開播',
                              en: 'Start now',
                              ja: 'すぐに配信',
                              ko: '바로 시작',
                            ),
                            subtitle: i18n.t(
                              zhHans: '准备好就开始直播',
                              zhHant: '準備好就開始直播',
                              en: 'Go live when ready',
                              ja: '準備できたら開始',
                              ko: '준비되면 바로 시작',
                            ),
                            onTap: onStartImmediately,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StartModeCard(
                            selected: !startImmediately,
                            icon: Icons.calendar_month_outlined,
                            title: i18n.t(
                              zhHans: '预约开播',
                              zhHant: '預約開播',
                              en: 'Schedule',
                              ja: '予約配信',
                              ko: '예약 시작',
                            ),
                            subtitle: scheduledAt == null
                                ? i18n.t(
                                    zhHans: '设置未来的开播时间',
                                    zhHant: '設置未來的開播時間',
                                    en: 'Pick a future start time',
                                    ja: '開始時刻を設定',
                                    ko: '시작 시간을 설정',
                                  )
                                : DateFormat('yyyy-MM-dd HH:mm')
                                    .format(scheduledAt!.toLocal()),
                            onTap: onStartScheduled,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Color(0xFF8A8F99),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            i18n.t(
                              zhHans: '开播后可在直播间进行更多设置（封面、公告、礼物等）',
                              zhHant: '開播後可在直播間進行更多設置（封面、公告、禮物等）',
                              en: 'More settings after going live (cover, notice, gifts).',
                              ja: '開始後にカバー・告知・ギフトなどを設定できます。',
                              ko: '시작 후 커버, 공지, 선물 등을 설정할 수 있습니다.',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: Color(0xFF8A8F99),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ],
    ),
    );
  }
}

class _CreateLabeledField extends StatelessWidget {
  const _CreateLabeledField({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF3FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: GroupLiveOnlineLiveScaffold.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1D24),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateCounterField extends StatelessWidget {
  const _CreateCounterField({
    required this.controller,
    required this.maxLength,
    required this.hint,
  });

  final TextEditingController controller;
  final int maxLength;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLength: maxLength,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: Color(0xFF1A1D24),
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ).copyWith(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFB4B8C2),
                    ),
                  ),
                ),
              ),
              Text(
                '${controller.text.length}/$maxLength',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFC0C4CC),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreateAnchorRow extends StatelessWidget {
  const _CreateAnchorRow({
    required this.anchor,
    required this.loading,
    required this.placeholder,
    required this.onTap,
  });

  final RedPacketMember? anchor;
  final bool loading;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = anchor?.name.trim() ?? '';
    return Material(
      color: const Color(0xFFF4F6F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              AppUserAvatar(
                faceUrl: anchor?.avatar ?? '',
                showName: name.isNotEmpty ? name : placeholder,
                size: 36,
                type: 1,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : placeholder,
                  style: TextStyle(
                    fontSize: 14,
                    color: name.isNotEmpty
                        ? const Color(0xFF1A1D24)
                        : const Color(0xFF8A8F99),
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFFC0C4CC),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartModeCard extends StatelessWidget {
  const _StartModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? GroupLiveOnlineLiveScaffold.primaryBlue
              : const Color(0xFFE6EAF0),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? GroupLiveOnlineLiveScaffold.primaryBlue
                        : const Color(0xFF8A8F99),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? GroupLiveOnlineLiveScaffold.primaryBlue
                            : const Color(0xFF1F2329),
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected
                        ? GroupLiveOnlineLiveScaffold.primaryBlue
                        : const Color(0xFFC5CAD3),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A8F99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateLiveSubmitButton extends StatelessWidget {
  const _CreateLiveSubmitButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: GroupLiveOnlineLiveScaffold.primaryBlue,
          disabledBackgroundColor:
              GroupLiveOnlineLiveScaffold.primaryBlue.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    i18n.t(
                      zhHans: '预约直播',
                      zhHant: '預約直播',
                      en: 'Schedule live',
                      ja: '配信を予約',
                      ko: '라이브 예약',
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
      ),
    );
  }
}
