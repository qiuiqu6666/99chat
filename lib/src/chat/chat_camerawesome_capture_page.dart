import 'dart:async';
import 'dart:math' as math;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';

class ChatCamerAwesomeCaptureResult {
  final String? imagePath;
  final String? videoPath;
  final int? durationSeconds;

  const ChatCamerAwesomeCaptureResult.image(String path)
      : imagePath = path,
        videoPath = null,
        durationSeconds = null;

  const ChatCamerAwesomeCaptureResult.video(String path, this.durationSeconds)
      : imagePath = null,
        videoPath = path;
}

/// 聊天拍摄：进页即绑定 Preview + ImageCapture + VideoCapture。
/// 轻点拍照、长按录像，底层不再在 Photo / Video 模式之间切换。
class ChatCamerAwesomeCapturePage extends StatefulWidget {
  const ChatCamerAwesomeCapturePage({super.key});

  static const Duration maxRecordDuration = Duration(seconds: 60);
  static const Duration longPressToRecord = Duration(milliseconds: 280);
  static const Duration minRecordDuration = Duration(milliseconds: 700);

  @override
  State<ChatCamerAwesomeCapturePage> createState() =>
      _ChatCamerAwesomeCapturePageState();
}

class _ChatCamerAwesomeCapturePageState
    extends State<ChatCamerAwesomeCapturePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _recordProgress;
  VideoRecordingCameraState? _recordingState;
  CameraState? _latestState;
  DateTime? _recordStartedAt;
  Timer? _longPressTimer;
  int? _activePointer;
  bool _fingerDown = false;
  bool _recordArmed = false;
  bool _popped = false;
  bool _takingPhoto = false;

  @override
  void initState() {
    super.initState();
    _recordProgress = AnimationController(
      vsync: this,
      duration: ChatCamerAwesomeCapturePage.maxRecordDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final stop = _recordingState?.stopRecording();
          if (stop != null) {
            unawaited(stop);
          }
        }
      });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _recordProgress.dispose();
    super.dispose();
  }

  void _syncRecording(CameraState state) {
    _latestState = state;
    final recording = state is VideoRecordingCameraState ? state : null;
    if (recording != null) {
      _recordingState = recording;
      if (!_recordProgress.isAnimating && _recordProgress.value == 0) {
        _recordStartedAt = DateTime.now();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _recordingState == null) {
            return;
          }
          if (!_recordProgress.isAnimating && _recordProgress.value == 0) {
            _recordProgress.forward(from: 0);
          }
        });
      }
      if (!_fingerDown && !_popped) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _fingerDown || _popped) {
            return;
          }
          final current = _latestState;
          if (current is VideoRecordingCameraState) {
            unawaited(current.stopRecording());
          }
        });
      }
      return;
    }
    if (_recordingState != null) {
      _recordingState = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _recordingState != null) {
          return;
        }
        _recordProgress
          ..stop()
          ..reset();
      });
    }
  }

  void _onShutterDown(int pointer, CameraState state) {
    if (_popped ||
        _takingPhoto ||
        _activePointer != null ||
        state is PreparingCameraState) {
      return;
    }
    _activePointer = pointer;
    _fingerDown = true;
    _recordArmed = false;
    HapticFeedback.selectionClick();
    _longPressTimer?.cancel();
    _longPressTimer = Timer(ChatCamerAwesomeCapturePage.longPressToRecord, () {
      if (!mounted || !_fingerDown || _popped) {
        return;
      }
      _recordArmed = true;
      HapticFeedback.mediumImpact();
      final current = _latestState ?? state;
      if (current is VideoCameraState) {
        unawaited(current.startRecording());
      }
    });
  }

  void _onShutterUp(int pointer, CameraState state) {
    if (_activePointer != pointer) {
      return;
    }
    _activePointer = null;
    _fingerDown = false;
    final armed = _recordArmed || _recordingState != null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    final current = _latestState ?? state;
    if (current is VideoRecordingCameraState) {
      unawaited(current.stopRecording());
      return;
    }
    if (armed) {
      _recordArmed = false;
      return;
    }
    unawaited(_takeStill(current));
  }

  Future<void> _takeStill(CameraState state) async {
    if (_popped || _takingPhoto || state is VideoRecordingCameraState) {
      return;
    }
    if (state is PhotoCameraState) {
      _takingPhoto = true;
      try {
        await state.takePhoto();
      } finally {
        _takingPhoto = false;
      }
      return;
    }
    if (state is! VideoCameraState) {
      return;
    }
    final builder = state.saveConfig?.photoPathBuilder;
    if (builder == null) {
      return;
    }
    _takingPhoto = true;
    try {
      final request =
          await builder(state.sensorConfig.sensors.nonNulls.toList());
      final ok = await CamerawesomePlugin.takePhoto(request);
      if (!mounted || _popped) {
        return;
      }
      if (!ok) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(TIM_t('拍摄失败'))),
        );
        return;
      }
      final path = request.path?.trim() ?? '';
      if (path.isEmpty) {
        return;
      }
      _popped = true;
      Navigator.of(context).pop(ChatCamerAwesomeCaptureResult.image(path));
    } catch (_) {
      if (!mounted || _popped) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(TIM_t('拍摄失败'))),
      );
    } finally {
      _takingPhoto = false;
    }
  }

  int _recordedSeconds() {
    final started = _recordStartedAt;
    if (started == null) {
      return 1;
    }
    final seconds =
        (DateTime.now().difference(started).inMilliseconds / 1000).ceil();
    return seconds.clamp(1, 60);
  }

  bool _isTooShortVideo() {
    final started = _recordStartedAt;
    if (started == null) {
      return true;
    }
    return DateTime.now().difference(started) <
        ChatCamerAwesomeCapturePage.minRecordDuration;
  }

  void _onMediaCaptureEvent(MediaCapture event) {
    if (!mounted || _popped) {
      return;
    }
    if (event.status == MediaCaptureStatus.failure) {
      final message = event.exception?.toString() ?? TIM_t('拍摄失败');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    if (event.status != MediaCaptureStatus.success) {
      return;
    }
    if (event.isPicture) {
      return;
    }
    final path = event.captureRequest.path?.trim() ?? '';
    if (path.isEmpty) {
      return;
    }
    if (_isTooShortVideo()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(TIM_t('录像时间太短'))),
      );
      return;
    }
    _popped = true;
    Navigator.of(context).pop(
      ChatCamerAwesomeCaptureResult.video(path, _recordedSeconds()),
    );
  }

  Widget _overlay(CameraState state) {
    final recording = state is VideoRecordingCameraState;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                  if (!recording)
                    AwesomeFlashButton(state: state)
                  else
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
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (recording)
                  _ChatCamerAwesomeRecordBadge(progress: _recordProgress)
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      TIM_t('轻点拍照，长按录像'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      recording
                          ? const SizedBox(width: 48)
                          : AwesomeCameraSwitchButton(state: state),
                      _ChatCamerAwesomeShutter(
                        state: state,
                        progress: _recordProgress,
                        onPointerDown: (pointer) =>
                            _onShutterDown(pointer, state),
                        onPointerUp: (pointer) => _onShutterUp(pointer, state),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: CameraAwesomeBuilder.custom(
          saveConfig: SaveConfig.photoAndVideo(
            initialCaptureMode: CaptureMode.video,
            exifPreferences: ExifPreferences(saveGPSLocation: false),
            mirrorFrontCamera: true,
          ),
          sensorConfig: SensorConfig.single(
            sensor: Sensor.position(SensorPosition.back),
            aspectRatio: CameraAspectRatios.ratio_16_9,
          ),
          previewFit: CameraPreviewFit.cover,
          filters: const <AwesomeFilter>[],
          onMediaCaptureEvent: _onMediaCaptureEvent,
          progressIndicator: const ColoredBox(color: Colors.black),
          builder: (state, preview) {
            _syncRecording(state);
            return _overlay(state);
          },
        ),
      ),
    );
  }
}

