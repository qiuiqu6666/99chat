import 'dart:async';
import 'dart:math' as math;

import 'latest_search_lane.dart';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

typedef ConversationMessageSearch
    = Future<V2TimValueCallback<V2TimMessageSearchResult>> Function({
  required bool cloud,
  required V2TimMessageSearchParam param,
});

/// One query owns both SDK cursors; stale requests cannot change either cursor.
class ConversationTextSearchController {
  ConversationTextSearchController({
    required this.read,
    required this.ownerId,
    required this.onChanged,
    this.accountGeneration,
    this.onTrace,
    this.debounce = const Duration(milliseconds: 300),
    this.timeout = const Duration(seconds: 15),
  });

  final ConversationMessageSearch read;
  final String Function() ownerId;
  final int Function()? accountGeneration;
  final void Function() onChanged;
  final void Function(String event, Map<String, Object?> fields)? onTrace;
  final Duration debounce;
  final Duration timeout;
  static const pageSize = 30;

  final _localLane =
      LatestSearchLane<V2TimValueCallback<V2TimMessageSearchResult>>();
  final _cloudLane =
      LatestSearchLane<V2TimValueCallback<V2TimMessageSearchResult>>();
  final Set<String> _messageIds = {};
  Timer? _notificationTimer;
  Timer? _timer;

  void _notifySoon() {
    final generation = _generation;
    _notificationTimer ??= Timer(Duration.zero, () {
      _notificationTimer = null;
      if (_isCurrent(generation)) onChanged();
    });
  }

