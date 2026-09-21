import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import '../pages/settings/lottery_drawer.dart';
import '../api/api_client.dart';
import '../../utils/api_response_util.dart';
import '../../utils/chat_id_format.dart';

Future<String?> loadLotteryGameIdFromSdk(String groupUid) async {
  final sdkId = ChatIdFormat.normalizeGroupId(groupUid);
  final response = await TencentImSDKPlugin.v2TIMManager
      .getGroupManager()
      .getGroupsInfo(groupIDList: [sdkId]);
  if (response.code != 0) {
    throw StateError('IM group lookup code=${response.code}');
  }
  for (final item in response.data ?? []) {
    if (item.resultCode == 0 &&
        ChatIdFormat.groupIdsEquivalent(
            item.groupInfo?.groupID ?? '', groupUid)) {
      return item.groupInfo?.customInfo?['gameid'];
    }
  }
  throw StateError('IM group record missing');
}

Future<bool> loadLotteryBackendEnabled(String groupUid) async {
  try {
    // App group metadata belongs to the main service, not the robot binding API.
    final response = await ApiClient.instance.dio.get(
      '/group/${Uri.encodeComponent(ChatIdFormat.apiGroupId(groupUid))}',
    );
    _logLotteryGateResponse(
        response.requestOptions.uri, response.statusCode, response.data);
    final data = unwrapApiPayload(response.data);
    final value = data is Map ? data['gameEnabled'] : null;
    if (kDebugMode) {
      debugPrint(
          '[LotteryEntryHTTP] gameEnabled=$value type=${value.runtimeType} allowed=${value == true}');
    }
    return value == true;
  } on DioError catch (error) {
    _logLotteryGateResponse(error.requestOptions.uri,
        error.response?.statusCode, error.response?.data);
    if (kDebugMode) debugPrint('[LotteryEntryHTTP] errorType=${error.type}');
    rethrow;
  }
}

void _logLotteryGateResponse(Uri uri, int? status, dynamic body) {
  if (!kDebugMode) return;
  dynamic redact(dynamic value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(
          key.toString(),
          RegExp(r'token|authorization|secret|password|cookie|credential|key',
                      caseSensitive: false)
                  .hasMatch(key.toString())
              ? '[redacted]'
              : redact(item)));
    }
    if (value is List) return value.map(redact).toList();
    return value;
  }

  debugPrint('[LotteryEntryHTTP] GET ${uri.origin}${uri.path} status=$status');
  // Non-JSON error pages are omitted; only structured response bodies are logged.
  final text = body is Map || body is List
      ? jsonEncode(redact(body))
      : '[non-JSON body: ${body.runtimeType}]';
  for (var offset = 0; offset < text.length; offset += 800) {
    final end = offset + 800 < text.length ? offset + 800 : text.length;
    debugPrint(
        '[LotteryEntryHTTP] response[${offset ~/ 800 + 1}]=${text.substring(offset, end)}');
  }
}

bool canShowLotteryEntry(Map<String, String>? customInfo,
        {bool backendEnabled = false}) =>
    (customInfo?['gameid']?.trim().isNotEmpty ?? false) && backendEnabled;

/// Independent of agent and Sangong permissions. IM custom fields are strings.
String _lotteryAccountId() => ApiClient.instance.authenticatedUserId;

final _entryStateCache = <(String, String, String, String?), (String?, bool)>{};

class LotteryChatEntry extends StatefulWidget {
  const LotteryChatEntry(
      {super.key,
      this.controller,
      required this.groupUid,
      this.accountId = _lotteryAccountId,
      this.loadGameId = loadLotteryGameIdFromSdk,
      this.loadEnabled = loadLotteryBackendEnabled});
  final TIMUIKitChatController? controller;
  final String groupUid;
  final String Function() accountId;
  final Future<String?> Function(String) loadGameId;
  final Future<bool> Function(String) loadEnabled;

  @override
  State<LotteryChatEntry> createState() => _LotteryChatEntryState();
}

