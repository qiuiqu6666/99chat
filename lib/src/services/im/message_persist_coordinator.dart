import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Persist queue priority. One coordinator, one SQLite writer.
enum MessagePersistPriority {
  realtime,
  userHistory,
  backgroundRepair,
}

enum MessagePersistSource {
  realtime,
  userHistory,
  backgroundRepair,
}

enum MessagePersistAuthorityKind {
  revoke,
  delete,
  sendState,
  edit,
  read,
}

class MessagePersistRejected implements Exception {
  const MessagePersistRejected(this.reason);
  final String reason;
  @override
  String toString() => 'MessagePersistRejected($reason)';
}

class MessagePersistMetrics {
  const MessagePersistMetrics({
    required this.source,
    required this.queueWaitUs,
    required this.prepareCpuUs,
    required this.txnWaitUs,
    required this.txnUs,
    required this.publishUs,
    required this.batchSize,
    required this.queueDepth,
  });

  final MessagePersistSource source;
  final int queueWaitUs;
  final int prepareCpuUs;
  final int txnWaitUs;
  final int txnUs;
  final int publishUs;
  final int batchSize;
  final int queueDepth;
}

class MessagePersistJob<T> {
  MessagePersistJob({
    required this.priority,
    required this.source,
    required this.conversationId,
    required this.accountGeneration,
    required this.itemCount,
    required this.run,
    this.messageIds = const <String>[],
    this.authorityKind,
    this.allowProjection = true,
    this.prepare,
    this.publish,
  });

  final MessagePersistPriority priority;
  final MessagePersistSource source;
  final String conversationId;
  final int accountGeneration;
  final int itemCount;
  final List<String> messageIds;
  final MessagePersistAuthorityKind? authorityKind;
  final bool allowProjection;
  final Future<void> Function()? prepare;
  final Future<T> Function() run;
  final Future<void> Function(T value)? publish;
  final Completer<T> completer = Completer<T>();
  final int enqueuedAtUs = DateTime.now().microsecondsSinceEpoch;
}

/// Single serialized persist coordinator.
///
/// Preemption happens between small transactions, never inside one.
class MessagePersistCoordinator {
  static const Object _nestedRunZoneKey = #messagePersistNestedRun;

  MessagePersistCoordinator({
    this.historyChunkSize = 80,
    this.realtimeCoalesceLimit = 8,
    this.backgroundQueueSoftLimit = 32,
    this.backgroundQueueHardLimit = 128,
    this.foregroundQueueLimit = 128,
    this.authorityCacheLimit = 4096,
  }) : assert(foregroundQueueLimit > 0 &&
            authorityCacheLimit > 0 &&
            realtimeCoalesceLimit > 0);

  static final MessagePersistCoordinator instance = MessagePersistCoordinator();

  final int historyChunkSize;
  final int realtimeCoalesceLimit;
  final int backgroundQueueSoftLimit;
  final int backgroundQueueHardLimit;
  final int foregroundQueueLimit;
  final int authorityCacheLimit;
  final _admissionWaiters = <MessagePersistPriority, Queue<Completer<void>>>{};
  final _reservedAdmissions = <MessagePersistPriority, int>{};
  int _waitingAdmissions = 0;
  int get waitingAdmissions => _waitingAdmissions;
  int get authorityCacheSize => _authority.length;

  final Queue<MessagePersistJob<dynamic>> _p0 =
      Queue<MessagePersistJob<dynamic>>();
  final Queue<MessagePersistJob<dynamic>> _p1 =
      Queue<MessagePersistJob<dynamic>>();
  final Queue<MessagePersistJob<dynamic>> _p2 =
      Queue<MessagePersistJob<dynamic>>();

  final Map<String, MessagePersistAuthorityKind> _authority =
      <String, MessagePersistAuthorityKind>{};

  int _accountGeneration = 0;
  bool _pumping = false;
  bool _txnInFlight = false;
  int _executeDepth = 0;
  MessagePersistPriority? _executingPriority;
  String? _activeChatConversationId;
  final List<MessagePersistMetrics> _metrics = <MessagePersistMetrics>[];

