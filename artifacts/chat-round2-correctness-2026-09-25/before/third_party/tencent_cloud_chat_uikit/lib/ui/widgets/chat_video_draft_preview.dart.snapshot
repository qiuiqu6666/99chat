import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:video_player/video_player.dart';

/// Local video confirmation owns one player, including while it initializes.
/// Navigation never waits for the native decoder to initialize or dispose.
class ChatVideoDraftPreview extends StatefulWidget {
  const ChatVideoDraftPreview(
      {super.key,
      required this.filePath,
      required this.sizeText,
      required this.durationSeconds,
      required this.canRetake,
      required this.onCancel,
      required this.onRetake,
      required this.onSend});

  final String filePath;
  final String sizeText;
  final int durationSeconds;
  final bool canRetake;
  final VoidCallback onCancel;
  final VoidCallback onRetake;
  final ValueChanged<int> onSend;

  @override
  State<ChatVideoDraftPreview> createState() => _ChatVideoDraftPreviewState();
}

class _ChatVideoDraftPreviewState extends State<ChatVideoDraftPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _firstPlaybackTimer;
  bool _loading = true;
  bool _failed = false;
  bool _closing = false;
  bool _active = true;
  late int _durationSeconds;

  @override
  void initState() {
    super.initState();
    _durationSeconds = widget.durationSeconds;
    WidgetsBinding.instance.addObserver(this);
    _active = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_initialize());
  }

  bool _owns(VideoPlayerController controller) =>
      mounted && !_closing && identical(_controller, controller);

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(File(widget.filePath),
        // Avoid the iOS texture/pixel-buffer rendering path for freshly recorded video.
        viewType: defaultTargetPlatform == TargetPlatform.iOS
            ? VideoViewType.platformView
            : VideoViewType.textureView);
    _controller = controller;
    controller.addListener(_onPlayerChanged);
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (!_owns(controller)) return;
      await controller.setLooping(true).timeout(const Duration(seconds: 2));
      if (!_owns(controller)) return;
      final milliseconds = controller.value.duration.inMilliseconds;
      setState(() {
        _loading = false;
        if (milliseconds > 0) _durationSeconds = (milliseconds / 1000).ceil();
      });
      // Attach the native view before starting playback.
      await WidgetsBinding.instance.endOfFrame;
      if (_owns(controller) && _active) await _play(controller);
    } catch (error) {
      if (_owns(controller)) _fail(error);
    }
  }

  Future<void> _play(VideoPlayerController controller) async {
    try {
      await controller.play().timeout(const Duration(seconds: 2));
      if (!_owns(controller) || !_active) return;
      _firstPlaybackTimer?.cancel();
      if (controller.value.position == Duration.zero) {
        _firstPlaybackTimer = Timer(const Duration(seconds: 8), () {
          if (_owns(controller) &&
              _active &&
              controller.value.position == Duration.zero) {
            _fail(StateError('Video playback did not advance'));
          }
        });
      }
    } catch (error) {
      if (_owns(controller)) _fail(error);
    }
  }

  void _onPlayerChanged() {
    final controller = _controller;
    if (controller?.value.hasError == true) {
      // A plugin may publish an error while another widget is rebuilding.
      scheduleMicrotask(() {
        if (controller != null && _owns(controller)) {
          _fail(StateError(controller.value.errorDescription ?? 'Video error'));
        }
      });
    }
  }

  void _fail(Object error) {
    if (!mounted || _closing || _failed) return;
    debugPrint('ChatCameraPreview: unavailable: $error');
    _releaseController();
    setState(() {
      _failed = true;
      _loading = false;
    });
  }

  void _releaseController() {
    _firstPlaybackTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onPlayerChanged);
    unawaited(controller
        .dispose()
        .timeout(const Duration(seconds: 2))
        .catchError((Object error) {
      debugPrint('ChatCameraPreview: dispose pending/failed: $error');
    }));
  }

  void _finish(VoidCallback callback) {
    if (_closing) return;
    setState(() {
      _closing = true;
    });
    _releaseController();
    callback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _active;
    _active = state == AppLifecycleState.resumed;
    if (!_active) _firstPlaybackTimer?.cancel();
    // video_player itself pauses on backgrounding. Do not run a polling loop
    // which interprets that pause as completion and starts the video again.
    final controller = _controller;
    if (_active &&
        !wasActive &&
        !_loading &&
        controller != null &&
        _owns(controller)) {
      unawaited(_play(controller));
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final duration = '${(_durationSeconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(_durationSeconds % 60).toString().padLeft(2, '0')}';
    final size = controller != null && controller.value.isInitialized
        ? controller.value.size
        : Size.zero;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    Widget preview;
    if (_loading) {
      preview = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (controller != null &&
        controller.value.isInitialized &&
        !_closing &&
        size.width > 0 &&
        size.height > 0) {
      preview = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      );
    } else {
      preview = Center(
        child: Text(
          TIM_t('视频预览暂不可用，可直接发送'),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: preview),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('video-preview-close'),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => _finish(widget.onCancel),
                      ),
                      Expanded(
                        child: Text(
                          TIM_t('预览'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 18 + bottomPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$duration  ${widget.sizeText}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('video-preview-retake'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                              onPressed: () => _finish(widget.canRetake
                                  ? widget.onRetake
                                  : widget.onCancel),
                              child: Text(
                                  widget.canRetake ? TIM_t('重拍') : TIM_t('删除')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              key: const ValueKey('video-preview-send'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                              onPressed: () => _finish(
                                  () => widget.onSend(_durationSeconds)),
                              child: Text(TIM_t('发送')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
