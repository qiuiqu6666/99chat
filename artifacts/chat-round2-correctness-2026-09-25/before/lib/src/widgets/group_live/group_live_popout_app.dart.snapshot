import 'dart:async';
import 'dart:convert';
import 'group_live_playback_state.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';

class GroupLivePopoutApp extends StatelessWidget {
  const GroupLivePopoutApp({
    super.key,
    required this.windowId,
    required this.argumentJson,
  });

  final int windowId;
  final String argumentJson;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _GroupLivePopoutPage(
        windowId: windowId,
        argumentJson: argumentJson,
      ),
    );
  }
}

String _urlFromPayload(String playUrl, String fallbackFlvUrl) {
  final raw = fallbackFlvUrl.trim().isNotEmpty ? fallbackFlvUrl : playUrl;
  return MediaUrlResolver.resolve(raw) ?? raw;
}

class _GroupLivePopoutPage extends StatefulWidget {
  const _GroupLivePopoutPage({
    required this.windowId,
    required this.argumentJson,
  });

  final int windowId;
  final String argumentJson;

  @override
  State<_GroupLivePopoutPage> createState() => _GroupLivePopoutPageState();
}

class _GroupLivePopoutPageState extends State<_GroupLivePopoutPage> {
  late final Player _player;
  late final VideoController _videoController;
  late final GroupLivePlaybackState _playback;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _playback = GroupLivePlaybackState(
      openUrl: (url) => _player.open(Media(url), play: true),
      pause: _player.pause,
      errors: _player.stream.error,
      positions: _player.stream.position,
      completed: _player.stream.completed,
    );
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'switchUrl') {
        final payload = _decodePayload(call.arguments);
        await _open(
          playUrl: payload.$1,
          fallbackFlvUrl: payload.$2,
        );
      }
      return null;
    });
    final initial = _decodePayload(widget.argumentJson);
    unawaited(_open(playUrl: initial.$1, fallbackFlvUrl: initial.$2));
  }

  (String, String) _decodePayload(dynamic raw) {
    if (raw is Map) {
      return (
        '${raw['playUrl'] ?? ''}',
        '${raw['fallbackFlvUrl'] ?? ''}',
      );
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return (
            '${decoded['playUrl'] ?? ''}',
            '${decoded['fallbackFlvUrl'] ?? ''}',
          );
        }
      } catch (_) {}
    }
    return ('', '');
  }

  Future<void> _open({
    required String playUrl,
    required String fallbackFlvUrl,
  }) async {
    await _playback.open(_urlFromPayload(playUrl, fallbackFlvUrl));
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    _playback.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : 100);
    if (mounted) setState(() {});
  }

  Future<void> _closeWindow() {
    return WindowController.fromWindowId(widget.windowId).hide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _playback,
            builder: (context, child) => Stack(
              fit: StackFit.expand,
              children: [child!, GroupLivePlaybackError(playback: _playback)],
            ),
            child: Video(
              controller: _videoController,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    icon: Icon(
                      _muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () => unawaited(_toggleMute()),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () => unawaited(_closeWindow()),
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