  void _notifyNow() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    onChanged();
  }

  int _generation = 0;
  int? _inFlight;
  String _owner = '';
  int _accountGeneration = 0;
  String keyword = '';
  String conversationId = '';
  List<V2TimMessage> messages = [];
  int totalCount = 0;
  bool loading = false;
  bool completed = false;
  bool localFailed = false;
  bool cloudFailed = false;
  int? localErrorCode;
  int? cloudErrorCode;
  int _localPage = 0;
  String _cloudCursor = '';
  bool _localFinished = false;
  bool _cloudFinished = false;
  final Set<String> _localIds = {};

  bool get hasError => localFailed || cloudFailed;
  bool get hasMore => completed && (!_localFinished || !_cloudFinished);

  void _trace(String event, [Map<String, Object?> fields = const {}]) {
    onTrace?.call(event, {
      'generation': _generation,
      'conv': conversationId,
      'keywordLength': keyword.length,
      ...fields,
    });
  }

  void clear({bool notify = true}) {
    if (keyword.isNotEmpty) _trace('cancel');
    _timer?.cancel();
    _generation++;
    _localLane.cancelPending();
    _cloudLane.cancelPending();
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _messageIds.clear();
    _inFlight = null;
    _owner = '';
    keyword = '';
    conversationId = '';
    messages = [];
    totalCount = 0;
    loading = false;
    completed = false;
    localFailed = cloudFailed = false;
    localErrorCode = cloudErrorCode = null;
    _localPage = 0;
    _cloudCursor = '';
    _localFinished = _cloudFinished = false;
    _localIds.clear();
    if (notify) onChanged();
  }

  void schedule(String query, String conversation) {
    _prepare(query, conversation);
    if (keyword.isEmpty) return;
    final generation = _generation;
    _timer = Timer(debounce, () => _load(generation));
  }

  Future<void> search(String query, String conversation) {
    _prepare(query, conversation);
    return keyword.isEmpty ? Future.value() : _load(_generation);
  }

  void _prepare(String query, String conversation) {
    clear(notify: false);
    keyword = query.trim();
    conversationId = conversation.trim();
    _owner = ownerId();
    _accountGeneration = accountGeneration?.call() ?? 0;
    loading = keyword.isNotEmpty;
    _trace('query', {'ownerReady': _owner.isNotEmpty});
    onChanged();
  }

  Future<void> loadMore() {
    // An initial attempt may run before the SDK login has completed.
    if (!_isCurrent(_generation)) return search(keyword, conversationId);
    return _load(_generation);
  }

  bool _isCurrent(int generation) =>
      generation == _generation &&
      _owner == ownerId() &&
      _accountGeneration == (accountGeneration?.call() ?? 0);

  Future<void> _load(int generation) async {
    if (!_isCurrent(generation) ||
        keyword.isEmpty ||
        _inFlight == generation ||
        (_localFinished && _cloudFinished)) {
      return;
    }
    if (_owner.isEmpty || conversationId.isEmpty) {
      _trace('blocked', {
        'reason':
            _owner.isEmpty ? 'sdk_login_unavailable' : 'empty_conversation',
      });
      loading = false;
      completed = true;
      localFailed = cloudFailed = true;
      onChanged();
      return;
    }
    _inFlight = generation;
    if (!loading) {
      loading = true;
      _notifyNow();
    }
    // Local matches can be painted while the cloud request is still pending.
    // Always query both: cloud retention/indexing and local availability differ.
    await Future.wait([
      if (!_localFinished) _readPage(generation, cloud: false),
      if (!_cloudFinished) _readPage(generation, cloud: true),
    ]);
    if (!_isCurrent(generation)) return;
    _inFlight = null;
    loading = false;
    completed = true;
    _trace('complete', {
      'rows': messages.length,
      'total': totalCount,
      'localCode': localErrorCode,
      'cloudCode': cloudErrorCode,
      'hasError': hasError,
      'hasMore': hasMore,
    });
    _notifyNow();
  }

  Future<void> _readPage(int generation, {required bool cloud}) async {
    final cursor = _cloudCursor;
    final page = _localPage;
    final requestConversation = conversationId;
    final requestKeyword = keyword;
    final requestKeywordLength = requestKeyword.length;
    final watch = Stopwatch()..start();
    final requestFields = <String, Object?>{
      'generation': generation,
      'conv': requestConversation,
      'keywordLength': requestKeywordLength,
      'source': cloud ? 'cloud' : 'local',
      'api': cloud ? 'searchCloudMessages' : 'searchLocalMessages',
      'page': cloud ? null : page,
      'hasCursor': cloud && cursor.isNotEmpty,
      'count': pageSize,
    };
    var waiting = true;
    try {
      final lane = cloud ? _cloudLane : _localLane;
      final result = await lane.run(() {
        _trace('request', requestFields);
        return read(
          cloud: cloud,
          param: V2TimMessageSearchParam(
            keywordList: [requestKeyword],
            conversationID: requestConversation,
            type: 0,
            pageIndex: cloud ? null : page,
            pageSize: pageSize,
            searchCount: pageSize,
            searchCursor: cloud ? cursor : null,
            searchTimePosition: 0,
            searchTimePeriod: 0,
          ),
        );
      }, () => waiting && _isCurrent(generation)).timeout(timeout);
      if (result == null) return;
      _trace('response', {
        ...requestFields,
        'elapsedMs': watch.elapsedMilliseconds,
        'code': result.code,
        'desc': result.desc,
        'hasData': result.data != null,
        'total': result.data?.totalCount,
        'groups': result.data?.messageSearchResultItems?.length ?? 0,
        'returnedConversations': result.data?.messageSearchResultItems
            ?.take(3)
            .map((item) => item.conversationID)
            .toList(),
        'rawRows': result.data?.messageSearchResultItems?.fold<int>(
                0, (count, item) => count + (item.messageList?.length ?? 0)) ??
            0,
        'hasNextCursor': result.data?.searchCursor?.isNotEmpty ?? false,
      });
      if (!_isCurrent(generation)) {
        _trace('discard',
            {...requestFields, 'reason': 'query_or_account_changed'});
        return;
      }
      if (result.code != 0 || result.data == null) {
        _fail(cloud, result.code);
        return;
      }
      final data = result.data!;
      final items = (data.messageSearchResultItems ?? [])
          .where((item) => _matchesConversation(item.conversationID));
      final incoming = <V2TimMessage>[];
      var count = 0;
      for (final item in items) {
        incoming.addAll(item.messageList ?? []);
        count = math.max(count, item.messageCount ?? 0);
      }
      // Sort only the new page; merge it into the already ordered window.
      // A repeated/empty page keeps the current list and does no full sort.
      final additions = incoming
          .where((message) => _messageIds.add(_identity(message)))
          .toList()
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      if (additions.isNotEmpty) {
        final merged = <V2TimMessage>[];
        var oldIndex = 0;
        var newIndex = 0;
        while (oldIndex < messages.length && newIndex < additions.length) {
          if ((messages[oldIndex].timestamp ?? 0) >=
              (additions[newIndex].timestamp ?? 0)) {
            merged.add(messages[oldIndex++]);
          } else {
            merged.add(additions[newIndex++]);
          }
        }
        merged.addAll(messages.skip(oldIndex));
        merged.addAll(additions.skip(newIndex));
        messages = merged;
      }
      totalCount = math.max(totalCount, math.max(count, messages.length));
      if (cloud) {
        cloudFailed = false;
        cloudErrorCode = null;
        final next = data.searchCursor?.trim() ?? '';
        _cloudCursor = next;
        _cloudFinished = next.isEmpty || next == cursor;
      } else {
        localFailed = false;
        localErrorCode = null;
        final before = _localIds.length;
        _localIds.addAll(incoming.map(_identity));
        _localPage = page + 1;
        final total = math.max(count, data.totalCount ?? 0);
        _localFinished = incoming.isEmpty ||
            _localIds.length == before ||
            (total > 0
                ? _localIds.length >= total
                : incoming.length < pageSize);
      }
      _trace('accepted', {
        ...requestFields,
        'matchedRows': incoming.length,
        'rows': messages.length,
        'finished': cloud ? _cloudFinished : _localFinished,
      });
      _notifySoon();
    } catch (error) {
      _trace('exception', {
        ...requestFields,
        'elapsedMs': watch.elapsedMilliseconds,
        'kind': error is TimeoutException
            ? 'timeout'
            : error.runtimeType.toString(),
        'discarded': !_isCurrent(generation),
      });
      if (_isCurrent(generation)) _fail(cloud, -1);
    } finally {
      waiting = false;
    }
  }

  void _fail(bool cloud, int code) {
    if (cloud) {
      cloudFailed = true;
      cloudErrorCode = code;
    } else {
      localFailed = true;
      localErrorCode = code;
    }
    // Preserve accepted rows and cursors. A retry repeats only unaccepted pages.
    _notifySoon();
  }

  bool _matchesConversation(String? candidate) {
    var wanted = conversationId.trim();
    var actual = candidate?.trim() ?? '';
    if (actual.isEmpty) return false;
    if (wanted.startsWith('group_')) {
      if (actual.startsWith('c2c_')) return false;
      while (wanted.startsWith('group_')) {
        wanted = wanted.substring(6);
      }
      while (actual.startsWith('group_')) {
        actual = actual.substring(6);
      }
      return searchGroupIdsEquivalent(wanted, actual);
    }
    if (wanted.startsWith('c2c_')) {
      if (actual.startsWith('group_')) return false;
      wanted = wanted.substring(4);
      if (actual.startsWith('c2c_')) actual = actual.substring(4);
    }
    return wanted == actual;
  }

  String _identity(V2TimMessage message) {
    final id = (message.msgID ?? message.id ?? '').trim();
    return id.isNotEmpty
        ? id
        : '${message.sender}|${message.timestamp}|${message.seq}|${message.elemType}';
  }
}
