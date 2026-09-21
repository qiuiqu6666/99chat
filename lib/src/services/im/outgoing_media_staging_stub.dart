import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

class OutgoingMediaStageResult {
  const OutgoingMediaStageResult({
    required this.hadLocalMedia,
    required this.rootPath,
    required this.succeeded,
  });

  final bool hadLocalMedia;
  final String? rootPath;
  final bool succeeded;

  bool get shouldBlock => hadLocalMedia && !succeeded;
}

class OutgoingMediaStager {
  OutgoingMediaStager({Object? supportDirectoryProvider});

  static final OutgoingMediaStager instance = OutgoingMediaStager();

  static bool hasLocalMedia(V2TimMessage? message) => false;

  Future<OutgoingMediaStageResult> stageMessage({
    required V2TimMessage? message,
    required String operationId,
  }) async {
    return const OutgoingMediaStageResult(
      hadLocalMedia: false,
      rootPath: null,
      succeeded: true,
    );
  }

  Future<void> cleanup(String? rootPath) async {}

  Future<void> cleanupLiveMessage(V2TimMessage? message) async {}

  Future<void> cleanupOrphans({
    required Iterable<String?> activeRootPaths,
    Duration minimumAge = const Duration(hours: 24),
  }) async {}

  Future<void> cleanupLiveOrphans({
    Duration minimumAge = const Duration(days: 2),
  }) async {}
}