  int get accountGeneration => _accountGeneration;
  bool get txnInFlight => _txnInFlight;
  bool get hasRealtimeBacklog =>
      _p0.isNotEmpty || _executingPriority == MessagePersistPriority.realtime;
  int get queueDepth => _p0.length + _p1.length + _p2.length;
  int get realtimeQueueDepth => _p0.length;
  int get userHistoryQueueDepth => _p1.length;
  int get backgroundQueueDepth => _p2.length;
  bool get shouldProduceBackground =>
      !hasRealtimeBacklog && queueDepth < backgroundQueueSoftLimit;
  String? get activeChatConversationId => _activeChatConversationId;

  List<MessagePersistMetrics> get metricsSnapshot =>
      List<MessagePersistMetrics>.unmodifiable(_metrics);

  @visibleForTesting
  void resetForTest() {
    _p0.clear();
    _p1.clear();
    _p2.clear();
    _authority.clear();
    _metrics.clear();
    _accountGeneration = 0;
    _pumping = false;
    _txnInFlight = false;
    _executeDepth = 0;
    _executingPriority = null;
    _activeChatConversationId = null;
  }

  void bindAccountGeneration(int generation) {
    _accountGeneration = generation;
    _rejectStale(_p0);
    _rejectStale(_p1);
    _rejectStale(_p2);
    _authority.clear();
    _wakeAdmissions();
  }

  void setActiveChatConversationId(String? conversationId) {
    final next = conversationId?.trim() ?? '';
    _activeChatConversationId = next.isEmpty ? null : next;
  }

  void rememberAuthority({
    required String conversationId,
    required String messageId,
    required MessagePersistAuthorityKind kind,
  }) {
    final key = _authorityKey(conversationId, messageId);
    if (key.isEmpty) return;
    final previous = _authority[key];
    if (previous == null || _authorityRank(kind) >= _authorityRank(previous)) {
      _authority.remove(key);
      _authority[key] = kind;
    }
    while (_authority.length > authorityCacheLimit) {
      _authority.remove(_authority.keys.first);
    }
  }

  bool isStaleHistoryWrite({
    required String conversationId,
    required String messageId,
  }) {
    return authorityFor(
          conversationId: conversationId,
          messageId: messageId,
        ) !=
        null;
  }

  MessagePersistAuthorityKind? authorityFor({
    required String conversationId,
    required String messageId,
  }) {
    final key = _authorityKey(conversationId, messageId);
    if (key.isEmpty) return null;
    return _authority[key];
  }

  bool shouldProjectConversation(String conversationId) {
    return _shouldProject(conversationId);
  }

