import 'dart:async';
import 'package:flutter/foundation.dart';

/// Optional entry caches can load after the application frame. Consumers keep
/// entries hidden until this shared task has established visibility/position.
class StartupEntryPreferences {
  StartupEntryPreferences._();
  static final ValueNotifier<bool> readiness = ValueNotifier(true);
  static Future<void> Function()? _loader;
  static Future<void>? _pending;
  static bool get isReady => readiness.value;

  static void configure(Future<void> Function() loader) {
    _loader = loader;
    _pending = null;
    readiness.value = false;
  }

  static Future<void> ensureReady() {
    if (isReady) return Future<void>.value();
    final active = _pending;
    if (active != null) return active;
    final loader = _loader!;
    late final Future<void> operation;
    operation = Future<void>.sync(loader).then((_) {
      if (identical(_loader, loader)) readiness.value = true;
    }).whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
    _pending = operation;
    return operation;
  }
}
