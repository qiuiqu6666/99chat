import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';

/// Per-feed LRU of conversation rows that Sliver has already placed in the
/// keepAlive bucket. Probe is owned here: one post-frame callback, never
/// one per row.
class ConversationRowRetention {
  ConversationRowRetention({int? limit})
      : limit = limit ?? ConversationPerfFlags.conversationRowRetentionLruLimit;

  final int limit;
  final Set<ConversationRowRetentionClient> mountedHosts =
      <ConversationRowRetentionClient>{};
  final LinkedHashMap<String, ConversationRowRetentionClient> _lru =
      LinkedHashMap<String, ConversationRowRetentionClient>();
  bool _probeScheduled = false;
  bool _disposed = false;
  int evictionCount = 0;

  int get keepAliveCount => _lru.length;
  int get activeRowCount => mountedHosts.length;

  static String conversationKeyHash(String identity) =>
      ConversationPerfGateLog.conversationKeyHash(identity);

  void register(ConversationRowRetentionClient host) {
    mountedHosts.add(host);
    _emit('row_init', host.identity);
    scheduleProbe();
  }

  void unregister(ConversationRowRetentionClient host) {
    mountedHosts.remove(host);
    _lru.remove(host.identity);
    _emit('row_dispose', host.identity);
  }

  void dispose() {
    _disposed = true;
    mountedHosts.clear();
    _lru.clear();
  }

  void scheduleProbe() {
    if (_disposed || _probeScheduled) {
      return;
    }
    if (!ConversationPerfFlags.conversationRowRetentionEnabled) {
      return;
    }
    _probeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeScheduled = false;
      probe();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @visibleForTesting
  void probe() {
    if (_disposed || !ConversationPerfFlags.conversationRowRetentionEnabled) {
      return;
    }
    for (final host in List<ConversationRowRetentionClient>.of(mountedHosts)) {
      if (!host.mounted) {
        continue;
      }
      if (host.isKeptAlive) {
        _tryRetain(host);
      } else if (_lru.remove(host.identity) != null) {
        _emit('row_keepalive_hit', host.identity);
      }
    }
  }

  void _tryRetain(ConversationRowRetentionClient host) {
    final id = host.identity;
    _lru.remove(id);
    while (_lru.length >= limit) {
      final oldestId = _lru.keys.first;
      final oldest = _lru.remove(oldestId)!;
      evictionCount += 1;
      oldest.dropKeepAlive();
      _emit('row_keepalive_evict', oldestId);
    }
    _lru[id] = host;
  }

  void _emit(String event, String identity) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = conversationKeyHash(identity);
    ConversationFeedPerf.recordRowRetention(
      event: event,
      conversationKeyHash: hash,
      timestamp: timestamp,
      activeRowCount: activeRowCount,
      keepAliveCount: keepAliveCount,
    );
    ConversationPerfGateLog.log(
      event,
      extras: <String, Object?>{
        'conversationKeyHash': hash,
        'timestamp': timestamp,
        'activeRowCount': activeRowCount,
        'keepAliveCount': keepAliveCount,
      },
    );
  }
}

abstract class ConversationRowRetentionClient {
  String get identity;
  bool get mounted;
  bool get isKeptAlive;
  void dropKeepAlive();
}

class ConversationRowRetentionHost extends StatefulWidget {
  const ConversationRowRetentionHost({
    super.key,
    required this.identity,
    required this.retention,
    required this.child,
  });

  final String identity;
  final ConversationRowRetention retention;
  final Widget child;

  @override
  State<ConversationRowRetentionHost> createState() =>
      ConversationRowRetentionHostState();
}

class ConversationRowRetentionHostState
    extends State<ConversationRowRetentionHost>
    with AutomaticKeepAliveClientMixin
    implements ConversationRowRetentionClient {
  bool _armed = true;

  @override
  String get identity => widget.identity;

  @override
  bool get wantKeepAlive =>
      _armed && ConversationPerfFlags.conversationRowRetentionEnabled;

  @override
  bool get isKeptAlive {
    RenderObject? node = context.findRenderObject();
    while (node != null) {
      final parentData = node.parentData;
      if (parentData is KeepAliveParentDataMixin) {
        return parentData.keptAlive;
      }
      node = node.parent;
    }
    return false;
  }

  @override
  void dropKeepAlive() {
    if (!_armed) {
      return;
    }
    _armed = false;
    if (mounted) {
      updateKeepAlive();
    }
  }

  @override
  void initState() {
    super.initState();
    _armed = ConversationPerfFlags.conversationRowRetentionEnabled;
    widget.retention.register(this);
  }

  @override
  void didUpdateWidget(covariant ConversationRowRetentionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!ConversationPerfFlags.conversationRowRetentionEnabled && _armed) {
      dropKeepAlive();
    }
  }

  @override
  void dispose() {
    widget.retention.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
