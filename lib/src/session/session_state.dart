import 'package:flutter/foundation.dart';

enum SessionInvalidationReason { kickedOffline, credentialsExpired }

enum SessionPhase {
  unknown,
  restoring,
  authenticating,
  initializingIm,
  connectingIm,
  ready,
  loggedOut,
  expired,
  temporarilyUnavailable,
  offline,
}

@immutable
class SessionState {
  const SessionState({
    required this.phase,
    this.userId,
    this.error,
  });

  const SessionState.unknown() : this(phase: SessionPhase.unknown);

  final SessionPhase phase;
  final String? userId;
  final Object? error;

  bool get isReady => phase == SessionPhase.ready;
  bool get isLoggedOut => phase == SessionPhase.loggedOut;

  SessionState copyWith({
    SessionPhase? phase,
    String? userId,
    Object? error,
    bool clearError = false,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      userId: userId ?? this.userId,
      error: clearError ? null : error ?? this.error,
    );
  }
}
