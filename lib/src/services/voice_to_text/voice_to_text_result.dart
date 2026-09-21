class VoiceToTextResult {
  const VoiceToTextResult({
    this.text,
    this.errorMessage,
    this.isCancelled = false,
  });

  final String? text;
  final String? errorMessage;
  final bool isCancelled;

  bool get isSuccess => text != null && text!.trim().isNotEmpty;
}
