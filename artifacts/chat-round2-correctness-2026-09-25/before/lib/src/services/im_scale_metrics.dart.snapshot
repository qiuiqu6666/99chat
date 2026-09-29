import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';

/// One callback shared by all mounted feed tabs. No periodic timer or IDs logged.
class ImScaleMetrics {
  static int _owners = 0;
  static int _lastSampleMs = 0;
  static void retain() {
    if (!ConversationFeedPerf.isEnabled) return;
    if (_owners++ == 0) WidgetsBinding.instance.addTimingsCallback(_onFrames);
  }

  static void release() {
    if (_owners == 0) return;
    if (--_owners == 0)
      WidgetsBinding.instance.removeTimingsCallback(_onFrames);
  }

  static void _onFrames(List<FrameTiming> frames) {
    for (final frame in frames) {
      final build = frame.buildDuration.inMicroseconds;
      final raster = frame.rasterDuration.inMicroseconds;
      ConversationFeedPerf.recordDurationMicros('frame_build', build);
      ConversationFeedPerf.recordDurationMicros('frame_raster', raster);
      ConversationFeedPerf.increment('frame_count');
      if (build > 16667 || raster > 16667)
        ConversationFeedPerf.increment('frame_over_60hz_budget');
      if (build > 8333 || raster > 8333)
        ConversationFeedPerf.increment('frame_over_120hz_budget');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSampleMs < 1000) return;
    _lastSampleMs = now;
    final members = GroupMemberStore.instance;
    final profiles = UserProfileLocalService.instance;
    final writer = MessagePersistCoordinator.instance;
    ConversationFeedPerf.gauge('group_cache_groups', members.cachedGroupCount);
    ConversationFeedPerf.gauge(
        'group_cache_members', members.cachedMemberCount);
    ConversationFeedPerf.gauge(
        'avatar_live_handles', members.avatarSubscriptionCount);
    ConversationFeedPerf.gauge(
        'avatar_dormant_handles', members.dormantAvatarCount);
    ConversationFeedPerf.gauge(
        'profile_cache_rows', profiles.cachedProfileCount);
    ConversationFeedPerf.gauge(
        'profile_cache_evictions', profiles.profileCacheEvictions);
    ConversationFeedPerf.gauge('persist_queue_depth', writer.queueDepth);
    ConversationFeedPerf.gauge(
        'persist_waiting_admissions', writer.waitingAdmissions);
  }
}
