/// Voice-input recording pipeline states (page-local).
enum RecordInputState {
  idle,
  preparing,
  recording,
  stopping,
  cancelling,
  ready,
  transcribing,
  sendingVoice,
  sendingText,
  cancelled,
  error,
}

extension RecordInputStateRules on RecordInputState {
  bool get canStartRecording => this == RecordInputState.idle;

  bool canTransitionTo(RecordInputState next) {
    if (this == next || next == RecordInputState.error) {
      return true;
    }
    switch (this) {
      case RecordInputState.idle:
        return next == RecordInputState.preparing;
      case RecordInputState.preparing:
        return next == RecordInputState.recording ||
            next == RecordInputState.stopping ||
            next == RecordInputState.cancelling;
      case RecordInputState.recording:
        return next == RecordInputState.stopping ||
            next == RecordInputState.cancelling ||
            next == RecordInputState.ready;
      case RecordInputState.stopping:
        return next == RecordInputState.ready ||
            next == RecordInputState.cancelling;
      case RecordInputState.cancelling:
        return next == RecordInputState.cancelled;
      case RecordInputState.ready:
        return next == RecordInputState.transcribing ||
            next == RecordInputState.sendingVoice ||
            next == RecordInputState.sendingText ||
            next == RecordInputState.cancelling ||
            next == RecordInputState.idle ||
            next == RecordInputState.cancelled;
      case RecordInputState.transcribing:
        return next == RecordInputState.ready ||
            next == RecordInputState.sendingVoice ||
            next == RecordInputState.sendingText ||
            next == RecordInputState.cancelling;
      case RecordInputState.sendingVoice:
      case RecordInputState.sendingText:
      case RecordInputState.cancelled:
      case RecordInputState.error:
        return next == RecordInputState.idle;
    }
  }
}

enum RecordReleaseZone {
  send,
  cancel,
  convertText,
}

enum RecordOverlayMode {
  recording,
  convertReview,
}