class _LotteryChatEntryState extends State<LotteryChatEntry>
    with WidgetsBindingObserver {
  String? _gameId;
  double _verticalPosition = 0.3;
  bool _backendEnabled = false;
  int _requestGeneration = 0;
  String? _loadedAccount;
  String? _loadedToken;
  static const _hintCountKey = 'lottery_history_hint_count_v1';
  static const _hintOpenedKey = 'lottery_history_hint_opened_v1';
  Timer? _hintTimer;
  bool _hintVisible = false;
  bool _hintConsidered = false;
  bool _entryOpened = false;

  Future<void> _showHistoryHint(int generation) async {
    if (_hintConsidered || _entryOpened) return;
    _hintConsidered = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || generation != _requestGeneration || _entryOpened) return;
      final count = prefs.getInt(_hintCountKey) ?? 0;
      if (prefs.getBool(_hintOpenedKey) == true || count >= 3) return;
      setState(() => _hintVisible = true);
      _hintTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _hintVisible = false);
      });
      await prefs.setInt(_hintCountKey, count + 1);
    } catch (_) {
      // Optional onboarding must never prevent opening the drawer.
    }
  }

  Future<void> _rememberEntryOpened() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hintOpenedKey, true);
    } catch (_) {
      // Keep navigation usable even if local storage is unavailable.
    }
  }

  Future<void> _loadBackendEnabled() async {
    final generation = ++_requestGeneration;
    _hintTimer?.cancel();
    _hintVisible = false;
    final groupUid = widget.groupUid;
    final account = widget.accountId();
    final token = ApiClient.instance.token;
    _loadedAccount = account;
    _loadedToken = token;
    final key = (account, groupUid, ApiClient.resolveBaseUrl(), token);
    final cached = account.isEmpty ? null : _entryStateCache[key];
    _backendEnabled = cached?.$2 ?? false;
    _gameId = cached?.$1;
    if (groupUid.isEmpty) return;
    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        groupUid == widget.groupUid &&
        account == widget.accountId() &&
        token == ApiClient.instance.token &&
        key.$3 == ApiClient.resolveBaseUrl();
    void cache(String? gameId, bool enabled) {
      if (account.isEmpty) return;
      _entryStateCache.remove(key);
      _entryStateCache[key] = (gameId, enabled);
      if (_entryStateCache.length > 100) {
        _entryStateCache.remove(_entryStateCache.keys.first);
      }
    }

    void revoke() {
      if (!isCurrent()) return;
      cache(null, false);
      _hintTimer?.cancel();
      setState(() {
        _backendEnabled = false;
        _hintVisible = false;
      });
    }

    try {
      final values = await Future.wait<Object?>([
        widget.loadGameId(groupUid).then((value) {
          if (value == null || value.trim().isEmpty) revoke();
          return value;
        }),
        widget.loadEnabled(groupUid).then((value) {
          if (!value) revoke();
          return value;
        }),
      ]);
      final gameId = values[0] as String?;
      final enabled = values[1] == true;
      if (!isCurrent()) {
        return;
      }
      cache(gameId, enabled);
      debugPrint(
          '[LotteryEntry] sdkGameIdPresent=${gameId?.trim().isNotEmpty == true} backendEnabled=$enabled');
      setState(() {
        _backendEnabled = enabled;
        _gameId = gameId;
      });
      if (canShowLotteryEntry({'gameid': gameId ?? ''},
          backendEnabled: enabled)) {
        unawaited(_showHistoryHint(generation));
      }
    } catch (error) {
      if (!isCurrent()) return;
      _entryStateCache.remove(key);
      debugPrint(
          '[LotteryEntry] loadFailed type=${error.runtimeType}; entry hidden');
      setState(() => _backendEnabled = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBackendEnabled();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _loadBackendEnabled();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LotteryChatEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupUid != widget.groupUid ||
        _loadedAccount != widget.accountId() ||
        _loadedToken != ApiClient.instance.token) {
      _loadBackendEnabled();
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    ++_requestGeneration;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedAccount != widget.accountId() ||
        _loadedToken != ApiClient.instance.token ||
        !canShowLotteryEntry({'gameid': _gameId ?? ''},
            backendEnabled: _backendEnabled)) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, constraints) {
        const height = 56.0;
        final travel = (constraints.maxHeight - height)
            .clamp(0.0, double.infinity)
            .toDouble();
        final top = (constraints.maxHeight * _verticalPosition - height / 2)
            .clamp(0.0, travel)
            .toDouble();
        return Stack(children: [
          Positioned(
            right: 46,
            top: top,
            height: height,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hintVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 10,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: const Text('点击查看开奖记录',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF555555))),
                  ),
                  Transform.translate(
                    offset: const Offset(-4, 0),
                    child: Transform.rotate(
                        angle: 0.785398,
                        child: const SizedBox(
                            width: 8,
                            height: 8,
                            child: ColoredBox(color: Colors.white))),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
              right: 0,
              top: top,
              child: GestureDetector(
                key: const ValueKey('lottery-edge-handle'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  _hintTimer?.cancel();
                  setState(() => _hintVisible = false);
                },
                onVerticalDragUpdate: (details) {
                  if (travel <= 0) return;
                  setState(() => _verticalPosition =
                      ((top + details.delta.dy).clamp(0.0, travel) +
                              height / 2) /
                          constraints.maxHeight);
                },
                onTap: () {
                  if (!canShowLotteryEntry({'gameid': _gameId ?? ''},
                      backendEnabled: _backendEnabled)) {
                    return;
                  }
                  _entryOpened = true;
                  _hintTimer?.cancel();
                  setState(() => _hintVisible = false);
                  unawaited(_rememberEntryOpened());
                  showLotteryDrawer(context,
                      groupUid: widget.groupUid,
                      gameId: _gameId,
                      anchorY: (context.findRenderObject() as RenderBox?)
                          ?.localToGlobal(Offset(0, top + height / 2))
                          .dy);
                },
                child: Semantics(
                  label: '点击查看开奖记录',
                  button: true,
                  child: const SizedBox(
                    width: 40,
                    height: height,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xCCFFFFFF),
                          borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(14)),
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x10000000),
                                blurRadius: 6,
                                offset: Offset(-1, 1))
                          ],
                        ),
                        child: SizedBox(
                            width: 28,
                            height: 48,
                            child: Icon(Icons.chevron_left_rounded,
                                size: 28, color: Color(0xFF777777))),
                      ),
                    ),
                  ),
                ),
              ))
        ]);
      }),
    );
  }
}