class _ChatCamerAwesomeRecordBadge extends StatelessWidget {
  const _ChatCamerAwesomeRecordBadge({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final remaining = (60 * (1 - progress.value)).ceil().clamp(0, 60);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '剩余 $remaining 秒',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatCamerAwesomeShutter extends StatefulWidget {
  const _ChatCamerAwesomeShutter({
    required this.state,
    required this.progress,
    required this.onPointerDown,
    required this.onPointerUp,
  });

  final CameraState state;
  final Animation<double> progress;
  final ValueChanged<int> onPointerDown;
  final ValueChanged<int> onPointerUp;

  @override
  State<_ChatCamerAwesomeShutter> createState() =>
      _ChatCamerAwesomeShutterState();
}

class _ChatCamerAwesomeShutterState extends State<_ChatCamerAwesomeShutter> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.state is VideoRecordingCameraState;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _setPressed(true);
        widget.onPointerDown(event.pointer);
      },
      onPointerUp: (event) {
        _setPressed(false);
        widget.onPointerUp(event.pointer);
      },
      onPointerCancel: (event) {
        _setPressed(false);
        widget.onPointerUp(event.pointer);
      },
      child: AnimatedBuilder(
        animation: widget.progress,
        builder: (context, child) {
          return SizedBox(
            width: 92,
            height: 92,
            child: CustomPaint(
              painter: _RecordProgressRingPainter(
                progress: recording ? widget.progress.value : 0,
              ),
              child: child,
            ),
          );
        },
        child: Center(
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1,
            duration: const Duration(milliseconds: 100),
            child: CustomPaint(
              size: const Size(80, 80),
              painter: recording
                  ? const _ShutterButtonPainter(recording: true)
                  : const _ShutterButtonPainter(recording: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButtonPainter extends CustomPainter {
  const _ShutterButtonPainter({required this.recording});

  final bool recording;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPainter = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    bgPainter.color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, bgPainter);
    if (recording) {
      bgPainter.color = const Color(0xFFE53935);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(17, 17, size.width - 34, size.height - 34),
          const Radius.circular(12),
        ),
        bgPainter,
      );
      return;
    }
    bgPainter.color = Colors.white;
    canvas.drawCircle(center, radius - 8, bgPainter);
  }

  @override
  bool shouldRepaint(covariant _ShutterButtonPainter oldDelegate) {
    return oldDelegate.recording != recording;
  }
}

class _RecordProgressRingPainter extends CustomPainter {
  _RecordProgressRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) {
      return;
    }
    final fill = Paint()
      ..color = const Color(0xFF07C160)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RecordProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
