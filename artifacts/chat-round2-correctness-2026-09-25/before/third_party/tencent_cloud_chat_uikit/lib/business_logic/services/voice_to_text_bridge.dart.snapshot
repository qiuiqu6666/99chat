import 'dart:async';

typedef VoiceToTextTranscriber = Future<String?> Function({
  String? localAudioPath,
  String? remoteAudioUrl,
});

class VoiceToTextCancellationToken {
  bool _isCancelled = false;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _cancelled.complete();
  }
}

/// App 侧注入语音识别实现（如腾讯 IM convertVoiceToText）。
class VoiceToTextBridge {
  VoiceToTextBridge._();

  static VoiceToTextTranscriber? transcribe;
  static String? lastErrorMessage;

  static void configure({VoiceToTextTranscriber? transcriber}) {
    transcribe = transcriber;
  }
}
