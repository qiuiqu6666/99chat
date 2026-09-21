import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_live_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_chrome_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_video_player.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';

/// Serializes live-session loads and keeps at most the latest explicit reload.
///
/// Poll ticks join the active load without queueing another request. User or
/// widget-driven reloads replace the single pending operation, so a session
/// change is picked up immediately after the current request settles.
@visibleForTesting
class GroupLiveLoadGate {
  Future<void>? _inFlight;
  Future<void> Function()? _pendingOperation;

  @visibleForTesting
  bool get isBusy => _inFlight != null;

  Future<void> run(
    Future<void> Function() operation, {
    bool queueLatestIfBusy = false,
  }) {
    final active = _inFlight;
    if (active != null) {
      if (queueLatestIfBusy) {
        _pendingOperation = operation;
      }
      return active;
    }

    late final Future<void> tracked;
    tracked = _drain(operation).whenComplete(() {
      if (identical(_inFlight, tracked)) {
        _inFlight = null;
      }
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<void> _drain(Future<void> Function() initialOperation) async {
    var next = initialOperation;
    while (true) {
      await next();
      final pending = _pendingOperation;
      _pendingOperation = null;
      if (pending == null) {
        return;
      }
      next = pending;
    }
  }
}

/// In-chat 16:9 live preview (watch while chatting), matching the product mock.
class GroupLiveInlineWatchBanner extends StatefulWidget {
  const GroupLiveInlineWatchBanner({
    super.key,
    required this.session,
    required this.onClose,
    this.anchorFaceUrl = '',
    this.followRouteVisibility = true,
  });

  final GroupLiveSession session;
  final VoidCallback onClose;
  final String anchorFaceUrl;
  final bool followRouteVisibility;

  @override
  State<GroupLiveInlineWatchBanner> createState() =>
      _GroupLiveInlineWatchBannerState();
}

class _GroupLiveInlineWatchBannerState extends State<GroupLiveInlineWatchBanner>
    with WidgetsBindingObserver {
  GroupLivePlayInfo? _playInfo;
  final Stopwatch _startupClock = Stopwatch()..start();
  bool _loading = true;
  bool _waitingForPush = false;
  String? _error;
  String _title = '';
  Timer? _pollTimer;
  bool _surfaceVisible = false;
  bool _foreground = true;
  int _generation = 0;
  final GlobalKey<GroupLiveVideoPlayerState> _playerKey =
      GlobalKey<GroupLiveVideoPlayerState>();
  bool get _workEnabled => mounted && _surfaceVisible && _foreground;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = !widget.followRouteVisibility ||
        (RouteVisibility.isRouteVisible(context) &&
            TickerMode.valuesOf(context).enabled);
    if (visible != _surfaceVisible) {
      _surfaceVisible = visible;
      _visibilityChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibilityChanged();
  }

  void _visibilityChanged() {
    ++_generation;
    _pollTimer?.cancel();
    if (_workEnabled) {
      unawaited(_load(silent: _playInfo != null, queueLatest: true));
    }
  }

  final GroupLiveLoadGate _loadGate = GroupLiveLoadGate();

  @override
  void initState() {
    super.initState();
    _title = widget.session.roomName.trim();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant GroupLiveInlineWatchBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged =
        oldWidget.session.liveSessionId != widget.session.liveSessionId;
    final becameLive = !oldWidget.session.isLive && widget.session.isLive;
    if (sessionChanged || becameLive) {
      ++_generation;
      _pollTimer?.cancel();
      if (sessionChanged) {
        _startupClock
          ..reset()
          ..start();
        _playInfo = null;
        _loading = true;
        _waitingForPush = false;
        _error = null;
      }
      _title = widget.session.roomName.trim();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (!_workEnabled || !_waitingForPush) return;
    _pollTimer = Timer(const Duration(seconds: 4), () {
      if (!_workEnabled || !_waitingForPush) return;
      unawaited(_load(silent: true));
    });
  }

  Future<void> _load({bool silent = false, bool queueLatest = false}) {
    if (!_workEnabled) return Future.value();
    final generation = _generation;
    final session = widget.session;
    return _loadGate.run(
      () => _loadOnce(session: session, silent: silent, generation: generation),
      // Poll ticks are disposable. Explicit loads (widget update / retry)
      // retain only the latest request while another load is active.
      queueLatestIfBusy: queueLatest || !silent,
    );
  }

  bool _isCurrentLoadSession(GroupLiveSession session, int generation) {
    return _workEnabled &&
        generation == _generation &&
        widget.session.liveSessionId == session.liveSessionId;
  }

  Future<void> _loadOnce({
    required GroupLiveSession session,
    required bool silent,
    required int generation,
  }) async {
    if (!_isCurrentLoadSession(session, generation)) return;
    if (LiveKitCallSession.instance.isInCall) {
      if (!mounted) return;
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '通话中无法进入直播间',
        zhHant: '通話中無法進入直播間',
        en: 'Cannot enter live room during a call.',
        ja: '通話中は視聴できません。',
        ko: '통화 중에는 라이브룸에 입장할 수 없습니다.',
      ));
      widget.onClose();
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _waitingForPush = false;
      });
    }

    var liveNow = session.isLive;
    if (!liveNow) {
      try {
        final latest = await GroupLiveApi.instance.sessionDetail(
          liveSessionId: session.liveSessionId,
        );
        if (!_isCurrentLoadSession(session, generation)) return;
        liveNow = latest.isLive;
        final roomName = latest.roomName.trim();
        if (roomName.isNotEmpty) {
          _title = roomName;
        }
      } catch (_) {
        // Keep waiting UI when detail refresh fails.
      }
    }

    if (!liveNow) {
      if (!_isCurrentLoadSession(session, generation)) return;
      setState(() {
        _loading = false;
        _waitingForPush = true;
        _error = null;
      });
      _startPollingIfNeeded();
      return;
    }

    if (!_isCurrentLoadSession(session, generation)) return;
    try {
      final requestClock = Stopwatch()..start();
      final playInfo = await GroupLiveApi.instance.playInfo(
        liveSessionId: session.liveSessionId,
      );
      if (!_isCurrentLoadSession(session, generation)) return;
      if (kDebugMode || kProfileMode) {
        debugPrint(
            '[GroupLiveStartup] play_info_ms=${requestClock.elapsedMilliseconds}');
      }
      final roomName = playInfo.roomName.trim();
      if (roomName.isNotEmpty) {
        _title = roomName;
      }
      await _initPlayer(playInfo);
      if (!_isCurrentLoadSession(session, generation)) return;
      _pollTimer?.cancel();
      setState(() {
        _loading = false;
        _waitingForPush = false;
        _error = null;
      });
    } on GroupLiveApiException catch (e) {
      if (!_isCurrentLoadSession(session, generation)) return;
      final code = e.code.trim().toUpperCase();
      final waiting = code == 'LIVE_NOT_LIVE' ||
          code == 'LIVE_NOT_AUTHORIZED_YET' ||
          code.contains('NOT_LIVE');
      setState(() {
        _loading = false;
        _waitingForPush = waiting;
        _error = waiting ? null : GroupLiveErrorMessage.from(e);
      });
      if (waiting) {
        _startPollingIfNeeded();
      }
    } catch (e) {
      if (!_isCurrentLoadSession(session, generation)) return;
      setState(() {
        _loading = false;
        _waitingForPush = false;
        _error = GroupLiveErrorMessage.from(e);
      });
    }
  }

