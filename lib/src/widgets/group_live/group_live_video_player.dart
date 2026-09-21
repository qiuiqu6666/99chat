import 'dart:async';
import 'group_live_playback_state.dart';
import 'group_live_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_cast_button.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_chrome_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_popout_window.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';

class GroupLiveVideoPlayer extends StatefulWidget {
  const GroupLiveVideoPlayer(
      {super.key,
      required this.playInfo,
      this.compact = false,
      this.startupClock,
      this.fit = BoxFit.contain,
      this.onClose,
      this.showLiveStatus = false});
  final GroupLivePlayInfo playInfo;
  final bool compact;
  final Stopwatch? startupClock;
  final BoxFit fit;
  final VoidCallback? onClose;
  final bool showLiveStatus;
  @override
  State<GroupLiveVideoPlayer> createState() => GroupLiveVideoPlayerState();
}

class GroupLiveVideoPlayerState extends State<GroupLiveVideoPlayer>
    with WidgetsBindingObserver {
  late Player _player;
  late VideoController _videoController;
  late GroupLivePlaybackState _playback;
  late GroupLiveStartup _startup;
  int _sourceIndex = 0;
  bool _muted = false;
  bool _isFullscreen = false;
  String get _url {
    final sources = groupLiveHttpSources(widget.playInfo);
    final raw = sources.isEmpty
        ? ''
        : sources[_sourceIndex.clamp(0, sources.length - 1)];
    return MediaUrlResolver.resolve(raw) ?? raw;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayback();
  }

  void _initializePlayback() {
    _startup = GroupLiveStartup();
    _player = Player();
    if (_muted) unawaited(_player.setVolume(0));
    _videoController = VideoController(_player);
    _playback = GroupLivePlaybackState(
      openUrl: (url) => _player.open(Media(url), play: true),
      pause: _player.pause,
      errors: _player.stream.error,
      positions: _player.stream.position,
      completed: _player.stream.completed,
    );
    _waitForFirstFrame();
    unawaited(_open());
  }

  void _waitForFirstFrame() {
    _startup.waitForFrame(_videoController.waitUntilFirstFrameRendered,
        onReady: (elapsed) {
      if (kDebugMode || kProfileMode) {
        debugPrint(
            '[GroupLiveStartup] first_frame_ms=${elapsed.inMilliseconds} '
            'view_to_frame_ms=${widget.startupClock?.elapsedMilliseconds} '
            'source=$_sourceIndex scheme=${Uri.tryParse(_url)?.scheme}');
      }
    });
  }

  Future<void> _open() => _playback.open(_url);

  void _retryStartup() {
    // Try each supported fallback only on explicit retry. Never race decoders.
    if (!_startup.ready) {
      final sources = groupLiveHttpSources(widget.playInfo);
      if (_sourceIndex + 1 < sources.length) _sourceIndex++;
      _waitForFirstFrame();
    }
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant GroupLiveVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playInfo.liveSessionId != widget.playInfo.liveSessionId ||
        !listEquals(groupLiveHttpSources(oldWidget.playInfo),
            groupLiveHttpSources(widget.playInfo))) {
      // The first-frame future belongs to one controller lifetime. A new stream
      // must not inherit the completed future or picture of the previous stream.
      _startup.dispose();
      _playback.dispose();
      unawaited(_player.dispose());
      _sourceIndex = 0;
      _initializePlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _startup.suspend();
      unawaited(_playback.pause());
    } else if (state == AppLifecycleState.resumed) {
      if (!_startup.ready) _waitForFirstFrame();
      unawaited(_playback.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startup.dispose();
    _playback.dispose();
    _player.dispose();
    super.dispose();
  }

  void toggleFullscreen() => _toggleFullscreen();

  Future<void> _toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : 100);
    if (mounted) setState(() {});
  }

  void _toggleFullscreen() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        widget.compact) {
      unawaited(GroupLivePopoutWindow.openOrFocus(widget.playInfo));
      return;
    }
    if (_isFullscreen) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _isFullscreen = true);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                body: SafeArea(
                    child: Stack(fit: StackFit.expand, children: [
                  _buildVideo(),
                  Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                          icon: const Icon(Icons.fullscreen_exit,
                              color: Colors.white),
                          onPressed: () => Navigator.of(context).pop()))
                ])))))
        .whenComplete(() {
      if (mounted) setState(() => _isFullscreen = false);
    });
  }

  Widget _buildVideo() => AnimatedBuilder(
        animation: Listenable.merge([_playback, _startup]),
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (!_startup.ready && _playback.error == null)
              Center(
                  child: _startup.timedOut
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('直播连接较慢，请重试',
                              style: TextStyle(color: Colors.white)),
                          TextButton(
                              onPressed: _retryStartup,
                              child: const Text('重新连接')),
                        ])
                      : const Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(height: 8),
                          Text('正在连接直播…',
                              style: TextStyle(color: Colors.white70)),
                        ])),
            GroupLivePlaybackError(playback: _playback, onRetry: _retryStartup),
          ],
        ),
        child: Video(
            key: ObjectKey(_videoController),
            controller: _videoController,
            fit: widget.fit,
            controls: NoVideoControls),
      );
  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      _buildVideo(),
      if (widget.compact)
        Positioned(
            top: 4,
            left: 8,
            right: 8,
            child: GroupLiveInlineChromeBar(
                showLiveStatus: widget.showLiveStatus,
                showMediaButtons: true,
                muted: _muted,
                isFullScreen: _isFullscreen,
                onToggleMute: () => unawaited(_toggleMute()),
                onToggleFullscreen: _toggleFullscreen,
                onClose: widget.onClose ?? () {}))
      else
        Positioned(
            top: 8,
            left: 8,
            child: _CompactToolbar(
                muted: _muted,
                isFullScreen: _isFullscreen,
                onToggleMute: () => unawaited(_toggleMute()),
                onToggleFullscreen: _toggleFullscreen)),
      if (!widget.compact)
        const Positioned(
            top: 8,
            right: 8,
            child: GroupLiveCastButton(iconColor: Colors.white, iconSize: 22))
    ]);
  }
}

class _CompactToolbar extends StatelessWidget {
  const _CompactToolbar(
      {required this.muted,
      required this.isFullScreen,
      required this.onToggleMute,
      required this.onToggleFullscreen});
  final bool muted;
  final bool isFullScreen;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFullscreen;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: muted ? 'Unmute' : 'Mute',
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white, size: 18),
            onPressed: onToggleMute),
        const GroupLiveCastButton(iconSize: 18),
        IconButton(
            tooltip: isFullScreen ? 'Exit fullscreen' : 'Fullscreen',
            icon: Icon(isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white, size: 18),
            onPressed: onToggleFullscreen)
      ]));
}