  Future<T> enqueue<T>({
    required MessagePersistPriority priority,
    required MessagePersistSource source,
    required Future<T> Function() run,
    String conversationId = '',
    int accountGeneration = 0,
    int itemCount = 1,
    List<String> messageIds = const <String>[],
    MessagePersistAuthorityKind? authorityKind,
    bool? allowProjection,
    Future<void> Function()? prepare,
    Future<void> Function(T value)? publish,
  }) async {
    final admittedGeneration =
        accountGeneration == 0 ? _accountGeneration : accountGeneration;
    if (accountGeneration != 0 &&
        _accountGeneration != 0 &&
        accountGeneration != _accountGeneration) {
      return Future<T>.error(
        const MessagePersistRejected('stale_account_generation'),
      );
    }
    if (Zone.current[_nestedRunZoneKey] == true) {
      return run();
    }
    // Await capacity before constructing a queued job. Producers that await
    // enqueue naturally slow down; accepted durable work is never discarded.
    if (priority != MessagePersistPriority.backgroundRepair &&
        ((_admissionWaiters[priority]?.isNotEmpty ?? false) ||
            _queueFor(priority).length + (_reservedAdmissions[priority] ?? 0) >=
                foregroundQueueLimit)) {
      final available = Completer<void>();
      (_admissionWaiters[priority] ??= Queue<Completer<void>>()).add(available);
      _waitingAdmissions++;
      _wakeAdmissions();
      try {
        await available.future;
      } finally {
        _waitingAdmissions--;
        _reservedAdmissions[priority] =
            (_reservedAdmissions[priority] ?? 1) - 1;
      }
      if (admittedGeneration != 0 &&
          _accountGeneration != 0 &&
          admittedGeneration != _accountGeneration) {
        _wakeAdmissions();
        throw const MessagePersistRejected('stale_account_generation');
      }
    }
    if (priority == MessagePersistPriority.backgroundRepair &&
        !shouldProduceBackground &&
        source == MessagePersistSource.backgroundRepair) {
      // Already-accepted durable work is still queued. Callers that are
      // *producing* new background batches should check [shouldProduceBackground]
      // before creating more jobs.
    }
    if (priority == MessagePersistPriority.backgroundRepair &&
        _p2.length >= backgroundQueueHardLimit) {
      return Future<T>.error(
        const MessagePersistRejected('background_backpressure'),
      );
    }
    final job = MessagePersistJob<T>(
      priority: priority,
      source: source,
      conversationId: conversationId.trim(),
      accountGeneration: admittedGeneration,
      itemCount: itemCount < 1 ? 1 : itemCount,
      messageIds: messageIds,
      authorityKind: authorityKind,
      allowProjection: allowProjection ?? _shouldProject(conversationId),
      prepare: prepare,
      run: run,
      publish: publish,
    );
    _queueFor(priority).add(job);
    unawaited(_pump());
    return job.completer.future;
  }

  /// Split a large history persist into small transactions that can yield to P0.
  Future<void> enqueueHistoryChunks({
    required MessagePersistPriority priority,
    required MessagePersistSource source,
    required List<Future<void> Function()> chunks,
    String conversationId = '',
    int accountGeneration = 0,
    int itemsPerChunk = 0,
  }) async {
    if (chunks.isEmpty) return;
    final generation = accountGeneration == 0
        ? _accountGeneration : accountGeneration;
    for (final chunk in chunks) {
      await enqueue<void>(
        priority: priority,
        source: source,
        conversationId: conversationId,
        accountGeneration: generation,
        itemCount: itemsPerChunk > 0 ? itemsPerChunk : historyChunkSize,
        run: chunk,
      );
    }
  }