  Future<void> _initPlayer(GroupLivePlayInfo info) async {
    if (!mounted) return;
    setState(() => _playInfo = info);
  }

  String _waitingText(AppI18n i18n) {
    if (widget.session.status == GroupLiveStatus.scheduled) {
      return i18n.t(
        zhHans: '直播尚未开始，请稍候',
        zhHant: '直播尚未開始，請稍候',
        en: 'Live has not started yet.',
        ja: '配信はまだ始まっていません。',
        ko: '라이브가 아직 시작되지 않았습니다.',
      );
    }
    return i18n.t(
      zhHans: '直播准备中，请稍候…',
      zhHant: '直播準備中，請稍候…',
      en: 'Live is getting ready. Please wait…',
      ja: '配信の準備中です。しばらくお待ちください…',
      ko: '라이브 준비 중입니다. 잠시만 기다려 주세요…',
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);

    return ColoredBox(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_playInfo != null)
              GroupLiveVideoPlayer(
                key: _playerKey,
                playInfo: _playInfo!,
                startupClock: _startupClock,
                compact: true,
                fit: BoxFit.cover,
                onClose: widget.onClose,
                showLiveStatus: widget.session.isLive,
              )
            else
              const ColoredBox(color: Color(0xFF111111)),
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            if (_waitingForPush && !_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sensors,
                        color: Colors.white70,
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _waitingText(i18n),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null && !_loading && !_waitingForPush)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => unawaited(_load()),
                        child: Text(
                          i18n.t(
                            zhHans: '重试',
                            zhHant: '重試',
                            en: 'Retry',
                            ja: '再試行',
                            ko: '재시도',
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 88,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x99000000),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _WatchingBottomBar(
                roomName: widget.session.roomName,
                description: widget.session.description,
                anchorUserId: widget.session.anchorUserId,
                groupId: widget.session.groupId,
                anchorFaceUrl: widget.anchorFaceUrl,
                onFullscreen: () =>
                    _playerKey.currentState?.toggleFullscreen(),
              ),
            ),
            if (_playInfo == null)
              Positioned(
                top: 4,
                left: 8,
                right: 8,
                child: GroupLiveInlineChromeBar(
                  showLiveStatus: widget.session.isLive,
                  showMediaButtons: false,
                  onClose: widget.onClose,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WatchingBottomBar extends StatelessWidget {
  const _WatchingBottomBar({
    required this.roomName,
    required this.description,
    required this.anchorUserId,
    required this.groupId,
    required this.anchorFaceUrl,
    required this.onFullscreen,
  });

  final String roomName;
  final String description;
  final String anchorUserId;
  final String groupId;
  final String anchorFaceUrl;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final trimmedName = roomName.trim();
    final title = trimmedName.isNotEmpty
        ? trimmedName
        : i18n.t(
            zhHans: '群直播',
            zhHant: '群直播',
            en: 'Group Live',
            ja: 'グループ配信',
            ko: '그룹 라이브',
          );
    final trimmedDescription = description.trim();
    final subtitle = (trimmedDescription.isNotEmpty &&
            trimmedDescription != 'null')
        ? trimmedDescription
        : '';
    final action = i18n.t(
      zhHans: '全屏观看',
      zhHant: '全屏觀看',
      en: 'Fullscreen',
      ja: '全画面',
      ko: '전체 화면',
    );
    return Row(
      children: [
        _WatchingAnchorAvatar(
          userId: anchorUserId,
          groupId: groupId,
          initialFaceUrl: anchorFaceUrl,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  shadows: [
                    Shadow(color: Color(0x66000000), blurRadius: 4),
                  ],
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE8E8E8),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    shadows: [
                      Shadow(color: Color(0x66000000), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          shape: const StadiumBorder(
            side: BorderSide(color: Colors.white, width: 1),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onFullscreen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.north_east,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatchingAnchorAvatar extends StatefulWidget {
  const _WatchingAnchorAvatar({
    required this.userId,
    required this.groupId,
    this.initialFaceUrl = '',
  });

  final String userId;
  final String groupId;
  final String initialFaceUrl;

  @override
  State<_WatchingAnchorAvatar> createState() => _WatchingAnchorAvatarState();
}

class _WatchingAnchorAvatarState extends State<_WatchingAnchorAvatar> {
  static const double _avatarSize = 44;

  late String _faceUrl;
  late String _normalizedUserId;
  late String _normalizedGroupId;

  @override
  void initState() {
    super.initState();
    _normalizedUserId = ChatIdFormat.rawUserUid(widget.userId);
    _normalizedGroupId = ChatIdFormat.normalizeGroupId(widget.groupId);
    _faceUrl = _resolveFaceFromLocalHints();
    GroupMemberStore.instance.addListener(_onMemberStoreChanged);
    if (_needsNetworkResolve(_faceUrl)) {
      unawaited(_resolveFaceUrl());
    }
  }

  @override
  void didUpdateWidget(covariant _WatchingAnchorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUserId = ChatIdFormat.rawUserUid(widget.userId);
    final nextGroupId = ChatIdFormat.normalizeGroupId(widget.groupId);
    final userChanged = nextUserId != _normalizedUserId;
    final groupChanged = nextGroupId != _normalizedGroupId;
    final hintChanged = oldWidget.initialFaceUrl != widget.initialFaceUrl;
    if (!userChanged && !groupChanged && !hintChanged) {
      return;
    }
    _normalizedUserId = nextUserId;
    _normalizedGroupId = nextGroupId;
    final nextFace = _resolveFaceFromLocalHints();
    if (nextFace != _faceUrl) {
      setState(() => _faceUrl = nextFace);
    }
    if (_needsNetworkResolve(_faceUrl)) {
      unawaited(_resolveFaceUrl());
    }
  }

  @override
  void dispose() {
    GroupMemberStore.instance.removeListener(_onMemberStoreChanged);
    super.dispose();
  }

  String _resolveFaceFromLocalHints() {
    final fromHint =
        UserAvatarHelper.usableAvatarOrEmpty(widget.initialFaceUrl);
    if (fromHint.isNotEmpty) {
      return fromHint;
    }
    return UserAvatarHelper.groupMemberFaceUrl(
      _normalizedGroupId,
      _normalizedUserId,
    );
  }

  bool _needsNetworkResolve(String faceUrl) {
    return UserAvatarHelper.usableAvatarOrEmpty(faceUrl).isEmpty &&
        _normalizedUserId.isNotEmpty;
  }

  void _onMemberStoreChanged() {
    final memberFace = UserAvatarHelper.groupMemberFaceUrl(
      _normalizedGroupId,
      _normalizedUserId,
    );
    if (memberFace.isEmpty || memberFace == _faceUrl) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _faceUrl = memberFace);
  }

  Future<void> _resolveFaceUrl() async {
    final id = _normalizedUserId;
    if (id.isEmpty) {
      return;
    }
    final resolved = await UserAvatarHelper.resolveChatPeerFaceUrl(
      peerUserId: id,
      messageFaceUrl: widget.initialFaceUrl,
      groupId: _normalizedGroupId,
    );
    final usable = UserAvatarHelper.usableAvatarOrEmpty(resolved);
    if (usable.isEmpty || !mounted || _normalizedUserId != id) {
      return;
    }
    if (usable == _faceUrl) {
      return;
    }
    setState(() => _faceUrl = usable);
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: AppUserAvatar(
        faceUrl: _faceUrl,
        showName: _normalizedUserId,
        size: _avatarSize,
        type: 1,
        preferRasterPlaceholder: true,
      ),
    );
  }
}
