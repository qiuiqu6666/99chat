import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

typedef GroupNameCardEditorProfile = ({
  String nameCard,
  String nickname,
  String faceUrl,
});

/// Route-owned display data. Profile hydration never gates a nickname write.
class GroupNameCardProfileSource extends ChangeNotifier {
  GroupNameCardProfileSource({
    required this.model,
    Future<MeResult> Function(CancelToken)? loadMe,
    Future<UserProfileRecord?> Function(String userId)? readLocal,
    this.timeout = const Duration(seconds: 6),
  })  : identity = SessionIdentityService.instance.capture(),
        groupId = model.groupID,
        _loadMe = loadMe ?? _fetchMe,
        _readLocal = readLocal ??
            ((id) => UserProfileLocalStore.instance
                .read(userId: id, ownerUserId: id)) {
    _value = _resolve();
    model.addListener(_onChanged);
    _self.addListener(_onChanged);
    GroupMemberStore.instance.addListener(_onChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onProfileChanged);
    if (_value.nickname.isEmpty || _value.faceUrl.isEmpty) {
      unawaited(reload());
    }
  }

  final TUIGroupProfileModel model;
  final SessionIdentity identity;
  final String groupId;
  final Duration timeout;
  final Future<MeResult> Function(CancelToken) _loadMe;
  final Future<UserProfileRecord?> Function(String) _readLocal;
  final TUISelfInfoViewModel _self = serviceLocator<TUISelfInfoViewModel>();
  late GroupNameCardEditorProfile _value;
  GroupNameCardEditorProfile get value => _value;
  UserProfileRecord? _diskProfile;
  MeResult? _remoteProfile;
  Future<void>? _task;
  CancelToken? _cancel;
  bool _disposed = false;
  bool loading = false;
  bool loadFailed = false;
  int _profileRevision = 0;

  bool get isCurrent =>
      !_disposed &&
      model.groupID == groupId &&
      SessionIdentityService.instance.isCurrent(identity);

  static Future<MeResult> _fetchMe(CancelToken cancel) async {
    // Own the cancellation scope: do not cancel another page's shared /me load.
    final response =
        await ApiClient.instance.dio.get('/me', cancelToken: cancel);
    return MeResult.fromJson(response.data);
  }

  GroupNameCardEditorProfile _resolve() {
    if (!isCurrent) return (nameCard: '', nickname: '', faceUrl: '');
    final owner = identity.ownerUserId;
    final cached = UserProfileLocalService.instance.readCached(owner);
    final self = _self.loginInfo;
    final core = serviceLocator<CoreServicesImpl>().loginUserInfo;
    final member = GroupMemberStore.instance.memberOf(groupId, owner);
    final sources = [
      if (ChatIdFormat.rawUserUid(self?.userID) == owner) self,
      if (ChatIdFormat.rawUserUid(core?.userID) == owner) core,
    ];
    String first(Iterable<String?> values, {bool avatar = false}) {
      for (final raw in values) {
        final text = avatar
            ? UserAvatarHelper.usableAvatarOrEmpty(raw)
            : (raw ?? '').trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    return (
      nameCard: model.getSelfNameCard(),
      nickname: first([
        _remoteProfile?.nickname,
        cached?.nickname,
        _diskProfile?.nickname,
        ...sources.map((info) => info?.nickName),
        member?.nickName,
      ]),
      faceUrl: first([
        _remoteProfile?.avatarUrl,
        cached?.avatarUrl,
        _diskProfile?.avatarUrl,
        ...sources.map((info) => info?.faceUrl),
        member?.faceUrl,
      ], avatar: true),
    );
  }

  void _onChanged() {
    if (_disposed) return;
    final next = _resolve();
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }

  void _onProfileChanged() {
    if (!isCurrent ||
        PeerProfileRefreshBus.instance.matchesLatest(identity.ownerUserId)) {
      // A newer local profile edit takes precedence over the earlier /me read.
      _remoteProfile = null;
      _profileRevision++;
      _onChanged();
    }
  }

  Future<void> reload() {
    if (_task != null) return _task!;
    if (!isCurrent) return Future<void>.value();
    final cancel = CancelToken();
    _cancel = cancel;
    loading = true;
    loadFailed = false;
    notifyListeners();
    final profileRevision = _profileRevision;
    final operation = ChatRecoveryTrace.nextOperation('name_card_profile');
    void trace(String stage) =>
        ChatRecoveryTrace.log('name_card_profile_$stage',
            conversationID: 'group_$groupId', operation: operation);
    trace('load');
    bool accepts() =>
        isCurrent && identical(_cancel, cancel) && !cancel.isCancelled;
    late final Future<void> task;
    task = Future.wait<void>([
      () async {
        try {
          final local = await _readLocal(identity.ownerUserId).timeout(timeout);
          if (!accepts()) return;
          if (ChatIdFormat.rawUserUid(local?.userId) == identity.ownerUserId) {
            _diskProfile = local;
            _onChanged();
          }
        } catch (_) {
          trace('local_unavailable');
        }
      }(),
      () async {
        try {
          final me = await _loadMe(cancel).timeout(timeout, onTimeout: () {
            cancel.cancel('name_card_profile_deadline');
            throw TimeoutException('name_card_profile_deadline');
          });
          if (!accepts()) return;
          if (ChatIdFormat.rawUserUid(me.userId) != identity.ownerUserId) {
            throw StateError('profile_owner_mismatch');
          }
          if (_profileRevision == profileRevision) {
            _remoteProfile = me;
          }
          _onChanged();
          trace('ready');
        } catch (_) {
          if (isCurrent && identical(_cancel, cancel)) loadFailed = true;
          trace('unavailable');
        }
      }(),
    ]).whenComplete(() {
      if (!identical(_task, task)) return;
      _task = null;
      _cancel = null;
      loading = false;
      if (!_disposed) {
        _value = _resolve();
        notifyListeners();
      }
    });
    _task = task;
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('name_card_profile_closed');
    model.removeListener(_onChanged);
    _self.removeListener(_onChanged);
    GroupMemberStore.instance.removeListener(_onChanged);
    PeerProfileRefreshBus.instance.revision.removeListener(_onProfileChanged);
    super.dispose();
  }
}