  static List<List<E>> splitChunks<E>(List<E> items, int chunkSize) {
    final size = chunkSize < 1 ? 1 : chunkSize;
    if (items.isEmpty) return const [];
    final out = <List<E>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = i + size > items.length ? items.length : i + size;
      out.add(items.sublist(i, end));
    }
    return out;
  }

  Queue<MessagePersistJob<dynamic>> _queueFor(MessagePersistPriority priority) {
    return switch (priority) {
      MessagePersistPriority.realtime => _p0,
      MessagePersistPriority.userHistory => _p1,
      MessagePersistPriority.backgroundRepair => _p2,
    };
  }

  MessagePersistJob<dynamic>? _takeNext() {
    if (_p0.isNotEmpty) return _p0.removeFirst();
    if (_p1.isNotEmpty) return _p1.removeFirst();
    if (_p2.isNotEmpty) return _p2.removeFirst();
    return null;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    var completed = 0;
    final slice = Stopwatch()..start();
    try {
      while (true) {
        final job = _takeNext();
        if (job == null) return;
        _wakeAdmissions();
        await _execute(job);
        if (++completed >= realtimeCoalesceLimit ||
            slice.elapsedMilliseconds >= 4) {
          await Future<void>.delayed(Duration.zero);
          completed = 0;
          slice.reset();
        }
      }
    } finally {
      _pumping = false;
      if (queueDepth > 0) {
        unawaited(_pump());
      }
    }
  }

  void _wakeAdmissions() {
    for (final priority in [
      MessagePersistPriority.realtime,
      MessagePersistPriority.userHistory
    ]) {
      final waiters = _admissionWaiters[priority];
      if (waiters == null) continue;
      while (waiters.isNotEmpty &&
          _queueFor(priority).length + (_reservedAdmissions[priority] ?? 0) <
              foregroundQueueLimit) {
        _reservedAdmissions[priority] =
            (_reservedAdmissions[priority] ?? 0) + 1;
        waiters.removeFirst().complete();
      }
    }
  }

  Future<void> _execute(MessagePersistJob<dynamic> job) async {
    if (_accountGeneration != 0 &&
        job.accountGeneration != 0 &&
        job.accountGeneration != _accountGeneration) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(
          const MessagePersistRejected('stale_account_generation'),
        );
      }
      return;
    }
    final queuedUs = DateTime.now().microsecondsSinceEpoch - job.enqueuedAtUs;
    var prepareUs = 0;
    var txnWaitUs = 0;
    var txnUs = 0;
    var publishUs = 0;
    try {
      if (job.prepare != null) {
        final prepareWatch = Stopwatch()..start();
        await job.prepare!();
        prepareUs = prepareWatch.elapsedMicroseconds;
      }
      final txnWaitWatch = Stopwatch()..start();
      while (_txnInFlight) {
        await Future<void>.delayed(Duration.zero);
      }
      txnWaitUs = txnWaitWatch.elapsedMicroseconds;
      _txnInFlight = true;
      _executeDepth++;
      _executingPriority = job.priority;
      final txnWatch = Stopwatch()..start();
      late final dynamic value;
      try {
        value = await runZoned(
          job.run,
          zoneValues: <Object?, Object?>{_nestedRunZoneKey: true},
        );
      } finally {
        txnUs = txnWatch.elapsedMicroseconds;
        _txnInFlight = false;
        _executeDepth--;
        _executingPriority = null;
      }
      if (job.authorityKind != null) {
        for (final id in job.messageIds) {
          rememberAuthority(
            conversationId: job.conversationId,
            messageId: id,
            kind: job.authorityKind!,
          );
        }
      }
      if (job.publish != null && job.allowProjection) {
        final publishWatch = Stopwatch()..start();
        await job.publish!(value);
        publishUs = publishWatch.elapsedMicroseconds;
      }
      _metrics.add(
        MessagePersistMetrics(
          source: job.source,
          queueWaitUs: queuedUs,
          prepareCpuUs: prepareUs,
          txnWaitUs: txnWaitUs,
          txnUs: txnUs,
          publishUs: publishUs,
          batchSize: job.itemCount,
          queueDepth: queueDepth,
        ),
      );
      if (_metrics.length > 64) {
        _metrics.removeRange(0, _metrics.length - 64);
      }
      if (!job.completer.isCompleted) {
        job.completer.complete(value);
      }
    } catch (error, stack) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(error, stack);
      }
    }
  }

  void _rejectStale(Queue<MessagePersistJob<dynamic>> queue) {
    final kept = Queue<MessagePersistJob<dynamic>>();
    while (queue.isNotEmpty) {
      final job = queue.removeFirst();
      if (job.accountGeneration != 0 &&
          job.accountGeneration != _accountGeneration) {
        if (!job.completer.isCompleted) {
          job.completer.completeError(
            const MessagePersistRejected('stale_account_generation'),
          );
        }
      } else {
        kept.add(job);
      }
    }
    queue.addAll(kept);
  }

  bool _shouldProject(String conversationId) {
    final active = _activeChatConversationId;
    final id = conversationId.trim();
    if (active == null || active.isEmpty || id.isEmpty) {
      return false;
    }
    return id == active;
  }

  static String _authorityKey(String conversationId, String messageId) {
    final conv = conversationId.trim();
    final id = messageId.trim();
    if (conv.isEmpty || id.isEmpty) return '';
    return '$conv|$id';
  }

  static int _authorityRank(MessagePersistAuthorityKind kind) {
    return switch (kind) {
      MessagePersistAuthorityKind.delete => 4,
      MessagePersistAuthorityKind.revoke => 3,
      MessagePersistAuthorityKind.sendState => 2,
      MessagePersistAuthorityKind.edit => 2,
      MessagePersistAuthorityKind.read => 1,
    };
  }
}
