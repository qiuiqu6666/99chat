import 'dart:math' as math;
import 'package:flutter/animation.dart';

/// A single, monotone motion that carries velocity across live insertions.
/// The deadline belongs to the latest target, never to the first row in a burst.
class ChatViewportMotion {
  static const maxDuration = Duration(milliseconds: 350);
  static const Curve curve = _ChatInsertCurve();
  Duration _segmentStart = Duration.zero;
  Duration _deadline = Duration.zero;
  double _previousProgress = 0;
  double _distance = 0;
  double _initialSlope = 0;

  static Duration durationFor(
      {required bool outgoing, required double extent}) {
    final extra = ((extent - 96) / 6).clamp(0.0, 60.0).round();
    return Duration(milliseconds: (outgoing ? 240 : 260) + extra);
  }

  void retarget(Duration elapsed,
      {required bool outgoing, double distance = 1, bool restart = false}) {
    final velocity = restart ? 0.0 : _velocityAt(elapsed);
    _segmentStart = elapsed;
    _distance = math.max(0.0, distance);
    final duration = durationFor(outgoing: outgoing, extent: _distance);
    _deadline = elapsed + duration;
    // A cubic Hermite segment ends at rest. Limiting its starting slope to 3
    // keeps it monotone even if a geometry correction shortened the distance.
    _initialSlope = _distance <= 0
        ? 0
        : (velocity * duration.inMicroseconds / 1000000 / _distance)
            .clamp(0.0, 3.0);
    _previousProgress = 0;
  }

  double _velocityAt(Duration elapsed) {
    final span = (_deadline - _segmentStart).inMicroseconds;
    if (span <= 0 || elapsed >= _deadline) return 0;
    final t = ((elapsed - _segmentStart).inMicroseconds / span).clamp(0.0, 1.0);
    final slope = 6 * t * (1 - t) + _initialSlope * (3 * t * t - 4 * t + 1);
    return math.max(0.0, _distance * slope * 1000000 / span);
  }

  /// Fraction of the *current* remaining distance to consume this frame.
  /// Absolute ticker time keeps the result independent of refresh rate.
  double consumeFraction(Duration elapsed, {bool disableAnimations = false}) {
    if (disableAnimations || elapsed >= _deadline) {
      _distance = 0;
      _previousProgress = 1;
      return 1;
    }
    final span = (_deadline - _segmentStart).inMicroseconds;
    if (span <= 0 || _previousProgress >= 1) return 1;
    final t = ((elapsed - _segmentStart).inMicroseconds / span).clamp(0.0, 1.0);
    final progress =
        (t * t * (3 - 2 * t) + _initialSlope * t * (1 - t) * (1 - t))
            .clamp(_previousProgress, 1.0);
    final fraction = (progress - _previousProgress) / (1 - _previousProgress);
    _previousProgress = progress;
    return fraction.clamp(0.0, 1.0);
  }

  /// Skip intermediate screens in a burst; retain only one screen of motion.
  static double correction(double distance, double inserted, double viewport) {
    if (viewport <= 0) return inserted;
    return math.min(distance + inserted, viewport) - distance;
  }
}

class _ChatInsertCurve extends Curve {
  const _ChatInsertCurve();

  @override
  double transformInternal(double t) => t * t * (3 - 2 * t);
}
