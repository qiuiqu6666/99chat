import 'dart:math';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

/// A deadline shared by all callers, so urgent refreshes cannot bypass backoff.
class RequestRetryBackoff {
  RequestRetryBackoff({Random? random}) : _random = random ?? Random();
  final Random _random;
  int _failures = 0;
  DateTime? _notBefore;

  Duration remaining(DateTime now) {
    final delay = _notBefore?.difference(now) ?? Duration.zero;
    return delay.isNegative ? Duration.zero : delay;
  }

  bool failed(Object error, DateTime now) {
    _failures = min(_failures + 1, 6);
    final status = error is DioError ? error.response?.statusCode : null;
    final retryable =
        status == null || status == 408 || status == 429 || status >= 500;
    final baseMs = min(30000, 1000 * (1 << (_failures - 1)));
    var delay =
        Duration(milliseconds: baseMs + _random.nextInt(baseMs ~/ 2 + 1));
    if (!retryable) delay = const Duration(minutes: 1);
    if (error is DioError) {
      final value = error.response?.headers.value('retry-after')?.trim();
      if (value != null) {
        final seconds = int.tryParse(value);
        Duration? requested;
        if (seconds != null && seconds >= 0) {
          requested = Duration(seconds: seconds);
        } else {
          try {
            requested = DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
                .parseUtc(value)
                .difference(now.toUtc());
          } catch (_) {/* Invalid server hint: retain backoff. */}
        }
        if (requested != null && requested > delay) delay = requested;
      }
    }
    _notBefore = now.add(delay);
    return retryable;
  }

  void reset() {
    _failures = 0;
    _notBefore = null;
  }
}
