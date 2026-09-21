import 'dart:developer' as developer;

class PerfTimeline {
  PerfTimeline._();

  static void instant(String name, {Map<String, Object?> arguments = const {}}) {
    developer.Timeline.instantSync(name, arguments: arguments);
  }
}
