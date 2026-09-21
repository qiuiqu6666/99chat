/// Select a populated address rather than allowing an old empty value to mask
/// metadata delivered after a realtime message was first rendered.
String? firstVoicePlaybackSource(Iterable<String?> candidates) {
  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

Future<String?> waitForVoicePlaybackSource({
  required String? Function() localSource,
  required String? Function() remoteSource,
  required Future<String?> Function() prepareLocal,
  Duration timeout = const Duration(seconds: 9),
}) async {
  final existing = localSource();
  if (existing != null) return existing;
  try {
    final prepared = await prepareLocal().timeout(timeout);
    if (prepared != null && prepared.isNotEmpty) return prepared;
  } catch (_) {
    // Download failure must still allow a newly populated remote URL to play.
  }
  return localSource() ?? remoteSource();
}
