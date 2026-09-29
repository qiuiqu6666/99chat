import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_history_peer.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

class ChatCoverageRepairScheduler {
  ChatCoverageRepairScheduler._();
  static final instance = ChatCoverageRepairScheduler._();
  static const _count = 20;
  static const _maxCandidates = 8;
  bool _running = false;
  bool _paused = false;
  int _generation = 0;
  Timer? _timer;
  final Set<String> _repairedThisSession = <String>{};

  void pause({String reason = 'user_activity'}) {
    _paused = true;
    _generation++;
    _timer?.cancel();
    ChatHistoryTrace.log('coverage_repair_pause', extras: {'reason': reason});
  }

  void resume() {
    _paused = false;
    _generation++;
    ChatHistoryTrace.log('coverage_repair_resume',
        extras: {'reason': 'home_visible', 'generation': _generation});
  }

  void schedule(
    List<V2TimConversation> visible, {
    String reason = 'home_idle',
    List<V2TimConversation> Function()? currentVisible,
  }) {
    if (_running || _paused || visible.isEmpty) return;
    final generation = ++_generation;
    final snapshotCount = visible.length;
    _timer?.cancel();
    ChatHistoryTrace.log('coverage_repair_scheduled', extras: {
      'generation': generation,
      'snapshotCandidateCount': snapshotCount,
      'delayMs': 1500,
      'reason': reason,
    });
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (_paused || generation != _generation) {
        ChatHistoryTrace.log('coverage_repair_cancelled', extras: {
          'reason': _paused ? 'paused' : 'generation_changed',
          'scheduledGeneration': generation,
          'currentGeneration': _generation,
        });
        return;
      }
      final fresh = currentVisible?.call() ?? visible;
      final candidates = fresh.take(_maxCandidates).toList(growable: false);
      ChatHistoryTrace.log('coverage_repair_fresh_candidates', extras: {
        'generation': generation,
        'freshCandidateCount': candidates.length,
      });
      unawaited(_run(candidates, generation, reason));
    });
  }

  Future<void> _run(List<V2TimConversation> candidates, int generation, String reason) async {
    if (_running || _paused || generation != _generation) {
      ChatHistoryTrace.log('coverage_repair_cancelled', extras: {
        'reason': _paused ? 'paused' : 'stale_generation',
      });
      return;
    }
    _running = true;
    ChatHistoryTrace.log('coverage_repair_start', extras: {'reason': reason, 'count': candidates.length});
    try {
      for (final conversation in candidates) {
        if (_paused || generation != _generation) break;
        if (!MessagePersistCoordinator.instance.shouldProduceBackground) {
          ChatHistoryTrace.log('coverage_repair_backpressure', extras: {
            'queueDepth': MessagePersistCoordinator.instance.queueDepth,
            'realtimeBacklog':
                MessagePersistCoordinator.instance.hasRealtimeBacklog,
          });
          break;
        }
        await _repairOne(conversation, generation);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    } finally {
      _running = false;
      ChatHistoryTrace.log('coverage_repair_finish');
    }
  }

  Future<void> _repairOne(V2TimConversation conversation, int generation) async {
    final key = conversation.conversationID.trim();
    if (_repairedThisSession.contains(key)) {
      ChatHistoryTrace.log('coverage_repair_skip', conversationID: key,
          extras: {'reason': 'already_repaired_this_session'});
      return;
    }
    final peer = ConversationHistoryPeer.resolve(conversation);
    if (peer == null || !peer.canFetch) return;
    final local = await serviceLocator<MessageService>().getHistoryMessageListWithComplete(
      count: _count,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      userID: peer.isGroup ? null : peer.userID,
      groupID: peer.isGroup ? peer.groupID : null,
    );
    final localCount = local?.messageList.length ?? 0;
    ChatHistoryTrace.log('coverage_repair_local_check', conversationID: conversation.conversationID,
        extras: {'localCount': localCount, 'finished': local?.isFinished});
    if (_paused || generation != _generation) return;
    if (localCount >= _count || local?.isFinished != true || !_mayNeed(conversation, localCount)) return;
    ChatHistoryTrace.log('coverage_repair_cloud_start', conversationID: conversation.conversationID);
    final cloud = await serviceLocator<MessageService>().getHistoryMessageListWithComplete(
      count: _count,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      userID: peer.isGroup ? null : peer.userID,
      groupID: peer.isGroup ? peer.groupID : null,
    );
    ChatHistoryTrace.log('coverage_repair_cloud_done', conversationID: key,
        extras: {'cloudCount': cloud?.messageList.length ?? 0, 'discarded': true});
    _repairedThisSession.add(key);
  }

  bool _mayNeed(V2TimConversation conversation, int localCount) {
    if (localCount > 3) return true;
    final ts = conversation.lastMessage?.timestamp;
    if (ts == null || ts <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch - ts * 1000 >= const Duration(minutes: 10).inMilliseconds;
  }
}
