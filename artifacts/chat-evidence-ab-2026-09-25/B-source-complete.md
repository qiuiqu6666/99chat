**B 包完整源码摘录**

这些是当前工作树的原文快照，不是修改后的实现。用 Dart AST 边界提取完整方法/类型，保留原文件路径、起止行号和哈希；依赖导入和未摘录上下文可回到原文件核对。

1. [_ChatState._draft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:371>)，原文件 lib/src/chat.dart，371–371 行。

~~~dart
final ChatDraftController _draft = ChatDraftController();
~~~

2. [_ChatState._draftWrites](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:372>)，原文件 lib/src/chat.dart，372–372 行。

~~~dart
final ChatDraftWriteQueue _draftWrites = ChatDraftWriteQueue();
~~~

3. [_ChatState._beginChatOpenGeneration](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:490>)，原文件 lib/src/chat.dart，490–490 行。

~~~dart
int _beginChatOpenGeneration() => ++_chatOpenGeneration;
~~~

4. [_ChatState._isChatOpenGenerationCurrent](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:492>)，原文件 lib/src/chat.dart，492–503 行。

~~~dart
bool _isChatOpenGenerationCurrent(int generation, String conversationID) {
    return mounted &&
        generation == _chatOpenGeneration &&
        ChatPageScope.instance.allowsProjection(
          token: _pageScope,
          conversationId: conversationID,
        ) &&
        MessageConversationId.sameConversation(
          _resolvedConversationID(),
          conversationID,
        );
  }
~~~

5. [_ChatState._scheduleReconnectHistoryRecovery](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:911>)，原文件 lib/src/chat.dart，911–943 行。

~~~dart
void _scheduleReconnectHistoryRecovery() {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = _resolvedConversationID();
    _reconnectRecoveryTimer?.cancel();
    _reconnectRecoveryTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_isChatOpenGenerationCurrent(generation, scheduledConversationID)) {
        return;
      }
      final conversationId = _resolvedConversationID();
      if (conversationId.isEmpty) {
        return;
      }
      if (_latestWindowResetNeeded()) {
        // Real reconnect while the page is open: the latest-window reset owns
        // recovery. It repairs immediately when the user is at the bottom and
        // defers (polling) while history is being read. The anchor-based
        // catch-up must not compete for the same recovery.
        _armLatestWindowResetWhenAtBottom(reason: 'im_reconnected');
        return;
      }
      unawaited(
        ConversationHistorySyncCoordinator.instance.reconcileConversation(
          conversationID: conversationId,
          conversation: _conversation,
          reason: 'im_reconnected',
        ),
      );
      ChatHistoryRefreshBus.instance.requestRefresh(
        conversationId: conversationId,
        reason: 'im_reconnected',
      );
    });
  }
~~~

6. [_ChatState._loadChatLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1306>)，原文件 lib/src/chat.dart，1306–1351 行。

~~~dart
Future<void> _loadChatLocalDraft() async {
    final conversationId = _resolvedConversationID();
    if (conversationId.isEmpty) {
      return;
    }
    final loadRevision = _draft.stateRevision;
    final text = await ConversationDraftService.instance.loadDraftText(
      conversationID: conversationId,
    );
    if (!mounted ||
        !_isCurrentConversation(conversationId) ||
        !_draft.canApplyLoadedDraft(loadRevision)) {
      return;
    }
    _draft.setTextImmediate(text);
    final loaded = text?.trim() ?? '';
    if (loaded.isEmpty) {
      return;
    }

    void applyToInputIfReady() {
      if (!mounted ||
          !_isCurrentConversation(conversationId) ||
          !_draft.canApplyLoadedDraft(loadRevision)) {
        return;
      }
      final inputController = _chatController.textFieldController;
      final editingController = inputController?.textEditingController;
      if (inputController == null || editingController == null) {
        return;
      }
      if (editingController.text.trim().isEmpty) {
        inputController.setTextField(text!, notifyChanged: false);
      }
    }

    // The outer controller owns a TextEditingController before the actual
    // input widget has attached its listener. A draft loaded in that window
    // makes setTextField() notify nobody. Rebuild with draftText for initState,
    // then retry after the frame for an already-created input widget.
    applyToInputIfReady();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyToInputIfReady();
    });
  }
~~~

7. [_ChatState._persistChatLocalDraftText](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1353>)，原文件 lib/src/chat.dart，1353–1405 行。

~~~dart
Future<void> _persistChatLocalDraftText(
    String text,
    int generation, {
    String? conversationID,
    bool enforceCurrentGeneration = true,
  }) async {
    final conversationId = (conversationID ?? _resolvedConversationID()).trim();
    if (conversationId.isEmpty) {
      return;
    }
    await _draftWrites.enqueue(
      () async {
        if (enforceCurrentGeneration && _draft.shouldSuppressLifecyclePersist) {
          ConversationDraftLeaveTrace.stage(
            'draft_persist_skipped',
            conversationId: conversationId,
            extras: const <String, Object?>{'reason': 'suppress'},
          );
          return;
        }
        if (enforceCurrentGeneration && generation != _draft.writeGeneration) {
          ConversationDraftLeaveTrace.stage(
            'draft_persist_skipped',
            conversationId: conversationId,
            extras: const <String, Object?>{'reason': 'generation'},
          );
          return;
        }
        if (_isCurrentConversation(conversationId)) {
          _draft.text = text.trim().isEmpty ? null : text;
        }
        ConversationDraftLeaveTrace.stage(
          'draft_persist_enqueue_run',
          conversationId: conversationId,
          draftText: text,
          extras: <String, Object?>{
            'generation': generation,
            'suppress': _draft.shouldSuppressLifecyclePersist,
          },
        );
        await ConversationDraftService.instance.persistDraft(
          conversationID: conversationId,
          rawInputText: text,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          '[ChatDraft] persist failed conv=$conversationId error=$error\n'
          '$stackTrace',
        );
      },
    );
  }
~~~

8. [_ChatState._onChatDraftTextChanged](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1407>)，原文件 lib/src/chat.dart，1407–1422 行。

~~~dart
void _onChatDraftTextChanged(String text) {
    final conversationId = _resolvedConversationID();
    if (text.trim().isNotEmpty) {
      ConversationDraftLeaveTrace.focus(conversationId);
    }
    ConversationDraftLeaveTrace.stage(
      'draft_input_changed',
      conversationId: conversationId,
      draftText: text,
    );
    _draft.onChanged(
      text,
      persist: (raw, generation) =>
          unawaited(_persistChatLocalDraftText(raw, generation)),
    );
  }
~~~

9. [_ChatState._persistChatLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1424>)，原文件 lib/src/chat.dart，1424–1444 行。

~~~dart
Future<void> _persistChatLocalDraft() async {
    if (_draft.shouldSuppressLifecyclePersist) {
      return;
    }
    _draft.cancelDebounce();
    final text =
        _chatController.textFieldController?.textEditingController?.text ?? '';
    final conversationId = _resolvedConversationID();
    ConversationDraftLeaveTrace.focus(conversationId);
    ConversationDraftLeaveTrace.stage(
      'draft_leave_persist_start',
      conversationId: conversationId,
      draftText: text,
      extras: const <String, Object?>{'source': 'lifecycle'},
    );
    await _persistChatLocalDraftText(
      text,
      _draft.writeGeneration,
      conversationID: conversationId,
    );
  }
~~~

10. [_ChatState._clearChatLocalDraftAfterSend](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1446>)，原文件 lib/src/chat.dart，1446–1476 行。

~~~dart
Future<void> _clearChatLocalDraftAfterSend(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    // 发送成功后使发送前排队的 debounce 保存失效，否则旧草稿可能在清理后
    // 又被异步写回本地库，表现为“消息已发出但草稿仍出现”。
    _draft.markSendCompleted();
    if (mounted) {
      _draft.text = null;
    }
    final ids = <String>{id, _conversation.conversationID.trim()};
    final groupId = _conversation.groupID?.trim() ?? '';
    if (_getConvType() == ConvType.group && groupId.isNotEmpty) {
      ids.add(groupId);
      ids.add('group_$groupId');
    }
    await _draftWrites.enqueue(
      () async {
        await ConversationDraftService.instance.clearDraftForConversationIds(
          ids,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          '[ChatDraft] clear-after-send failed conv=$id error=$error\n'
          '$stackTrace',
        );
      },
    );
  }
~~~

11. [_ChatState._seedCachedHistoryOnOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4135>)，原文件 lib/src/chat.dart，4135–4159 行。

~~~dart
void _seedCachedHistoryOnOpen(String convKey) {
    if (convKey.isEmpty) {
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    globalModel.setMessageListPosition(
      convKey,
      HistoryMessagePosition.bottom,
      notify: false,
    );

    final rawCount = globalModel.rawMessageCount(convKey);
    if (rawCount > 0) {
      final list = globalModel.getMessageList(convKey);
      if (list != null) {
        _normalizeSelfMessageAvatars(list);
      }
      if (globalModel.hasInitialHistoryLoaded(convKey)) {
        return;
      }
      if (rawCount >= HistoryMessageDartConstant.initialOpenFetchCount) {
        globalModel.markInitialHistoryLoaded(convKey);
      }
    }
  }
~~~

12. [_ChatState._isOpenHistoryWarm](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4161>)，原文件 lib/src/chat.dart，4161–4184 行。

~~~dart
bool _isOpenHistoryWarm(String convKey) {
    if (convKey.isEmpty) {
      return false;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (!globalModel.hasInitialHistoryLoaded(convKey)) {
      return false;
    }
    // removeMessageList 会删掉 map 条目；若只剩残留 loaded 别名，不能当暖窗，
    // 否则跳过 gate 又无消息 → 整页空灰。
    final raw = globalModel.rawMessageList(convKey);
    if (raw == null) {
      return false;
    }
    if (raw.isNotEmpty) {
      return true;
    }
    // 空 list：仅在「会话确实像空」且没有并行 peek 时算 warm。
    // 冷开并行期间禁止把空占位当成暖窗，否则会跳过 gate + hydrate_keep_empty。
    if (globalModel.hasOpenHydrateInFlight(convKey)) {
      return false;
    }
    return _conversationLooksEmptyForOpen(convKey);
  }
~~~

13. [_ChatState._conversationLooksEmptyForOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4186>)，原文件 lib/src/chat.dart，4186–4209 行。

~~~dart
/// 列表侧已无真实历史证据时，进页应直接空态，而不是先转圈拉历史。
  bool _conversationLooksEmptyForOpen(String convKey) {
    if (convKey.isEmpty) {
      return false;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (globalModel.rawMessageCount(convKey) > 0) {
      return false;
    }
    final conv = widget.selectedConversation;
    if ((conv.unreadCount ?? 0) > 0) {
      return false;
    }
    final last = conv.lastMessage;
    // 仅 lastMessage 缺失才预判空。最新一条是 tip/灰字不代表 SDK 无历史；
    // 冷开并行 peek 前误标 empty-loaded 会 hydrate_keep_empty → 灰屏。
    //
    // 社群：列表预览因 ID/落库失败暂时为 null 时，禁止预判空——否则再进页
    // 会 clearLocalHistoryAsEmptyLoaded，跳过云端拉历史，聊天记录整页空白。
    if (last == null && _getConvType() == ConvType.group) {
      return false;
    }
    return last == null;
  }
~~~

14. [_ChatState._ensureEmptyConversationReadyForOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4211>)，原文件 lib/src/chat.dart，4211–4225 行。

~~~dart
void _ensureEmptyConversationReadyForOpen(String convKey) {
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // 冷开并行 peek 未完成：禁止预判 empty-loaded。
    if (globalModel.hasOpenHydrateInFlight(convKey)) {
      return;
    }
    if (!_conversationLooksEmptyForOpen(convKey)) {
      return;
    }
    if (globalModel.hasInitialHistoryLoaded(convKey) &&
        globalModel.rawMessageCount(convKey) == 0) {
      return;
    }
    globalModel.clearLocalHistoryAsEmptyLoaded(convKey);
  }
~~~

15. [_ChatState._startOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4227>)，原文件 lib/src/chat.dart，4227–4301 行。

~~~dart
void _startOpenHistoryGate(String convKey) {
    _openLifecycle.openHistoryGateConvKey = convKey;
    _openLifecycle.openHistoryPreparationGate = null;
    if (convKey.isEmpty ||
        widget.initFindingMsg != null ||
        widget.searchJumpAnchor != null ||
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          _getConvType(),
          widget.entryUnreadCount ?? 0,
        )) {
      _openLifecycle.openHistoryGate = null;
      if (convKey.isNotEmpty) {
        ChatHistoryOpenLayoutReady.cancel(convKey);
      }
      return;
    }
    // 先同步灌入缓存；只有完整首屏（或确认空）才跳过 gate。
    // 列表 LOCAL 预热常常只有几条：立刻上屏会在反转列表底部露出大片空白。
    _seedCachedHistoryOnOpen(convKey);
    _ensureEmptyConversationReadyForOpen(convKey);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final rawCount = globalModel.rawMessageCount(convKey);
    final emptyConfirmed =
        globalModel.hasInitialHistoryLoaded(convKey) && rawCount == 0;
    final completeWindow =
        ConversationPreviewHistorySync.isCompleteOpenHistoryWindow(
      globalModel: globalModel,
      conversationKey: convKey,
    );
    // 完整首屏或确认空：无需等待可交互 gate。
    if (completeWindow || emptyConfirmed) {
      ChatHistoryOpenLayoutReady.cancel(convKey);
      ChatOpenPerfLog.mark(
        'history_gate_content_ready_skip',
        conversationID: convKey,
        extras: <String, Object?>{
          'rawCount': rawCount,
          'emptyConfirmed': emptyConfirmed,
          'completeWindow': completeWindow,
          'initialLoaded': globalModel.hasInitialHistoryLoaded(convKey),
        },
      );
      _openLifecycle.openHistoryGate = null;
      final preparation = _prepareOpenHistoryGate(
        convKey,
        cachedHistorySeeded: true,
      );
      _openLifecycle.openHistoryPreparationGate = preparation;
      unawaited(preparation);
      if (_getConvType() == ConvType.group) {
        unawaited(_ensureGroupLocalTipsMergedOnOpen(convKey));
      }
      return;
    }
    ChatHistoryOpenLayoutReady.begin(convKey);
    // 未灌满的预热窗也走 prepare + layout，避免先亮底部几条。
    // 真冷零消息仍串行；事件名保留 cold_shell，兼容既有性能日志。
    final thinWindow = rawCount > 0;
    ChatOpenPerfLog.mark(
      thinWindow ? 'history_gate_thin_window' : 'history_gate_cold_shell',
      conversationID: convKey,
      extras: <String, Object?>{'rawCount': rawCount},
    );
    final preparation = _prepareOpenHistoryGate(
      convKey,
      cachedHistorySeeded: true,
      coldOpen: !thinWindow,
    );
    _openLifecycle.openHistoryPreparationGate = preparation;
    _openLifecycle.openHistoryGate = _runOpenHistoryGateWithTipsMerge(
      convKey,
      coldOpen: !thinWindow,
      preparation: preparation,
    );
  }
~~~

16. [_ChatState._runOpenHistoryGateWithTipsMerge](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4303>)，原文件 lib/src/chat.dart，4303–4350 行。

~~~dart
/// 先权威历史（冷开 / 薄窗均可 soft-timeout），再合本地 tip，
  /// 再等几何 ready。preparation 绝不能无限挂起，否则 AbsorbPointer 锁死滚动。
  Future<void> _runOpenHistoryGateWithTipsMerge(
    String convKey, {
    required bool coldOpen,
    required Future<void> preparation,
  }) async {
    if (convKey.isEmpty) {
      return;
    }
    // 薄窗与真冷共用硬超时：薄窗原先无超时，云端慢时门永不关 → 能返回不能滑。
    await preparation.timeout(
      const Duration(milliseconds: 1200),
      onTimeout: () {
        ChatOpenPerfLog.mark(
          coldOpen
              ? 'history_gate_timeout_1_2s'
              : 'history_gate_thin_timeout_1_2s',
          conversationID: convKey,
        );
      },
    );
    if (!mounted) {
      return;
    }
    try {
      await _ensureGroupLocalTipsMergedOnOpen(
        convKey,
      ).timeout(const Duration(milliseconds: 400));
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'history_gate_tips_merge_timeout',
        conversationID: convKey,
      );
    } catch (_) {
      // tip 合并失败不挡揭开门。
    }
    if (!mounted) {
      return;
    }
    // 列表已经揭开并 signal 过：不要二次 begin 抬 epoch，否则会把已亮的历史闪没。
    if (ChatHistoryOpenLayoutReady.isReady(convKey)) {
      return;
    }
    // 作废 prepare/tip 期间可能发出的假 signal，再等几何 ready。
    ChatHistoryOpenLayoutReady.begin(convKey);
    await _waitOpenHistoryLayoutReady(convKey);
  }
~~~

17. [_ChatState._waitOpenHistoryLayoutReady](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4352>)，原文件 lib/src/chat.dart，4352–4365 行。

~~~dart
Future<void> _waitOpenHistoryLayoutReady(String convKey) async {
    // History preparation already has a 1.2s soft timeout. Do not add another
    // full second of shell time when hidden-list geometry cannot settle yet.
    final ready = await ChatHistoryOpenLayoutReady.wait(
      convKey,
      timeout: const Duration(milliseconds: 300),
    );
    if (!ready) {
      ChatOpenPerfLog.mark(
        'history_open_ready_timeout',
        conversationID: convKey,
      );
    }
  }
~~~

18. [_ChatState._prepareOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4367>)，原文件 lib/src/chat.dart，4367–4416 行。

~~~dart
Future<void> _prepareOpenHistoryGate(
    String convKey, {
    bool cachedHistorySeeded = false,
    bool coldOpen = false,
  }) async {
    if (convKey.isEmpty) {
      return;
    }
    if (!cachedHistorySeeded) {
      _seedCachedHistoryOnOpen(convKey);
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    ChatOpenPerfLog.mark(
      'prepare_gate_start',
      conversationID: convKey,
      extras: <String, Object?>{'coldOpen': coldOpen},
    );
    // Reuse the local-only snapshot started at tap time. Direct entry paths
    // that do not pass through the conversation list start the same bounded
    // local task here. Cloud verification remains outside this gate.
    final loaded =
        await ChatOpenViewportCoordinator.instance.ensureLocalSnapshotForOpen(
      conversation: _conversation,
      timeout: const Duration(milliseconds: 900),
    );
    if (!mounted) return;
    if (loaded) {
      _chatController.model?.syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(convKey),
      );
      ChatOpenPerfLog.mark('prepare_gate_local_snapshot_reused',
          conversationID: convKey);
    }
    ChatOpenPerfLog.mark(
      'prepare_gate_bootstrap_done',
      conversationID: convKey,
      extras: <String, Object?>{
        'loaded': loaded,
        'rawCount': globalModel.rawMessageCount(convKey),
      },
    );
    if (!mounted) {
      return;
    }
    if (loaded) {
      _clearMountedDisplayListCache();
    }
    _markChatOpenHistoryReady();
    ChatOpenPerfLog.mark('prepare_gate_complete', conversationID: convKey);
  }
~~~

19. [_ChatState._ensureGroupLocalTipsMergedOnOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4504>)，原文件 lib/src/chat.dart，4504–4522 行。

~~~dart
/// 进聊首屏前合并本地群灰字并过滤占位 IM tip（设/取消管理员等）。
  Future<void> _ensureGroupLocalTipsMergedOnOpen(String convKey) async {
    if (!mounted || convKey.isEmpty) {
      return;
    }
    if (_getConvType() != ConvType.group || !SelfHostedGroupBridge.enabled) {
      return;
    }
    final groupId =
        widget.selectedConversation.groupID?.trim().isNotEmpty == true
            ? widget.selectedConversation.groupID!.trim()
            : convKey;
    if (groupId.isEmpty) {
      return;
    }
    await GroupTipsOperatorPatchService.instance.applyPatchesForVisibleGroup(
      groupId,
    );
  }
~~~

20. [_ChatState._wrapChatWithOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4536>)，原文件 lib/src/chat.dart，4536–4541 行。

~~~dart
Widget _wrapChatWithOpenHistoryGate(Widget chatWidget) {
    // History readiness remains a lifecycle/scheduling gate, not a page-wide
    // interaction gate. The stable TIMUIKitChat tree owns its loading state,
    // while the app bar and input stay responsive during a cold history load.
    return chatWidget;
  }
~~~

21. [_ChatState._reloadChatHistoryIfEmpty](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7379>)，原文件 lib/src/chat.dart，7379–7573 行。

~~~dart
Future<void> _reloadChatHistoryIfEmpty({required String reason}) async {
    if (!mounted) {
      return;
    }
    if (_hasVisibleHistoryMessages()) {
      return;
    }
    final convId = _resolvedConversationID();
    final convKey = _getConvID()?.trim() ?? '';
    final reloadTrace = ChatOpenPerfLog.captureCurrent(conversationKey: convKey);
    if (convId.isEmpty ||
        !MessageConversationId.sameConversation(
          ActiveChatRegistry.instance.activeConversationId,
          convId,
        )) {
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final initialLoaded = globalModel.hasInitialHistoryLoaded(convKey);
    final model = _chatController.model;
    // 冷启动首屏由 UIKit hydrate 独占；post_open 不要抢先塞预览消息造成 1→30 抖动。
    if (!initialLoaded) {
      if (model?.isLoadingChatHistory == true) {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_skip_hydrating',
          conversationID: convId,
          extras: <String, Object?>{'reason': reason},
        );
        return;
      }
      if (reason == 'post_open') {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_skip_post_open_cold',
          conversationID: convId,
        );
        return;
      }
    }
    final preview = await _fetchConversationPreviewLastMessage();
    final previewMsgId = preview?.msgID?.trim() ?? '';
    // 已确认空会话（清空记录后标了 empty-loaded、且不再可能有更早历史）
    // 且预览也无消息：没有任何可补拉的内容，跳过 local/cloud 双拉，
    // 避免清空后进页对同一空会话反复 setMessageList 的加载风暴。
    if (preview == null &&
        globalModel.hasInitialHistoryLoaded(convKey) &&
        globalModel.rawMessageCount(convKey) == 0 &&
        !globalModel.mayHaveOlderHistory(convKey)) {
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_skip_confirmed_empty',
        conversationID: convId,
        extras: <String, Object?>{'reason': reason},
      );
      return;
    }
    ChatDiagLog.log(
      'ChatHistory',
      'reload_if_empty_start',
      conversationID: convId,
      extras: <String, Object?>{
        'reason': reason,
        'convKey': convKey,
        'type': _getConvType().name,
        'hasPreviewLastMessage': preview != null,
        'previewMsgId': previewMsgId,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'cachedRaw': serviceLocator<TUIChatGlobalModel>().rawMessageCount(
          convKey,
        ),
        'initialLoaded': serviceLocator<TUIChatGlobalModel>()
            .hasInitialHistoryLoaded(convKey),
      },
    );
    try {
      if (model == null) {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_no_model',
          conversationID: convId,
          extras: <String, Object?>{'reason': reason},
        );
        await _chatController.refreshCurrentHistoryList();
        return;
      }
      // 仅在首屏已加载完成时补预览，避免冷启动先显示 1 条再 hydrate 整页抖动。
      if (preview != null && initialLoaded) {
        final merged = await _mergePreviewMessageIfMissing();
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_preview_merge',
          conversationID: convId,
          extras: <String, Object?>{
            'merged': merged,
            'hasMessages': _hasVisibleHistoryMessages(),
          },
        );
      }
      ChatOpenPerfLog.mark(
        'chat_reload_if_empty_load',
        conversationID: convId,
        extras: <String, Object?>{
          'reason': reason,
          'producer': 'reload_if_empty',
        },
        trace: reloadTrace,
      );
      await model.loadChatRecord(
        count: 20,
        getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      );
      var hasMessages = _hasVisibleHistoryMessages();
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_local_done',
        conversationID: convId,
        extras: <String, Object?>{
          'hasMessages': hasMessages,
          'listLen': model.globalModel.rawMessageCount(convKey),
        },
      );
      if (!hasMessages) {
        // Cloud recovery is owned by ConversationHistorySyncCoordinator.
        // Keep this legacy empty-page hook local-only so it cannot create a
        // second cloud pagination owner beside the open/reconnect pipeline.
        await ConversationHistorySyncCoordinator.instance.verifyAfterFirstFrame(
          conversation: _conversation,
          reason: 'reload_if_empty_$reason',
          delay: Duration.zero,
          logTrace: reloadTrace,
        );
        hasMessages = _hasVisibleHistoryMessages();
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_coordinator_done',
          conversationID: convId,
          extras: <String, Object?>{
            'hasMessages': hasMessages,
            'listLen': model.globalModel.rawMessageCount(convKey),
          },
        );
      }
      if (hasMessages) {
        serviceLocator<TUIChatGlobalModel>().markInitialHistoryLoaded(convKey);
      }
      // 清空后确实无消息：标记 empty-loaded，避免一直 bootstrapping 转圈。
      if (!hasMessages && !globalModel.hasInitialHistoryLoaded(convKey)) {
        final clearedAt =
            await ChatSessionController.instance.historyClearedAtMs(convKey);
        final inGrace = ArchiveHistoryProvider.isInHistoryClearGrace(convKey);
        if (clearedAt > 0 ||
            inGrace ||
            reason == 'return_from_profile' ||
            reason == 'return_from_settings') {
          globalModel.clearLocalHistoryAsEmptyLoaded(convKey);
          if (convId.isNotEmpty && convId != convKey) {
            globalModel.clearLocalHistoryAsEmptyLoaded(convId);
          }
          ChatDiagLog.log(
            'ChatHistory',
            'reload_if_empty_mark_empty_loaded',
            conversationID: convId,
            extras: <String, Object?>{
              'reason': reason,
              'clearedAt': clearedAt,
              'inGrace': inGrace,
            },
          );
        }
      }
    } catch (e) {
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_error',
        conversationID: convId,
        extras: <String, Object?>{'reason': reason, 'error': e.toString()},
      );
      try {
        await _chatController.refreshCurrentHistoryList();
      } catch (_) {}
    }
    ChatDiagLog.log(
      'ChatHistory',
      'reload_if_empty_end',
      conversationID: convId,
      extras: <String, Object?>{
        'reason': reason,
        'hasMessages': _hasVisibleHistoryMessages(),
      },
    );
    if (mounted) {
      setState(() {});
    }
  }
~~~

22. [_ChatState._markChatOpenHistoryReady](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7872>)，原文件 lib/src/chat.dart，7872–7898 行。

~~~dart
void _markChatOpenHistoryReady() {
    if (!_openLifecycle.markHistoryReady(_chatOpenPhaseGeneration)) {
      return;
    }
    ChatOpenPerfLog.mark(
      'chat_open_phase_history_ready_ms',
      extras: <String, Object?>{
        'durationMs': _chatOpenInitStopwatch.elapsedMilliseconds,
        'count': 1,
      },
    );
    final generation = _chatOpenPhaseGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _chatOpenPhaseGeneration) return;
      if (_openLifecycle.markInteractive(generation)) {
        ChatOpenPerfLog.mark(
          'chat_open_phase_interactive_ms',
          extras: <String, Object?>{
            'durationMs': _chatOpenInitStopwatch.elapsedMilliseconds,
            'count': 1,
          },
        );
        _tryMarkChatOpenEnriched();
      }
    });
    _scheduleDeferredHistoryVerification(generation);
  }
~~~

23. [_ChatState._scheduleDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7900>)，原文件 lib/src/chat.dart，7900–7983 行。

~~~dart
/// 首帧前只展示本地 SDK 快照。首帧稳定后由统一 Coordinator 负责云端
  /// 校验、重试和 gap repair；这里不再根据会话预览决定是否同步。
  void _scheduleDeferredHistoryVerification(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _chatOpenPhaseGeneration ||
          !_isCurrentConversation(_resolvedConversationID())) {
        return;
      }
      // DIAG: 首帧稳定后 dump 当前会话元信息 + IM06 scope 状态。
      // 目的：让日志能精准关联到用户看到的会话（如"无边心是岸"）。
      try {
        final convID = _getConvID()?.trim() ?? '';
        final convType = _getConvType();
        final peerID = convType == ConvType.group
            ? (_conversation.groupID?.trim() ?? '')
            : (_conversation.userID?.trim() ?? '');
        final displayName = _conversation.showName?.trim() ??
            widget.selectedConversation.showName?.trim() ??
            '';
        final globalModel = serviceLocator<TUIChatGlobalModel>();
        ChatHistoryTrace.log(
          'diag_chat_open',
          conversationID: convID,
          extras: <String, Object?>{
            'convType': convType.name,
            'peerID': peerID,
            'displayName': displayName,
            'openGeneration': generation,
            'im06ScopeConfigured': globalModel.im06WriterScopeConfigured,
            'im06ScopeOwnerUserID': globalModel.im06WriterOwnerUserID ?? '',
            'im06AccountGen': globalModel.im06WriterAccountGeneration ?? -1,
            'im06DomainGen': globalModel.im06WriterDomainGeneration ?? -1,
          },
        );
      } catch (_) {
        // 诊断日志失败不影响主链路。
      }
      // The remote gate protects only the route's first frame. Release it
      // independently from scroll position so an early upward gesture can
      // always fall through from the local SDK cache to cloud pagination.
      _chatController.model?.allowRemoteHistoryAfterFirstFrame();
      // History verification is the only automatic cloud history task after
      // the first frame. Older group history is loaded only when the user
      // scrolls upward; do not proactively backfill a time window.
      final conversationKey = _getConvID()?.trim() ?? '';
      if (conversationKey.isEmpty) {
        return;
      }
      final globalModel = serviceLocator<TUIChatGlobalModel>();
      final completeLocalWindow =
          ConversationPreviewHistorySync.isCompleteOpenHistoryWindow(
        globalModel: globalModel,
        conversationKey: conversationKey,
      );
      // Thin snapshots need history just as urgently as empty ones. Only a
      // complete first window can defer verification without delaying reveal.
      final previewAhead = ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
        preview: _conversation.lastMessage,
        cached: globalModel.rawMessageList(conversationKey) ?? const <V2TimMessage>[],
      );
      final delay = completeLocalWindow && !previewAhead
          ? const Duration(milliseconds: 700)
          : Duration.zero;
      final verification = _runDeferredHistoryVerification(
        generation: generation,
        conversationKey: conversationKey,
        delay: delay,
        logTrace: ChatOpenPerfLog.captureCurrent(
          conversationKey: conversationKey,
        ),
      );
      // Media prefetch runs after history verification so it cannot compete
      // with the first cloud recovery request for the same conversation.
      unawaited(verification.whenComplete(() {
        if (!mounted ||
            generation != _chatOpenPhaseGeneration ||
            !_isCurrentConversation(_resolvedConversationID())) {
          return;
        }
        unawaited(_prefetchMediaByType());
      }));
    });
  }
~~~

24. [_ChatState._runDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8023>)，原文件 lib/src/chat.dart，8023–8041 行。

~~~dart
Future<void> _runDeferredHistoryVerification({
    required int generation,
    required String conversationKey,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
  }) async {
    final key = '$generation|$conversationKey';
    if (!_pendingDeferredHistoryVerifications.add(key)) return;
    try {
      await _performDeferredHistoryVerification(
        generation: generation,
        conversationKey: conversationKey,
        delay: delay,
        logTrace: logTrace,
      );
    } finally {
      _pendingDeferredHistoryVerifications.remove(key);
    }
  }
~~~

25. [_ChatState._performDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8043>)，原文件 lib/src/chat.dart，8043–8160 行。

~~~dart
Future<void> _performDeferredHistoryVerification({
    required int generation,
    required String conversationKey,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted ||
        generation != _chatOpenPhaseGeneration ||
        !_isCurrentConversation(_resolvedConversationID())) {
      return;
    }
    // P1-1: 软 TTL — 同会话 N 秒内已 verify 过 → 直接 outcome=verified 跳过。
    // 不影响切到其它会话再切回来的场景（TTL 过期后重新 verify）。
    // 使用开区间：now - lastAt ≤ ttlMs 时跳过。
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAt = _lastCloudVerifyAtMs[conversationKey] ?? 0;
    final previewAhead = await _conversationPreviewAheadOfHistory();
    if (!mounted || generation != _chatOpenPhaseGeneration) return;
    final resetService = ChatLatestWindowResetService.instance;
    if (resetService.needsLatestWindowReset(conversationKey) ||
        resetService.isResetInFlight(conversationKey)) {
      // A real reconnect invalidated this conversation's latest window. The
      // reset service owns the cloud request; neither the stale verify TTL
      // nor an ordinary verify pass may run alongside it.
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_deferred_done',
        conversationID: conversationKey,
        extras: <String, Object?>{'outcome': 'latest_window_reset_owner'},
      );
      return;
    }
    if (!previewAhead && lastAt > 0 && now - lastAt <= _cloudVerifySoftTtlMs) {
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_soft_skip',
        conversationID: conversationKey,
        extras: <String, Object?>{
          'ageMs': now - lastAt,
          'ttlMs': _cloudVerifySoftTtlMs,
        },
      );
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_deferred_done',
        conversationID: conversationKey,
        extras: <String, Object?>{'outcome': 'soft_ttl_skip'},
      );
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    while (globalModel.isChatListUserScrolling ||
        globalModel.getMessageListPosition(_resolvedConversationID()) !=
            HistoryMessagePosition.bottom) {
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_requeued_by_user_state',
        conversationID: conversationKey,
      );
      // Keep exactly one bounded retry alive while this route is current.
      // Returning to the newest edge will eventually run verification; if the
      // user keeps reading older history, explicit pagination remains enabled.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted ||
          generation != _chatOpenPhaseGeneration ||
          !_isCurrentConversation(_resolvedConversationID())) return;
    }
    ChatOpenPerfLog.mark(
      'chat_open_cloud_verify_deferred_start',
      conversationID: conversationKey,
      extras: <String, Object?>{
        'rawCount': globalModel.rawMessageCount(conversationKey),
        'mayHaveOlder': globalModel.mayHaveOlderHistory(conversationKey),
      },
      trace: logTrace,
    );
    final verificationIdentity = SessionIdentityService.instance.capture();
    final latestPreview = await _fetchConversationPreviewLastMessage();
    if (!mounted ||
        generation != _chatOpenPhaseGeneration ||
        !SessionIdentityService.instance.isCurrent(verificationIdentity)) return;
    final verificationConversation =
        V2TimConversation.fromJson(_conversation.toJson())
          ..lastMessage = latestPreview;
    final outcome =
        await ConversationHistorySyncCoordinator.instance.verifyAfterFirstFrame(
      conversation: verificationConversation,
      reason: 'chat_open',
      delay: Duration.zero,
      logTrace: logTrace,
      boundOpenGeneration: _viewportOpenGeneration,
    );
    // P1-1: 验证完成 → 记 lastAt，下一次进入走软 TTL。
    // 只有 server sync 已完成且传输在线时，这次 verified 才有资格写 TTL；
    // 握手/漫游同步期间的 CLOUD 结果可能是本地降级，不能补发认证。
    if (mounted &&
        generation == _chatOpenPhaseGeneration &&
        outcome == ConversationHistorySyncOutcome.verified &&
        ChatHistoryVerificationGate.canMarkCloudVerifiedNow()) {
      _lastCloudVerifyAtMs[conversationKey] =
          DateTime.now().millisecondsSinceEpoch;
    }
    // DIAG: 校验出口 — 记录 outcome / SDK commit 后是否真的写入了 messageList。
    ChatHistoryTrace.log(
      'diag_verify_outcome',
      conversationID: conversationKey,
      extras: <String, Object?>{
        'outcome': outcome.name,
        'rawCountAfter': globalModel.rawMessageCount(conversationKey),
        'mayHaveOlderAfter': globalModel.mayHaveOlderHistory(conversationKey),
        'haveMoreData': _chatController.model?.haveMoreData ?? false,
      },
    );
    ChatHistoryTrace.log(
      'chat_open_cloud_verify_deferred_done',
      conversationID: conversationKey,
      extras: <String, Object?>{'outcome': outcome.name},
    );
  }
~~~

26. [_ChatState._schedulePostOpenTasks](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8242>)，原文件 lib/src/chat.dart，8242–8443 行。

~~~dart
void _schedulePostOpenTasks() {
    if (_openLifecycle.postOpenTasksScheduled) return;
    final taskGeneration = _openLifecycle.beginPostOpenTasks();
    final schedulerGeneration = _postOpenScheduler.beginRun();
    final scheduledConversationId = _resolvedConversationID();
    final scheduledConvKey = _getConvID()?.trim() ?? scheduledConversationId;

    bool canRun() {
      return taskGeneration == _openLifecycle.postOpenTasksGeneration &&
          _isCurrentConversation(scheduledConversationId);
    }

    Future<void> runTasks() async {
      if (!canRun()) return;
      await _openLifecycle.waitForOpenHistoryPreparationGate();
      if (!canRun()) return;
      ChatOpenPerfLog.mark(
        'post_open_tasks_run',
        extras: <String, Object?>{'isGroup': _getConvType() == ConvType.group},
      );
      ChatJitterDiag.log(
        'post_open_tasks',
        extras: const <String, Object?>{'source': 'route_animation_or_delay'},
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'local_foundation',
        delay: Duration.zero,
        canRun: canRun,
        task: () async {
          await Future.wait<void>(<Future<void>>[
            _loadChatBackground(),
            _loadChatLocalDraft(),
            _hydrateGroupDisplayForOpen(),
            _resolveImGroupIdAfterOpen(),
          ]);
          if (canRun()) {
            await _prepareOfficialAccountChat();
          }
          if (canRun() && _getConvType() == ConvType.c2c) {
            await Future.wait<void>(<Future<void>>[
              _loadPeerFaceUrl(),
              _loadPeerLocalProfile(),
            ]);
            if (canRun()) {
              _schedulePeerMessagePermissionSync(forceNetwork: true);
            }
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'history_enrichment',
        delay: ChatPostOpenScheduler.p1Delay,
        canRun: canRun,
        task: () => _runOpenHistoryEnrichment(scheduledConvKey, canRun: canRun),
      );
      if (_getConvType() == ConvType.group) {
        final groupId = ChatIdFormat.normalizeGroupId(
          widget.selectedConversation.groupID,
        );
        if (groupId.isNotEmpty) {
          // 与进页成员最小集错峰；本地已 seed 时只做权威补证。
          final muteGeneration = _openLifecycle.muteFetchGeneration;
          _postOpenScheduler.schedule(
            generation: schedulerGeneration,
            key: 'mute_status',
            delay: ChatPostOpenScheduler.muteNetworkDelay,
            canRun: canRun,
            task: () async {
              if (!mounted ||
                  muteGeneration != _openLifecycle.muteFetchGeneration) {
                return;
              }
              ChatOpenPerfLog.mark('mute_network_fetch_start');
              await _fetchAndStoreBackendMuteStatus(groupId);
              if (canRun()) {
                _markChatOpenBackgroundPart(
                  part: 'mute',
                  generation: taskGeneration,
                );
              }
            },
          );
        } else {
          _markChatOpenBackgroundPart(part: 'mute', generation: taskGeneration);
        }
      }
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'group_metadata',
        // Group metadata is enrichment, never a chat first-frame dependency.
        delay: ChatPostOpenScheduler.idleDelay,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          if (_getConvType() != ConvType.group) {
            _markChatOpenBackgroundPart(
              part: 'c2c',
              generation: taskGeneration,
            );
            return;
          }
          await _runOpenGroupMetadataEnrichment(
            generation: taskGeneration,
            canRun: canRun,
          );
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'business_enrichment',
        delay: const Duration(milliseconds: 650),
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          await Future.wait<void>(<Future<void>>[
            _loadGroupGameStatus(),
            _loadAgentRebateIdentity(),
            _loadSangongAgentEntry(),
            _loadGroupLiveCurrent(),
          ]);
          if (canRun()) {
            _markChatOpenBackgroundPart(
              part: 'group_game',
              generation: taskGeneration,
            );
            if (_getConvType() == ConvType.group) {
              _startGroupLiveCurrentPoll();
            }
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'idle_enrichment',
        delay: ChatPostOpenScheduler.idleDelay,
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          final idleTasks = <Future<void>>[
            DiceAssetWarmup.warm(context),
            _retryWalletCardsForConversation(
              source: WalletCardSendSource.autoRetry,
            ),
            if (!CallLifecycleService.instance.isInActiveCall)
              SoundPlayer.ensurePlaybackReady(),
          ];
          await Future.wait<void>(idleTasks);
          if (!canRun()) return;
          if (!_hasVisibleHistoryMessages()) {
            await _reloadChatHistoryIfEmpty(reason: 'post_open');
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'group_feature_idle',
        delay: const Duration(milliseconds: 900),
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun() || _getConvType() != ConvType.group) return;
          // Member verification and feature APIs share an idle lane and are
          // intentionally independent of chat history/readback. Their
          // failures must not delay the message list or trigger a reload.
          if (canRun()) {
            await _verifyGroupMembershipOnOpen();
          }
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation != null && !animation.isCompleted) {
        void listener(AnimationStatus status) {
          if (status != AnimationStatus.completed &&
              status != AnimationStatus.dismissed) {
            return;
          }
          _removeRouteTransitionListener(animation, listener);
          if (status == AnimationStatus.completed) {
            unawaited(runTasks());
          }
        }

        _addRouteTransitionListener(animation, listener);
        return;
      }
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'route_fallback',
        delay: ChatPostOpenScheduler.routeFallbackDelay,
        canRun: canRun,
        task: runTasks,
      );
    });
  }
~~~

27. [_ChatState.initState](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9199>)，原文件 lib/src/chat.dart，9199–9614 行。

~~~dart
@override
  void initState() {
    super.initState();
    // The resolved SDK conversation id can become available after the first
    // history frame. Keep the widget identity tied to the route entry so that
    // that metadata update does not remount the entire message surface.
    final entryConversationId = _getConvID()?.trim() ?? '';
    _stableChatWidgetKey = entryConversationId.isNotEmpty
        ? entryConversationId
        : 'chat_${widget.selectedConversation.type}_'
            '${widget.selectedConversation.userID ?? widget.selectedConversation.groupID ?? widget.selectedConversation.conversationID}';
    PerfTimeline.instant('chat_page_open', arguments: {
      'conversationId': widget.selectedConversation.conversationID,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PerfTimeline.instant('chat_page_first_frame', arguments: {
          'conversationId': _resolvedConversationID(),
        });
      }
    });
    // Pipeline [4] - init_begin：ChatState initState 入口（用 widget 原 conv 拼 key）
    final initPipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.selectedConversation.conversationID,
      userId: widget.selectedConversation.userID,
      groupId: widget.selectedConversation.groupID,
    );
    ChatPipelineClock.instance.trace(initPipelineKey, 'init_begin');
    WidgetsBinding.instance.addObserver(this);
    _chatOpenInitStopwatch.start();
    _c2cPermission.onTransitionToBlocked = _syncInFlightOutgoingOnC2cBlocked;
    _groupLiveState.addListener(_onGroupLiveStateChanged);
    GroupLiveIndexStore.instance.addListener(_onGroupLiveIndexStoreChanged);
    GroupLocalStore.instance.commitListenable.addListener(_onGroupStoreCommit);
    GroupLocalStore.instance.cacheHydration.addListener(_onGroupCacheHydrated);
    GroupMemberLocalStore.instance.commitListenable
        .addListener(_onGroupMemberStoreCommit);
    _openLifecycle.clearedExternalEntryOnDeactivate = false;
    ConversationDeletedBus.instance.revision.addListener(
      _onConversationDeletedBus,
    );
    _conversation = _normalizedConversationForChat(widget.selectedConversation);
    _applyCachedAgentRebateIdentityForCurrentGroup();
    _applyCachedGroupGameForCurrentGroup();
    _beginChatOpenGeneration();
    _firstViewportWindowLogged = false;
    _chatOpenPhaseGeneration = _openLifecycle.beginConversation();

    if (_getConvType() == ConvType.c2c) {
      final peerId = widget.selectedConversation.userID?.trim() ?? '';
      if (peerId.isNotEmpty) {
        _peerLocalProfile = UserProfileLocalService.instance.readCached(peerId);
        final cachedFace = UserAvatarHelper.usableAvatarOrEmpty(
          _peerLocalProfile?.avatarUrl,
        );
        if (cachedFace.isNotEmpty) {
          _resolvedPeerFaceUrl = cachedFace;
          _resolvedPeerFaceUrlForId = peerId;
          _conversation.faceUrl = cachedFace;
          widget.selectedConversation.faceUrl = cachedFace;
        }
      }
    }
    final openedConversationId = _resolvedConversationID();
    _pageScope = ChatPageScope.instance.attach(
      conversationId: openedConversationId,
      accountGeneration: SessionIdentityService.instance.generation,
    );
    final viewportKey = _getConvID()?.trim().isNotEmpty == true
        ? _getConvID()!.trim()
        : openedConversationId;
    if (viewportKey.isNotEmpty) {
      ChatViewportCollection.instance.attach(
        conversationKey: viewportKey,
        identity: SessionIdentityService.instance.capture(),
        attachSource: 'chat_init',
      );
      _viewportConversationKey = viewportKey;
      _viewportOpenGeneration = ChatViewportCollection.instance.openGeneration;
    }
    ChatImageMessagePrefetch.bindPageScope(_pageScope);
    final openConvKey = _getConvID()?.trim() ?? '';
    final openPreview = widget.selectedConversation.lastMessage;
    final openGlobal = serviceLocator<TUIChatGlobalModel>();
    final openWarm = openConvKey.isEmpty
        ? const <V2TimMessage>[]
        : (openGlobal.messageListMap[openConvKey] ?? const <V2TimMessage>[]);
    final openWarmNewest =
        openWarm.isEmpty ? 0 : (openWarm.first.timestamp ?? 0);
    final openWarmOldest =
        openWarm.isEmpty ? 0 : (openWarm.last.timestamp ?? 0);
    ChatDiagLog.log(
      'ChatHistory',
      'chat_open',
      conversationID: openedConversationId,
      extras: <String, Object?>{
        'convKey': openConvKey,
        'type': _getConvType().name,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'hasLastMessage': openPreview != null,
        'lastMsgId': openPreview?.msgID?.trim() ?? '',
        'cachedRaw':
            openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
        'initialLoaded': openConvKey.isEmpty
            ? false
            : openGlobal.hasInitialHistoryLoaded(openConvKey),
        'warmNewestTs': openWarmNewest,
        'warmOldestTs': openWarmOldest,
        'warmNewestId':
            openWarm.isEmpty ? '' : (openWarm.first.msgID?.trim() ?? ''),
        'rawAlsoCached':
            openedConversationId.isEmpty || openedConversationId == openConvKey
                ? 0
                : openGlobal.rawMessageCount(openedConversationId),
      },
    );
    ChatOpenPerfLog.mark(
      'chat_init_state',
      conversationID:
          openConvKey.isNotEmpty ? openConvKey : openedConversationId,
      extras: <String, Object?>{
        'type': _getConvType().name,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'cachedRaw':
            openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
        'initialLoaded': openConvKey.isEmpty
            ? false
            : openGlobal.hasInitialHistoryLoaded(openConvKey),
        'warmNewestTs': openWarmNewest,
        'isGroup': _getConvType() == ConvType.group,
      },
    );
    ChatJitterDiag.markChatOpen(
      openConvKey.isNotEmpty ? openConvKey : openedConversationId,
    );
    ChatResourceSample.resetForChatOpen(
      openConvKey.isNotEmpty ? openConvKey : openedConversationId,
    );
    // 首屏窗口已在内存时立刻尝试 100/500/1000 节点（不等上翻）。
    final openCount =
        openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey);
    if (openCount > 0) {
      ChatResourceSample.onRawMessageCount(openCount);
    }
    ConversationUnreadClearService.beginConversationChatSession(
      openedConversationId,
    );
    // Deep link / push / restart 这类入口绕过了会话列表点击预热；
    // 在 initState 同步注册同样的 in-flight 任务，让首帧尽量命中本地缓存。
    // in-flight 由 ChatOpenViewportCoordinator 保证去重，与 app_chat_route
    // 的 await 预热天然合并。搜索/找消息场景走的是另一个特殊路径，跳过。
    if (widget.initFindingMsg == null &&
        widget.searchJumpAnchor == null &&
        openedConversationId.isNotEmpty &&
        ConversationPeekService.canPeek(_conversation)) {
      unawaited((() async {
        await ChatOpenViewportCoordinator.instance.prepareOpenViewport(
          conversation: _conversation,
          source: 'chat_init',
        );
        if (!mounted) {
          return;
        }
        _onChatGlobalModelChanged();
      })());
    }
    if (openedConversationId.isNotEmpty) {
      ActiveChatRegistry.instance.enter(
        openedConversationId,
        conversationType: _getConvType(),
      );
      ExternalChatEntryService.instance.claimActiveChatSource(
        _externalEntrySourceToken,
      );
    }
    DeviceSyncService.instance.prepareForChatNavigation();
    DeviceSyncService.instance.beginForegroundMediaWork(
      reason: 'chat_open',
      duration: const Duration(seconds: 3),
    );
    _cachedHeaderFaceUrl = _conversation.faceUrl;
    _cachedHeaderShowName = _conversation.showName;
    if (_getConvType() == ConvType.group) {
      _logGroupHeaderAvatarSource(
        source: 'selected_conversation',
        currentFaceUrl: '',
        candidateFaceUrl: _conversation.faceUrl ?? '',
        applied: true,
      );
    }
    _applyInitialC2cPermissionHint(resetIfMissing: true);
    _seedGroupDisplayFromMemory();
    _armOpenGroupNoticeAfterTransition();
    _syncChatHeaderState(notify: false);
    _seedGroupLiveFromIndex();
    _syncChatTopFixState(notify: false);
    _stopGroupLiveCurrentPoll();
    _clearMountedDisplayListCache();
    if (openedConversationId.isNotEmpty) {
      unawaited(
        ImChatNotificationClearService.instance
            .clearChatNotificationsForConversation(
          openedConversationId,
          reason: 'chat_open',
        ),
      );
    }
    _schedulePostOpenFailedMessageRetry();
    final convId = _getConvID()?.trim() ?? '';
    if (convId.isNotEmpty) {
      PushFocusService.instance.enterChat(
        conversationType: _getConvType(),
        peerOrGroupId: convId,
      );
    }
    // Pipeline [5] - init_done：ChatState initState 同步段结束
    ChatPipelineClock.instance.trace(
      _resolvedConversationID(),
      'init_done',
      elapsedMs: _chatOpenInitStopwatch.elapsedMilliseconds,
    );
    // 生命周期回调可能在路由切换后才返回；草稿清理必须绑定本次打开的
    // 会话，不能在回调时重新取“当前会话”，否则 A 发送成功会清掉 B 草稿。
    final lifecycleConversationId = _resolvedConversationID();
    _chatLifeCycle = ChatLifeCycle(
      newMessageWillMount: (V2TimMessage message) async {
        _handleGroupLiveIncomingMessage(message);
        unawaited(
          MessageMediaMetadataStore.instance.upsertFromMessage(message),
        );
        if (_getConvType() == ConvType.c2c) {
          ChatImageMessagePrefetch.prefetchThumbnailForMessage(message);
        }
        if (ChatImageMessagePrefetch.needsOnlineUrlResolution(
          message,
          includeSelf: true,
        )) {
          unawaited(
            ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(
              <V2TimMessage>[message],
              includeSelf: true,
            ),
          );
        }
        return message;
      },
      didGetHistoricalMessageList: (List<V2TimMessage> messageList) async {
        _completeChatOpenInitStage(
          _ChatOpenInitStage.sdkReady,
          count: messageList.length,
          source: 'sdk_history_callback',
        );
        // Media metadata, sticker scans and image prefetch are enrichment.
        // Keep the history callback limited to the authoritative list commit.
        _pendingOpenHistoryMediaEnrichment = messageList;
        // C2C/group histories can contain both the server lk_call terminal
        // message and our local terminal projection for the same callId.
        // Normalize call candidates on every conversation type so those two
        // sources converge before the first history frame is mounted.
        final normalized = CallBubbleDedupe.normalizeCallHistoryMessages(
          messageList,
          preserveTipIdentity: true,
        );
        final deduped = TUIChatGlobalModel.dedupeMessages(normalized);
        _completeChatOpenInitStage(
          _ChatOpenInitStage.historyReady,
          count: deduped.length,
          source: 'sdk_history_commit',
        );
        _markChatOpenHistoryReady();
        RegExpProbe.dump(reason: 'didGetHistoricalMessageList');
        return deduped;
      },
      messageShouldMount: _messageShouldMountInHistory,
      messageListShouldMount: _normalizeMessageListForMount,
      messageDidSend: (sendMsgRes) {
        final conversationId = lifecycleConversationId.isNotEmpty
            ? lifecycleConversationId
            : _resolvedConversationID();
        if (sendMsgRes.code == 0 && conversationId.isNotEmpty) {
          unawaited(_clearChatLocalDraftAfterSend(conversationId));
        }
        // 己方发送不走通知侧 patch；SDK onConversationChanged 若因群 ID
        // 形态/非成员门禁落库失败，列表预览会空，再进页会误标 empty-loaded。
        if (sendMsgRes.code == 0 && conversationId.isNotEmpty) {
          final sent = sendMsgRes.data;
          OutgoingVisibleProbe.log(
            'send_preview_patch_start',
            conversationID: conversationId,
            message: sent,
            extras: <String, Object?>{
              'hasData': sent != null,
              'code': sendMsgRes.code,
            },
          );
          unawaited(
            () async {
              // 好友刚通过时，本地乐观会话与 SDK 建会话存在竞态。己方首条
              // 消息又不会走 onRecvNewMessage，因此不能只等待 SDK 的
              // onConversationChanged；否则返回列表后可能一直没有该会话。
              if (sent != null) {
                unawaited(
                  MessageMediaMetadataStore.instance.upsertFromMessage(sent),
                );
                if (ChatImageMessagePrefetch.needsOnlineUrlResolution(
                  sent,
                  includeSelf: true,
                )) {
                  unawaited(
                    ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(
                      <V2TimMessage>[sent],
                      includeSelf: true,
                    ),
                  );
                }
                await ChatSessionController.instance
                    .patchConversationLastMessage(
                  conversationID: conversationId,
                  message: sent,
                );
                OutgoingVisibleProbe.log(
                  'send_preview_patch_done',
                  conversationID: conversationId,
                  message: sent,
                );
              } else {
                // Rare SDK success responses without message data cannot be
                // patched optimistically. Use one authoritative fallback.
                await ChatSessionController.instance.refreshConversationItem(
                  conversationId,
                );
              }
              // The optimistic preview patch already queries the SDK once
              // and can create a local shell when the SDK conversation is
              // still racing the first send. The ordinary SDK conversation
              // callback supplies the later authoritative metadata; issuing
              // another query plus RefreshBus query here tripled the work for
              // every successful send.
            }()
                .catchError((Object error, StackTrace stack) {
              OutgoingVisibleProbe.log(
                'send_preview_patch_error',
                conversationID: conversationId,
                extras: <String, Object?>{'error': '$error'},
              );
            }),
          );
        }
      },
    );
    // Telegram-style stable surface: the real chat tree exists on the first
    // route frame. History readiness is represented inside that tree.
    _mountStableChatBody(openConvKey: openConvKey);
    _ensureMessageItemBuilder();
    _chatGlobalModel = serviceLocator<TUIChatGlobalModel>();
    _chatGlobalModel!.addListener(_onChatGlobalModelChanged);
    _conversationViewModel.addListener(_onConversationViewModelChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    serviceLocator<TUIFriendShipViewModel>().addListener(
      _onFriendshipModelChanged,
    );
    GroupMemberStore.instance.addListener(_onGroupMemberStoreChanged);
    unawaited(_loadPeerFaceUrl());
    unawaited(_loadPeerLocalProfile());
    WalletOrderEvents.chatCardPayload.addListener(_onWalletChatCard);
    WalletOrderEvents.chatCardSendFailedPayload.addListener(
      _onWalletChatCardSendFailed,
    );
    CallResultRepository.instance.revision.addListener(
      _onCallResultRepositoryChanged,
    );
    ChatHistoryRefreshBus.instance.revision.addListener(
      _onExternalChatHistoryRefreshRequested,
    );
    GroupNoticeRefreshBus.instance.lastRefresh.addListener(
      _onGroupNoticeRefreshRequested,
    );
    GroupSyncService.instance.lastChanged.addListener(_onGroupRealtimeChanged);
    ConversationHistoryWarmScheduler.instance.pauseForActiveChat(
      reason: 'chat_open',
    );
    // 轻壳首帧就尽量带上真实聊天背景，避免转场结束后再换底。
    unawaited(_prefetchShellBackground());
    _schedulePostOpenTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ChatOpenPerfLog.mark(
        'chat_first_frame',
        conversationID:
            openConvKey.isNotEmpty ? openConvKey : openedConversationId,
        extras: <String, Object?>{
          'rawCount':
              openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
          'gateActive': _openLifecycle.openHistoryGate != null,
        },
      );
      _attachLocalSettingListener();
      _publishExternalEntryState();
      unawaited(_activatePendingExternalEntryOnInit());
      final openConvResolved = _resolvedConversationID();
      if (openConvResolved.isNotEmpty) {
        CallBubbleInsertService.instance.ensureConversationBubbles(
          openConvResolved,
          reason: 'chat_open',
        );
      }
      _schedulePeerMessagePermissionSync(
        forceNetwork: _c2cPermission.trustedInitialCanMessage,
      );
    });
    // if (IMDemoConfig.customerServiceUserList.contains(widget.selectedConversation.userID)) {
    //   TencentCloudChatCustomerServicePlugin.sendCustomerServiceStartMessage(_chatController.sendMessage);
    // }
  }
~~~

28. [_ChatState.deactivate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9674>)，原文件 lib/src/chat.dart，9674–9703 行。

~~~dart
@override
  void deactivate() {
    final route = ModalRoute.of(context);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final leaveId = _resolvedConversationID();
    OutgoingVisibleProbe.log(
      'chat_deactivate',
      conversationID: leaveId,
      extras: <String, Object?>{
        'routeCurrent': route?.isCurrent,
        'mediaPreview': globalModel.isMediaPreviewOverlayOpen,
        'walletOverlay': globalModel.isWalletOverlayOpen,
        'pickerOverlay': globalModel.isMediaPickerOverlayOpen,
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(leaveId),
        ),
      },
    );
    if (route != null &&
        !route.isCurrent &&
        !globalModel.isMediaPreviewOverlayOpen &&
        !globalModel.isWalletOverlayOpen &&
        !globalModel.isMediaPickerOverlayOpen) {
      // 被资料/代理页盖住：栈内仍开着 Chat，只标不可见，不 leave、不清未读、不交还列表。
      ActiveChatRegistry.instance.updateRouteVisible(false);
      _dismissChatInput();
      unawaited(_persistChatLocalDraft());
    }
    super.deactivate();
  }
~~~

29. [_ChatState.dispose](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9779>)，原文件 lib/src/chat.dart，9779–9947 行。

~~~dart
@override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _mobileCommitGuard.advancePage();
    _chatOpenGeneration++;
    ChatImageMessagePrefetch.cancelForPageDispose();
    ChatPageScope.instance.invalidate(_pageScope);
    _pageScope = null;
    final viewportKey = _viewportConversationKey;
    if (viewportKey != null && viewportKey.isNotEmpty) {
      ChatViewportCollection.instance.detachUi(
        conversationKey: viewportKey,
        openGeneration: _viewportOpenGeneration,
      );
    }
    _pendingOpenHistoryMediaEnrichment = null;
    ConversationDeletedBus.instance.revision.removeListener(
      _onConversationDeletedBus,
    );
    // 真正离页时再腾出气泡位图并预热列表头像（勿放 deactivate：进资料页也会覆盖路由）。
    _cancelChatOpenSideEffects(reason: 'chat_dispose');
    _clearRouteTransitionListeners();
    final gateConv = _openLifecycle.openHistoryGateConvKey;
    if (gateConv.isNotEmpty) {
      ChatHistoryOpenLayoutReady.cancel(gateConv);
    }
    _openLifecycle.resetForDispose();
    _releaseBubbleCacheAndWarmListAvatar();
    ChatJitterDiag.logImageCache('chat_dispose');
    // Persist the draft before handing the conversation back to the list.
    // The old fire-and-forget ordering let the list refresh against the
    // previous snapshot, so the draft disappeared until the chat was opened
    // again and loaded directly from the draft store.
    final draftPersist = _persistChatLocalDraft();
    _draft.dispose();
    _headerState.dispose();
    _groupLiveState.removeListener(_onGroupLiveStateChanged);
    GroupLiveIndexStore.instance.removeListener(_onGroupLiveIndexStoreChanged);
    GroupLocalStore.instance.commitListenable.removeListener(
      _onGroupStoreCommit,
    );
    GroupLocalStore.instance.cacheHydration.removeListener(
      _onGroupCacheHydrated,
    );
    GroupMemberLocalStore.instance.commitListenable
        .removeListener(_onGroupMemberStoreCommit);
    _stopGroupLiveCurrentPoll();
    _groupLiveState.dispose();
    _topFixState.dispose();
    _peerPermissionSyncDebounce?.cancel();
    _c2cPermission.nextRequestSeq();
    _c2cPermission.dispose();
    _lastCloudVerifyAtMs.clear();
    final convType = _getConvType();
    final convId = _getConvID()?.trim() ?? '';
    final leaveConversationId = _resolvedConversationID();
    ConversationHistorySyncCoordinator.instance.cancelConversation(
      leaveConversationId,
    );
    OutgoingVisibleProbe.log(
      'chat_dispose',
      conversationID: leaveConversationId,
      extras: OutgoingVisibleProbe.trackedInList(
        serviceLocator<TUIChatGlobalModel>().rawMessageList(
          leaveConversationId.isNotEmpty ? leaveConversationId : convId,
        ),
      ),
    );
    if (leaveConversationId.isNotEmpty) {
      unawaited(
        ConversationUnreadClearService.finalizeConversationLeaveOnce(
          conversationID: leaveConversationId,
          lastMessageId: _lastVisibleMessageIdForLeave(),
          entryUnreadCount: widget.entryUnreadCount ?? 0,
          markViewModelReadLocally:
              _conversationViewModel.markConversationReadLocally,
        ),
      );
    }
    if (convId.isNotEmpty) {
      PushFocusService.instance.leaveChat(
        chatType: convType == ConvType.group ? 'group' : 'c2c',
        peerOrGroupId: convId,
      );
    }
    // Fix unread-list-doesnt-update-on-return: ensure the registry flushes
    // before any later dispose step can throw and orphan _conversationId.
    // When the route leaves, downstream UI projection would otherwise stay
    // stuck behind `deferTabStoreProjectionWhileActiveChat` until the next
    // chat_leave flush, but that flush never comes when dispose itself is
    // the only signal that the chat is gone.
    if (leaveConversationId.isNotEmpty) {
      ConversationDraftLeaveTrace.focus(leaveConversationId);
      ConversationDraftLeaveTrace.stage(
        'chat_pop',
        conversationId: leaveConversationId,
        extras: const <String, Object?>{'hasOpenChat': true},
      );
      ActiveChatRegistry.instance.leave(leaveConversationId);
      unawaited(
        draftPersist.whenComplete(() {
          _flushConversationListUiAfterChatLeave(
            reason: 'chat_dispose_leave_after_draft',
            leftConversationId: leaveConversationId,
          );
        }),
      );
    }
    _chatGlobalModel?.removeListener(_onChatGlobalModelChanged);
    _chatGlobalModel = null;
    _clearMountedDisplayListCache();
    if (!_openLifecycle.clearedExternalEntryOnDeactivate) {
      _clearExternalEntryState();
    }
    DeviceSyncService.instance.onChatClosed();
    DeviceSyncService.instance.endForegroundMediaWork(
      reason: 'chat_open_dispose',
      cooldown: const Duration(seconds: 3),
    );
    _dismissChatInput();
    _conversationViewModel.removeListener(_onConversationViewModelChanged);
    PeerProfileRefreshBus.instance.revision.removeListener(
      _onPeerProfileRefresh,
    );
    serviceLocator<TUIFriendShipViewModel>().removeListener(
      _onFriendshipModelChanged,
    );
    GroupMemberStore.instance.removeListener(_onGroupMemberStoreChanged);
    WalletOrderEvents.chatCardPayload.removeListener(_onWalletChatCard);
    WalletOrderEvents.chatCardSendFailedPayload.removeListener(
      _onWalletChatCardSendFailed,
    );
    CallResultRepository.instance.revision.removeListener(
      _onCallResultRepositoryChanged,
    );
    ChatHistoryRefreshBus.instance.revision.removeListener(
      _onExternalChatHistoryRefreshRequested,
    );
    GroupNoticeRefreshBus.instance.lastRefresh.removeListener(
      _onGroupNoticeRefreshRequested,
    );
    GroupSyncService.instance.lastChanged.removeListener(
      _onGroupRealtimeChanged,
    );
    _reconnectRecoveryTimer?.cancel();
    _groupMemberAvatarRefreshDebounce?.cancel();
    _postOpenScheduler.dispose();
    _releaseSangongRealtimeSubscription();
    _localSetting?.removeListener(_onLocalSettingChanged);
    // registry leave + UI flush already ran earlier (chat_dispose_leave_early);
    // the release handle here only schedules background post-pop work.
    final releaseConvId = leaveConversationId;
    if (releaseConvId.isNotEmpty) {
      ChatSessionController.instance.schedulePostPopCoalesceWindow(
        conversationID: releaseConvId,
      );
      ConversationHistoryWarmScheduler.instance.scheduleReleaseAfterChatLeave(
        releaseConvId,
      );
    }
    _chatController.model?.disableVoiceAutoPlayChain();
    unawaited(SoundPlayer.stop());
    OrphanOverlayGuard.scheduleCleanup(
      reason: 'chat_leave_dispose',
      hideLoading: true,
    );
    super.dispose();
  }
~~~

30. [_ChatState.didUpdateWidget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:10653>)，原文件 lib/src/chat.dart，10653–10781 行。

~~~dart
@override
  void didUpdateWidget(Chat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConversationID = _resolvedConversationID(
      oldWidget.selectedConversation,
    );
    final newConversationID = _resolvedConversationID(
      widget.selectedConversation,
    );
    if (oldConversationID != newConversationID) {
      final oldInputText =
          _chatController.textFieldController?.textEditingController?.text ??
              '';
      if (!_draft.shouldSuppressLifecyclePersist &&
          oldConversationID.isNotEmpty) {
        _draft.cancelDebounce();
        unawaited(
          _persistChatLocalDraftText(
            oldInputText,
            _draft.writeGeneration,
            conversationID: oldConversationID,
            enforceCurrentGeneration: false,
          ),
        );
      }
      _draft.beginConversation();
      _mobileCommitGuard.advanceConversation();
      _beginChatOpenGeneration();
      _chatOpenPhaseGeneration = _openLifecycle.beginConversation();
      _chatOpenCompletedStages.clear();
      _chatOpenBackgroundParts.clear();
      _pendingOpenHistoryMediaEnrichment = null;
      _chatOpenInitStopwatch
        ..reset()
        ..start();
      final oldGroupId = oldWidget.selectedConversation.groupID?.trim() ?? '';
      ConversationHistorySyncCoordinator.instance.cancelConversation(
        oldConversationID,
      );
      if (oldGroupId.isNotEmpty) {
        GroupMetadataRefreshCoordinator.instance.invalidate(oldGroupId);
      }
      _groupMemberCountGeneration++;
      _lastGroupMetadataRefreshAt = null;
      _clearExternalEntryState(oldConversationID);
      _openLifecycle.cancelPendingMuteFetch();
      _openLifecycle.scheduledVisibleSdkUnreadClean = false;
      _lastPublishedExternalEntryState = null;
      _chatController.model?.disableVoiceAutoPlayChain();
      unawaited(SoundPlayer.stop());
      ActiveChatRegistry.instance.enter(
        _resolvedConversationID(),
        conversationType: _getConvType(),
      );
      ConversationHistoryWarmScheduler.instance.pauseForActiveChat(
        reason: 'chat_switch',
      );
      _conversation = _normalizedConversationForChat(
        widget.selectedConversation,
      );
      _cachedHeaderFaceUrl = _conversation.faceUrl;
      _cachedHeaderShowName = _conversation.showName;
      _groupMemberCount = null;
      _groupMemberCountPinnedToLocalSnapshot = false;
      // 首屏同步：用本地缓存喂 _groupSide，避免首屏不显浮窗。
      final newGroupIdForRebate =
          widget.selectedConversation.groupID?.trim() ?? '';
      if (newGroupIdForRebate.isNotEmpty) {
        final rebateCached = AgentRebateEntryLocalStore.instance.readCachedSync(
          ownerUserId: ContactSocialCacheStore.safeLoginUserId(),
          groupId: newGroupIdForRebate,
        );
        if (rebateCached != null) {
          _groupSide.agentRebateGroupBound = rebateCached.bound;
          _groupSide.agentRebateGroupEnabled = rebateCached.enabled;
          _groupSide.agentRebateIdentityEnabled = rebateCached.isAgent;
        } else {
          _groupSide.agentRebateGroupBound = false;
          _groupSide.agentRebateGroupEnabled = false;
          _groupSide.agentRebateIdentityEnabled = false;
        }
      } else {
        _groupSide.agentRebateGroupBound = false;
        _groupSide.agentRebateGroupEnabled = false;
        _groupSide.agentRebateIdentityEnabled = false;
      }
      _groupSide.groupNoticeBanner = '';
      _openGroupNoticeAfterTransitionInFlight = null;
      // Plan 095：切会话时清空旧群的三公/游戏状态，防止旧群的网络结果
      // 晚到后把 sangongTenantId / canEditConfig 等写入新会话。
      _groupSide.clearSangongAccess();
      _groupSide.disableGroupGame();
      _applyCachedGroupGameForCurrentGroup();
      _watchingGroupLive = false;
      _groupLiveIndexFingerprint = null;
      _seedGroupDisplayFromMemory();
      _armOpenGroupNoticeAfterTransition();
      _seedGroupLiveFromIndex();
      _syncChatTopFixState();
      _stopGroupLiveCurrentPoll();
      _resolvedPeerFaceUrl = null;
      _resolvedPeerFaceUrlForId = null;
      _peerLocalProfile = null;
      _c2cPermission.canMessage = null;
      _c2cPermission.trustedInitialCanMessage = false;
      _c2cPermission.requestSeq++;
      _applyInitialC2cPermissionHint(resetIfMissing: true);
      final peer = _c2cPeerUserId();
      if (peer != null && !_c2cPermission.trustedInitialCanMessage) {
        C2cFriendMessageGuard.invalidate(peer);
      }
      _syncChatHeaderState();
      // Peer/network enrichment is restarted by the bounded post-open queue.
      _resetWalletCardState();
      _ensureMessageItemBuilder();
      _invalidateChatConfigCache();
      final newConvKey = _getConvID()?.trim() ?? '';
      _startOpenHistoryGate(newConvKey);
    }
    if (oldConversationID != newConversationID ||
        oldWidget.selectedConversation.groupID !=
            widget.selectedConversation.groupID ||
        oldWidget.selectedConversation.type !=
            widget.selectedConversation.type) {
      _openLifecycle.cancelPendingPostOpenTasks();
      _postOpenScheduler.cancelPending();
      _schedulePostOpenTasks();
    }
  }
~~~

31. [TUIChatGlobalModel.messageStatusInConversation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3627>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3627–3644 行。

~~~dart
int messageStatusInConversation(
    String conversationID, {
    String? clientId,
    String? msgID,
    int? fallback,
    int? elemType,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return OutgoingSendStatus.normalize(status: fallback);
    }
    final current = _messageInConversation(conversationID,
        clientId: clientId, msgID: msgID);
    if (current != null) {
      return _normalizedOutgoingStatus(current, fallback);
    }
    return OutgoingSendStatus.normalize(status: fallback);
  }
~~~

32. [TUIChatGlobalModel.abandonOutcomeUnknownMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3646>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3646–3669 行。

~~~dart
Future<bool> abandonOutcomeUnknownMessage({
    required String conversationID,
    required ConvType conversationType,
    required String sdkLocalId,
    String? msgID,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty || conversationType == ConvType.none) return false;
    final abandoned =
        await ImOutgoingSendCoordinator.instance.abandonOutcomeUnknown(
      sdkLocalId: localId,
      conversationId: conversationID,
      conversationType: conversationType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
    );
    if (!abandoned) return false;
    return markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: localId,
      msgID: msgID,
      reason: 'outcome_unknown_abandoned_by_user',
    );
  }
~~~

33. [TUIChatGlobalModel.applyOutgoingSendResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3671>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3671–3716 行。

~~~dart
bool applyOutgoingSendResult(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String clientId,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
  ) {
    final dataMsgID = sendMsgRes.data?.msgID;
    if (isOutgoingMediaCancelled(clientId) ||
        isOutgoingMediaCancelled(dataMsgID)) {
      return false;
    }
    try {
      updateMessage(
        sendMsgRes,
        convID,
        clientId,
        convType,
        groupType,
        setInputField,
      );
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return true;
    } catch (e) {
      outputLogger.i('updateMessage error: $e');
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return false;
    }
  }
~~~

34. [TUIChatGlobalModel.hasOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6455>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6455–6458 行。

~~~dart
/// 是否仍有进页 hydrate / 冷开并行 peek 在飞（别名感知）。
  bool hasOpenHydrateInFlight(String conversationID) {
    return _findOpenHydrateInFlight(conversationID) != null;
  }
~~~

35. [TUIChatGlobalModel.openHydrateResultFor](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6460>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6460–6477 行。

~~~dart
/// Last terminal result for the app-owned first-window bootstrap. This is
  /// separate from the in-flight map so a caller arriving just after
  /// completion can consume the same result without issuing LOCAL/CLOUD again.
  OpenHydrateResult? openHydrateResultFor(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) return null;
    final direct = _openHydrateResultByConv[trimmed];
    if (direct != null) return direct;
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateResultByConv[normalized];
      if (byNorm != null) return byNorm;
    }
    for (final entry in _openHydrateResultByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) return entry.value;
    }
    return null;
  }
~~~

36. [TUIChatGlobalModel.publishOpenHydrateResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6487>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6487–6496 行。

~~~dart
void publishOpenHydrateResult(
    String conversationID,
    OpenHydrateResult result,
  ) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateResultByConv[alias] = result;
    }
  }
~~~

37. [TUIChatGlobalModel.clearOpenHydrateResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6498>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6498–6504 行。

~~~dart
void clearOpenHydrateResult(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    _openHydrateResultByConv.removeWhere(
      (alias, _) => _isSameConversationID(alias, key),
    );
  }
~~~

38. [TUIChatGlobalModel._findOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6506>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6506–6528 行。

~~~dart
Future<OpenHydrateResult>? _findOpenHydrateInFlight(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final direct = _openHydrateInFlightByConv[trimmed];
    if (direct != null) {
      return direct;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateInFlightByConv[normalized];
      if (byNorm != null) {
        return byNorm;
      }
    }
    for (final entry in _openHydrateInFlightByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) {
        return entry.value;
      }
    }
    return null;
  }
~~~

39. [TUIChatGlobalModel.ensureOpenHydrate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6530>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6530–6671 行。

~~~dart
/// The route, page and UIKit share one task and its terminal result.
  /// A caller timing out does not remove the underlying task.
  Future<OpenHydrateResult> ensureOpenHydrate(
    String conversationID, {
    required String requestSignature,
    required Future<bool> Function() load,
    required bool Function() canPublish,
  }) {
    final key = conversationID.trim();
    final existing = _findOpenHydrateInFlight(key);
    if (existing != null && (_openHydrateCanPublish[existing]?.call() ?? true)) {
      final joinTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.markHydrateJoined(
        ChatOpenPerfLog.lastPrepareRequestId,
        trace: joinTrace,
      );
      ChatOpenPerfLog.mark(
        'app_hydrate_join',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': joinTrace.requestId,
          'prepareId': joinTrace.requestId,
        },
        trace: joinTrace,
      );
      if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
        _openBottomCapsuleHydrateSettled = false;
      }
      return existing;
    }
    final previous = openHydrateResultFor(key);
    if (previous != null &&
        previous.requestSignature == requestSignature &&
        previous.shouldSuppressOrdinaryLoad &&
        hasInitialHistoryLoaded(key)) {
      final reuseTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.mark(
        'app_hydrate_reuse',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': reuseTrace.requestId,
          'prepareId': reuseTrace.requestId,
          'hydrateKind': previous.kind.name,
        },
        trace: reuseTrace,
      );
      markOpenChatHydrateSettled(key);
      return Future.value(previous);
    }
    clearOpenHydrateResult(key);
    final generation = _messageHistoryCoverageSessionGeneration;
    final clearEpoch = messageDeltaClearEpochFor(key);
    final ownerTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
    final ownerRequestId = ownerTrace.requestId;
    ChatOpenPerfLog.markHydrateOwner(ownerRequestId, trace: ownerTrace);
    ChatOpenPerfLog.mark(
      'app_hydrate_registered',
      conversationID: key,
      extras: <String, Object?>{
        'requestId': ownerRequestId,
        'prepareId': ownerRequestId,
      },
      trace: ownerTrace,
    );
    late final Future<OpenHydrateResult> task;
    task = Future<OpenHydrateResult>.microtask(() async {
      var kind = OpenHydrateResultKind.aborted;
      ChatOpenPerfLog.mark(
        'app_hydrate_started',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': ownerRequestId,
          'prepareId': ownerRequestId,
        },
        trace: ownerTrace,
      );
      try {
        if (canPublish() && await load()) {
          kind = rawMessageCount(key) > 0
              ? OpenHydrateResultKind.committedMessages
              : OpenHydrateResultKind.committedEmpty;
        }
      } catch (_) {
        kind = OpenHydrateResultKind.failed;
      }
      final current = generation == _messageHistoryCoverageSessionGeneration &&
          clearEpoch == messageDeltaClearEpochFor(key) &&
          identical(_findOpenHydrateInFlight(key), task) &&
          canPublish();
      if (!current) kind = OpenHydrateResultKind.aborted;
      final result = OpenHydrateResult(
        kind: kind,
        conversationKey: key,
        resultCount: current ? rawMessageCount(key) : 0,
        firstWindowCommitted: current &&
            (kind == OpenHydrateResultKind.committedMessages ||
                kind == OpenHydrateResultKind.committedEmpty),
        generation: generation,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
        requestSignature: requestSignature,
      );
      if (current) {
        publishOpenHydrateResult(key, result);
        ChatOpenPerfLog.mark(
          'app_hydrate_commit',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
          },
          trace: ownerTrace,
        );
      } else {
        ChatOpenPerfLog.mark(
          'app_hydrate_aborted',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
            'staleReason': 'hydrateAborted',
          },
          trace: ownerTrace,
        );
      }
      return result;
    }).whenComplete(() {
      final stillOwner = identical(_findOpenHydrateInFlight(key), task);
      _openHydrateInFlightByConv
          .removeWhere((_, value) => identical(value, task));
      if (stillOwner) markOpenChatHydrateSettled(key);
    });
    _openHydrateCanPublish[task] = canPublish;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateInFlightByConv[alias] = task;
    }
    if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
      _openBottomCapsuleHydrateSettled = false;
    }
    return task;
  }
~~~

40. [TUIChatGlobalModel.awaitOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6673>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6673–6686 行。

~~~dart
Future<void> awaitOpenHydrateInFlight(
    String conversationID, {
    Duration timeout = const Duration(milliseconds: 450),
  }) async {
    final inFlight = _findOpenHydrateInFlight(conversationID);
    if (inFlight == null) {
      return;
    }
    try {
      await inFlight.timeout(timeout);
    } on TimeoutException {
      // hydrate 自行兜底。
    }
  }
~~~

41. [TUIChatGlobalModel.bindOutgoingSyncMsgId](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:8235>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，8235–8297 行。

~~~dart
/// Binds SDK-assigned [msgID] to a sending placeholder before send completes.
  void bindOutgoingSyncMsgId(
    String conversationID,
    String clientId,
    String msgID,
  ) {
    final id = clientId.trim();
    final serverMsgID = msgID.trim();
    if (id.isEmpty || serverMsgID.isEmpty) {
      return;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return;
    }

    final current = _mergedAliasMessageList(storageKey);
    final index = current.indexWhere(
      (item) =>
          item.isSelf == true &&
          item.id == id &&
          (item.msgID == null || item.msgID!.isEmpty || item.msgID == id),
    );
    if (index < 0) {
      return;
    }

    final previous = current[index];
    final updated = _cloneMessage(previous);
    updated.msgID = serverMsgID;
    final stableIdentity = readOutgoingStableId(previous) ?? id;
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'send_bind:$id:$serverMsgID',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: updated,
            msgID: updated.msgID,
            localID: updated.id,
            outgoingStableID: stableIdentity,
            seq: updated.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      // Rejected/stale/active-history binds must not mutate the formal list.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageKey,
      id,
      ChatUiStateStore.messageKeyOf(updated),
    );
    ChatMessageHeightCache.instance.rememberAlias(id, serverMsgID);
    _markMessageRowChanged(storageKey, updated, extraKey: id);
    _markNeedsNotify();
  }
~~~

42. [TUIChatGlobalModel._sendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:10767>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，10767–10874 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    bool? isEditStatusMessage = false,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    V2TimMessage? messageInfo,
    bool isExcludedFromContentModeration = false,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    ValueChanged<ImCoordinatedSendResult>? onCoordinatedResult,
  }) async {
    String receiver = convType == ConvType.c2c ? convID : '';
    String groupID = convType == ConvType.group ? convID : '';
    // 历史桶 key 常带 `c2c_` / `group_` 前缀；IM sendMessage 必须用裸 userID / groupID。
    if (receiver.toLowerCase().startsWith('c2c_') && receiver.length > 4) {
      receiver = receiver.substring(4);
    }
    if (groupID.toLowerCase().startsWith('group_') && groupID.length > 6) {
      groupID = groupID.substring(6);
    }
    final receiptGroupType = groupType ??
        (convType == ConvType.group
            ? await _loadGroupReceiptType(groupID)
            : null);
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group ||
                _isReadReceiptAllowedGroup(receiptGroupType)) &&
            !_looksLikeCommunityGroupId(groupID);
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      sdkLocalId: id,
      conversationId: convID,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
      onlineUserOnly: onlineUserOnly ?? false,
      businessCloudCustomData: cloudCustomData ??
          json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          }),
      persistOutbox: isEditStatusMessage != true,
      recoverPreparedOutbox: recoverPreparedOutbox,
      operationIdOverride: operationIdOverride,
      clientCorrelationIdOverride: clientCorrelationIdOverride,
      onSyncMsgID: (syncMsgID) {
        bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    onCoordinatedResult?.call(coordinatedSend);
    final sendMsgRes = coordinatedSend.sdkResult;
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {
      projectionCommitted = applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        receiptGroupType,
        setInputField,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (!coordinatedSend.outcomeUnknown) {
      insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    if (_lifeCycle?.messageDidSend != null) {
      _lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }
~~~

43. [TUIChatGlobalModel._findMessageIndexForUpdate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12161>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12161–12172 行。

~~~dart
int _findMessageIndexForUpdate(
    List<V2TimMessage> messageList,
    String id,
    V2TimMessage sentMessage,
  ) {
    return findReplaceableOutgoingIndex(
      '',
      sentMessage,
      priorTempId: id,
      listOverride: messageList,
    );
  }
~~~

44. [TUIChatGlobalModel.updateMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12192>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12192–12414 行。

~~~dart
updateMessage(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String id,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
  ) {
    final storageConvID = _resolveMessageListStorageKey(convID);
    List<V2TimMessage> currentHistoryMsgList =
        _messageListMap[storageConvID] ?? _collectAuthoritativeMessages(convID);
    final V2TimMessage sendMsgResData = sendMsgRes.data as V2TimMessage;
    final resolvedMessage = _cloneMessage(sendMsgResData);

    // Always set the correct status based on send result
    if (sendMsgRes.code == 0) {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
      _setUploadProgressSilently(id, 100);
      final resolvedMsgID = resolvedMessage.msgID?.trim();
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _setUploadProgressSilently(resolvedMsgID, 100);
      }
    } else {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (resolvedMessage.id == null || resolvedMessage.id!.isEmpty) {
      resolvedMessage.id = id;
    }
    final targetIndex = _findMessageIndexForUpdate(
      currentHistoryMsgList,
      id,
      resolvedMessage,
    );
    final originalRowCount = currentHistoryMsgList.length;
    if (sendMsgRes.code != 0 &&
        resolvedMessage.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      ErrorMessageConverter.attachSendFailCode(
        resolvedMessage,
        sendMsgRes.code,
      );
      final msgID = resolvedMessage.msgID;
      if (msgID != null &&
          msgID.isNotEmpty &&
          resolvedMessage.localCustomData != null) {
        _messageService.setLocalCustomData(
          msgID: msgID,
          localCustomData: resolvedMessage.localCustomData!,
        );
      }
    }
    V2TimMessage? previousForMerge;
    if (targetIndex != -1) {
      currentHistoryMsgList = [...currentHistoryMsgList];
      previousForMerge = currentHistoryMsgList[targetIndex];
      if (sendMsgRes.code != 0) {
        final boundMsgID = previousForMerge.msgID?.trim();
        if (boundMsgID != null && boundMsgID.isNotEmpty) {
          resolvedMessage.msgID = boundMsgID;
        }
      }
      _preserveSoundLocalPath(previousForMerge, resolvedMessage);
      _preserveImageLocalPath(previousForMerge, resolvedMessage);
      _preserveImageDisplaySize(resolvedMessage, id);
      _preserveOutgoingLocalOrderData(previousForMerge, resolvedMessage);
      currentHistoryMsgList[targetIndex] = resolvedMessage;
    } else {
      currentHistoryMsgList = [resolvedMessage, ...currentHistoryMsgList];
    }
    final resolvedId = resolvedMessage.id ?? id;
    final resolvedMsgID = resolvedMessage.msgID;
    if (sendMsgRes.code == 0) {
      final hadFailCode =
          ErrorMessageConverter.getSendFailCode(resolvedMessage) != null;
      ErrorMessageConverter.clearSendFailCode(resolvedMessage);
      if (hadFailCode && resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _messageService.setLocalCustomData(
          msgID: resolvedMsgID,
          localCustomData: resolvedMessage.localCustomData ?? '',
        );
      }
      _clearUploadProgressSilently(resolvedId);
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _clearUploadProgressSilently(resolvedMsgID);
      }
      _migrateFileMessageMetadata(id, resolvedMsgID);
      if (resolvedMessage.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        final layoutSize = _fileMessageSizeMap[id] ??
            ((resolvedMsgID?.isNotEmpty ?? false)
                ? _fileMessageSizeMap[resolvedMsgID!]
                : null);
        if (layoutSize != null &&
            layoutSize.width > 0 &&
            layoutSize.height > 0) {
          applyImageLayoutToMessage(resolvedMessage, layoutSize);
          if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
            _messageService.setLocalCustomData(
              msgID: resolvedMsgID,
              localCustomData: resolvedMessage.localCustomData ?? '',
            );
          }
        }
      }
    }
    if (resolvedId.isNotEmpty || (resolvedMsgID?.isNotEmpty ?? false)) {
      currentHistoryMsgList = currentHistoryMsgList.where((element) {
        if (identical(element, resolvedMessage)) {
          return true;
        }
        final sameId = resolvedId.isNotEmpty && element.id == resolvedId;
        final sameMsgID = resolvedMsgID != null &&
            resolvedMsgID.isNotEmpty &&
            element.msgID == resolvedMsgID;
        if (!sameId && !sameMsgID) {
          return true;
        }
        return false;
      }).toList();
    }
    final collapsedDuplicate = currentHistoryMsgList.length < originalRowCount;
    if (loadingMessage[storageConvID] != null &&
        loadingMessage[storageConvID]!.isNotEmpty) {
      loadingMessage[storageConvID]!.removeWhere((element) => element.id == id);
    }
    if (chatConfig.isShowReadingStatus &&
        groupType != GroupReceiptAllowType.community &&
        sendMsgRes.data?.msgID != null) {
      _messageReadReceiptMap[sendMsgRes.data!.msgID!] = V2TimMessageReceipt(
        timestamp: 0,
        userID: "",
        readCount: 0,
      );
    }
    _registerSoundLocalPath(resolvedMessage);
    final stableIdentity =
        readOutgoingStableId(previousForMerge)?.trim().isNotEmpty == true
            ? readOutgoingStableId(previousForMerge)!.trim()
            : readOutgoingStableId(resolvedMessage)?.trim().isNotEmpty == true
                ? readOutgoingStableId(resolvedMessage)!.trim()
                : id.trim();
    final adoptionRecord = MessageReconciliationRecord<V2TimMessage>(
      value: resolvedMessage,
      msgID: resolvedMessage.msgID,
      localID: resolvedMessage.id,
      outgoingStableID: stableIdentity,
      seq: resolvedMessage.seq,
    );
    final authoritativeSendCommit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID: 'send_adoption:$stableIdentity:${resolvedMessage.msgID ?? ''}',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: [adoptionRecord],
      ),
    );
    if (authoritativeSendCommit == null) {
      // A queued, stale, or rejected receipt cannot use the old row-local or
      // full-list fallback. History completion or a later valid receipt owns
      // the next formal publication.
      // `send_done_row_local_fallback` is intentionally retired as a formal
      // list path; keep the diagnostic term for compatibility with probes.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageConvID,
      id,
      ChatUiStateStore.messageKeyOf(resolvedMessage),
    );
    // temp id 上已测到的行高迁到正式 msgID，避免 send_done 后失缓存再估高抖动。
    ChatMessageHeightCache.instance.rememberAlias(id, resolvedMessage.msgID);
    final knownHeight = ChatMessageHeightCache.instance.heightFor(
      resolvedMessage,
    );
    if (knownHeight != null && knownHeight > 0) {
      ChatMessageHeightCache.instance.remember(resolvedMessage, knownHeight);
    }
    _markMessageRowChanged(storageConvID, resolvedMessage, extraKey: id);
    final insertedRow = targetIndex == -1;
    final reordered = !isNewestFirstStorageOrderValid(currentHistoryMsgList);
    final isRowLocalMediaReceipt = targetIndex != -1 &&
        !collapsedDuplicate &&
        stableIdentity.isNotEmpty &&
        _isRowLocalOutgoingMediaReceipt(previousForMerge, resolvedMessage);
    final structuralChange = insertedRow || collapsedDuplicate || reordered;
    if (structuralChange) {
      _bumpMessageListRevisionFor(
        storageConvID,
        reason: insertedRow
            ? 'send_done_insert_sort'
            : collapsedDuplicate
                ? 'send_done_duplicate_collapse'
                : 'send_done_reorder',
      );
    }
    _logOutgoingSendOrder(
      event: 'send_done',
      convID: storageConvID,
      message: resolvedMessage,
      clientId: id,
      mergePath: isRowLocalMediaReceipt
          ? 'row_local_stable_identity'
          : targetIndex != -1
              ? 'update_replace'
              : 'update_insert',
      existingIndex: targetIndex,
      reordered: reordered,
    );
    // 同位回执只由 ChatUiStateStore 通知该行；不发全局 notify，
    // 也不请求贴底，避免用户正在上滑时被拉回底部。
    if (!structuralChange) {
      return;
    }
    // 发送后 350ms suppress 窗口内推迟整表 notify，让 list-push 先播完。
    if (targetIndex != -1 && shouldSuppressOutgoingPinScroll()) {
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        _markNeedsNotify();
      });
    } else {
      _markNeedsNotify();
    }
  }
~~~

45. [TUIChatGlobalModel.markOutgoingSendFailedByIdentity](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12416>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12416–12500 行。

~~~dart
bool markOutgoingSendFailedByIdentity({
    required String conversationID,
    String? clientId,
    String? msgID,
    String? localCustomData,
    int? sendFailCode,
    String reason = 'send_failed',
  }) {
    final storageConvID = _resolveMessageListStorageKey(conversationID);
    final cid = clientId?.trim() ?? '';
    final mid = msgID?.trim() ?? '';
    if (storageConvID.isEmpty || (cid.isEmpty && mid.isEmpty)) {
      return false;
    }
    final list = _mergedAliasMessageList(storageConvID);
    if (list.isEmpty) {
      return false;
    }
    final index = list.indexWhere((item) {
      final stable = readOutgoingStableId(item)?.trim() ?? '';
      if (cid.isNotEmpty && (item.id == cid || stable == cid)) {
        return true;
      }
      if (mid.isNotEmpty && (item.msgID == mid || stable == mid)) {
        return true;
      }
      return false;
    });
    if (index < 0) {
      return false;
    }
    final previous = list[index];
    final failed = _cloneMessage(previous);
    failed.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    if (localCustomData != null) {
      failed.localCustomData = localCustomData;
    }
    if (sendFailCode != null) {
      ErrorMessageConverter.attachSendFailCode(failed, sendFailCode);
    }
    final stableIdentity = readOutgoingStableId(previous) ??
        readOutgoingStableId(failed) ??
        (cid.isNotEmpty ? cid : mid);
    final safeReason = reason.trim().isEmpty
        ? 'send_failed'
        : reason.trim().replaceAll(':', '_');
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID: 'send_fail:$storageConvID:$safeReason:$stableIdentity:$mid',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: failed,
            msgID: failed.msgID,
            localID: failed.id,
            outgoingStableID: stableIdentity,
            seq: failed.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return false;
    }
    final failedKey = ChatUiStateStore.messageKeyOf(failed);
    for (final alias in <String>{cid, mid, stableIdentity}..remove('')) {
      if (alias != failedKey) {
        _chatUiStateStore.bindMessageAlias(storageConvID, alias, failedKey);
      }
    }
    _markMessageRowChanged(
      storageConvID,
      failed,
      extraKey: cid.isNotEmpty ? cid : mid,
      mutationType: MessageMutationType.statusOrProgress,
    );
    if (_isSameConversationID(storageConvID, currentSelectedConv)) {
      _markNeedsNotify();
    }
    return true;
  }
~~~

46. [TUIChatGlobalModel.markOutgoingGuardDropped](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12502>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12502–12517 行。

~~~dart
/// Marks an optimistic outgoing message as SEND_FAIL when the commit guard
  /// rejected the send (e.g. conversation switched during async media prep).
  /// Finds the message by temporary client [id], updates its status, and
  /// stamps [localCustomData] with guard_dropped so the UI can show a retry.
  void markOutgoingGuardDropped({
    required String conversationID,
    required String clientId,
    String? localCustomData,
  }) {
    markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: clientId,
      localCustomData: localCustomData,
      reason: 'guard_dropped',
    );
  }
~~~

47. [TUIChatGlobalModel.applyAppRealtimeMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:10234>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，10234–10251 行。

~~~dart
/// Application-layer compatibility bridge for the single IM ingress.
  ///
  /// The SDK listener is owned by the app MessageCore. These methods preserve
  /// the existing UIKit projection behavior without registering another SDK
  /// listener inside the view model.
  Future<void> applyAppRealtimeMessage(
    V2TimMessage message, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    await _onReceiveNewMsg(
      message,
      ingressEventID: ingressEventID,
      ingressSequence: ingressSequence,
      projectMessageList: projectMessageList,
    );
  }
~~~

48. [TUIChatGlobalModel._onReceiveNewMsg](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:9250>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，9250–9384 行。

~~~dart
Future<void> _onReceiveNewMsg(
    V2TimMessage msgComing, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final writerScope = _messageReconciliationWriter.configuredScope;
    final initialConvID = _messageConversationID(msgComing);
    if (initialConvID == null || initialConvID.isEmpty) {
      return;
    }

    final capturedClearEpoch = messageDeltaClearEpochFor(initialConvID);
    V2TimMessage? mountedMessage = msgComing;
    if (_lifeCycle?.newMessageWillMount != null) {
      try {
        mountedMessage = await _lifeCycle!.newMessageWillMount(msgComing);
      } catch (e) {
        outputLogger.i('newMessageWillMount error: $e');
        mountedMessage = msgComing;
      }
    }
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope ||
        messageDeltaClearEpochFor(initialConvID) != capturedClearEpoch) {
      ChatJitterDiag.log(
        'message_inbound_drop_stale_lifecycle',
        conv: initialConvID,
        extras: <String, Object?>{
          'generation': lifecycleGeneration,
          'currentGeneration': _messageHistoryCoverageSessionGeneration,
        },
      );
      return;
    }
    if (mountedMessage == null) {
      return;
    }
    mountedMessage = _normalizeInboundC2cDirection(mountedMessage);

    final rawConvID = _messageConversationID(mountedMessage) ?? initialConvID;
    final convID = _resolveMessageListStorageKey(rawConvID);
    _syncGroupMemberFromMessage(mountedMessage);
    final senderId = TencentUtils.checkString(mountedMessage.sender) ??
        TencentUtils.checkString(mountedMessage.userID);
    if (mountedMessage.isSelf != true && senderId != null) {
      unawaited(
        UserProfileLocalBridge.upsertPublicProfileFromSnapshot(
          userId: senderId,
          nickName: mountedMessage.nickName,
          faceUrl: mountedMessage.faceUrl,
        ),
      );
    }

    // Typing/status custom messages should update typing state only. They must not
    // enter the visible message list, but they also must not stop normal message
    // events in other conversations.
    final bool isEditMessage = _editStatusCheck(mountedMessage);
    if (isEditMessage) {
      return;
    }

    if (!projectMessageList) {
      if (HistoryWindowRepositoryProvider.repository != null) {
        await _admitBoundedHistoryIncoming(
          mountedMessage,
          eventID: ingressEventID,
          ingressSequence: ingressSequence,
          allowLatestReveal: false,
        );
      }
      return;
    }

    if (!_isSameConversationID(convID, currentSelectedConv) &&
        !_messageListMap.containsKey(convID)) {
      // Notifications and business signaling run outside this display model.
      // Opening this conversation will read the SDK's persisted recent page.
      return;
    }

    if (HistoryWindowRepositoryProvider.repository != null &&
        await _admitBoundedHistoryIncoming(mountedMessage,
            eventID: ingressEventID, ingressSequence: ingressSequence)) return;
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope) return;

    _checkFromUserisActive(mountedMessage);
    final convType = TencentUtils.checkString(mountedMessage.groupID) != null
        ? ConvType.group
        : ConvType.c2c;
    final isActiveConversation = _isSameConversationID(
      convID,
      currentSelectedConv,
    );

    if (isActiveConversation &&
        chatConfig.isAutoReportRead &&
        lockedEntryUnreadCountFor(convID) == 0) {
      _scheduleActiveReadReport(convID: convID, convType: convType);
    }

    // Self-sent sync on the active chat must stay immediate for send UX.
    if (isActiveConversation && mountedMessage.isSelf == true) {
      _syncSelfSentMessage(convID, mountedMessage, forceSuccess: false);
      _markNeedsNotify();
      return;
    }

    // Group seq gap detection: if the reorder buffer is active for this
    // conversation, route through it so out-of-order messages are buffered
    // and missing messages trigger a cloud catch-up. C2C seq has no global
    // continuity so the buffer is never active for C2C.
    final buffer = _reorderBuffersByConv[convID];
    if (buffer != null && buffer.isActivated && convType == ConvType.group) {
      final result = buffer.accept(mountedMessage);
      if (result == null) {
        // Buffered: out-of-order or gap detected, will be flushed later.
        return;
      }
      if (result.isEmpty) {
        // Duplicate (seq <= expected), silently dropped.
        return;
      }
      // Contiguous: upsert immediately (may include drained buffer messages).
      for (final msg in result) {
        _inboundBatchCoalescer.enqueue(convID, msg);
      }
      return;
    }

    _inboundBatchCoalescer.enqueue(convID, mountedMessage);
  }
~~~

49. [TUIChatGlobalModel.completeHistoryReconciliation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:1279>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，1279–1400 行。

~~~dart
MessageCommitResult? completeHistoryReconciliation({
    required MessageReconciliationRequest request,
    required Iterable<V2TimMessage> history,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    String historyCommitSource = 'reconciliation',
    bool cloudHasMoreNewer = false,
    MessageHistoryBatchKind batchKind = MessageHistoryBatchKind.olderPage,
    bool? historyIsFinished,
    int? clearEpoch,
    MessageHistoryCursor? requestedCursor,
    MessageHistoryBounds? returnedBounds,
    MessageHistoryProofKind? proofKind,
    bool? cloudResponseProven,
    Iterable<String> explicitDeletes = const <String>[],
    Iterable<String> tombstones = const <String>[],
    bool skipEquivalentHistoryWindow = false,

    /// Already canonical window captured by the pagination caller. Reusing it
    /// avoids a second alias merge/dedupe while committing an older page.
    List<V2TimMessage>? currentWindowOverride,
  }) {
    // Include direct row-local/self-send commits made while the request was in
    // flight. Inbound callbacks are already held in pendingRealtime.
    final historyList = history.toList(growable: false);
    final effectiveClearEpoch =
        clearEpoch ?? messageDeltaClearEpochFor(request.conversationKey);
    final current = currentWindowOverride ??
        _mergedAliasMessageList(request.conversationKey);
    final authoritativeBase =
        batchKind == MessageHistoryBatchKind.latestWindow &&
                actualSource == MessageReconciliationSource.cloud
            ? _authoritativeBaseForCloudLatestWindow(
                conversationID: request.conversationKey,
                current: current,
                cloudWindow: historyList,
              )
            : current;
    final resolvedProofKind = proofKind ??
        (cloudResponseProven != null
            ? (cloudResponseProven
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none)
            : actualSource == MessageReconciliationSource.cloud &&
                    networkState == MessageReconciliationNetworkState.online
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none);
    final commit = _messageReconciliationWriter.completeHistory(
      request: request,
      history: _reconciliationRecords(historyList),
      authoritativeBase: _reconciliationRecords(authoritativeBase),
      actualSource: actualSource,
      networkState: networkState,
      clearEpoch: effectiveClearEpoch,
      cloudHasMoreNewer: cloudHasMoreNewer,
      batchKind: batchKind,
      proofKind: resolvedProofKind,
      historyIsFinished: historyIsFinished,
      explicitDeletes: explicitDeletes,
      tombstones: tombstones,
    );
    if (commit == null) {
      return null;
    }
    final result = setMessageList(
      commit.conversationKey,
      _messageReconciliationWriter.valuesFor(commit.conversationKey),
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: applyMemoryWindow,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      skipEquivalentHistoryWindow: true,
      writerCommit: commit,
      historyCommitSource: skipEquivalentHistoryWindow
          ? historyCommitSource
          : '$historyCommitSource:r${commit.revision}',
    );
    final resolvedMetadataKey = _resolveMessageListStorageKey(
      commit.conversationKey,
    );
    final metadataKey = resolvedMetadataKey.isEmpty
        ? commit.conversationKey.trim()
        : resolvedMetadataKey;
    _lastHistoryCommitMetadataByConv[metadataKey] =
        MessageHistoryCommitMetadata(
      conversationKey: metadataKey,
      source: actualSource,
      batchKind: batchKind,
      generation: request.generation,
      revision: commit.revision,
      resultCount: result.rawCount,
      proofKind: resolvedProofKind,
      clearEpoch: effectiveClearEpoch,
    );
    _recordMessageHistoryCoverageAfterCommit(
      request: request,
      batchKind: batchKind,
      actualSource: actualSource,
      networkState: networkState,
      history: historyList,
      historyIsFinished: historyIsFinished,
      cloudHasMoreNewer: cloudHasMoreNewer,
      clearEpoch: effectiveClearEpoch,
      requestedCursor: requestedCursor,
      returnedBounds: returnedBounds,
      proofKind: resolvedProofKind,
    );
    unawaited(
      ImOutgoingSendCoordinator.instance
          .adoptProviderHistory(historyList)
          .catchError((Object error) {
        debugPrint(
          'OUTBOX_HISTORY_ADOPTION_FAILURE '
          'errorType=${error.runtimeType}',
        );
        return 0;
      }),
    );
    return result;
  }
~~~

50. [TUIChatSeparateViewModel.initForEachConversation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:857>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，857–1047 行。

~~~dart
void initForEachConversation(
    ConvType convType,
    String convID,
    ValueChanged<String>? onChangeInputField, {
    String? groupID,
    String? groupType,
    List<V2TimGroupMemberFullInfo?>? preGroupMemberList,
  }) async {
    if (_isInit) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID),
      );
      return;
    }
    setInputField = onChangeInputField;
    conversationType = convType;
    _groupType = null;
    if (convType == ConvType.group) {
      final normalizedGroupType = groupType?.trim().toLowerCase();
      _groupType = switch (normalizedGroupType) {
        'meeting' => GroupReceiptAllowType.meeting,
        'public' => GroupReceiptAllowType.public,
        'work' => GroupReceiptAllowType.work,
        'community' => GroupReceiptAllowType.community,
        _ => null,
      };
    }
    // 消息列表 / hydrate / 归档一律用裸会话 ID（@TGS#…），勿带 group_。
    final previousConversationID = conversationID;
    conversationID = _storageConversationId(convID);
    if (previousConversationID != conversationID) {
      _mediaCommitGuard.advanceConversation();
    }
    _disposed = false;
    final initGeneration = ++_chatOpenGeneration;
    final initConversationID = conversationID;
    // Establish the visit boundary before the first await or incoming callback.
    // Failure keeps the baseline pending; admission/return retries it in order.
    unawaited(globalModel.beginHistoryUnreadVisit(conversationID).catchError(
      (Object error, StackTrace stack) {
        ChatHistoryTrace.log('unread_visit_baseline_retry_required',
            conversationID: initConversationID);
      },
    ));
    _preGroupMemberListForOpen = preGroupMemberList;
    _openProfileEnrichmentInFlight = null;
    _pagination.resetForConversationInit();

    var warmOnStorage = globalModel.rawMessageCount(conversationID);
    final warmOnRaw = globalModel.rawMessageCount(convID);
    final idMismatchRisk = warmOnStorage == 0 && warmOnRaw > 0;
    ChatHistoryTrace.log(
      'init_conv',
      conversationID: conversationID,
      extras: <String, Object?>{
        'rawConvID': convID,
        'warmOnStorage': warmOnStorage,
        'warmOnRaw': warmOnRaw,
        'loadedStorage': globalModel.hasInitialHistoryLoaded(conversationID),
        'loadedRaw': globalModel.hasInitialHistoryLoaded(convID),
        'idMismatchRisk': idMismatchRisk,
      },
    );

    // 暖窗写在 raw/group_ 桶、页面已收成裸 storageId：迁到 storage，避免假空。
    if (idMismatchRisk) {
      final aliasWindow = globalModel.rawMessageList(convID);
      if (aliasWindow != null && aliasWindow.isNotEmpty) {
        final historyIsCurrent = _historyPublicationFence();
        final authoritative = await globalModel.applyHistoryWindowMutations(
            conversationID, List<V2TimMessage>.from(aliasWindow));
        if (!historyIsCurrent()) return;
        final commit = globalModel.setMessageList(
          conversationID,
          authoritative,
          needResetNewMessageCount: false,
          replace: true,
        );
        globalModel.markInitialHistoryLoaded(conversationID);
        final mayOlder = globalModel.mayHaveOlderHistory(convID) ||
            aliasWindow.length >=
                HistoryMessageDartConstant.initialOpenFetchCount;
        globalModel.markInitialHistoryMayHaveOlder(
          conversationID,
          mayHaveOlder: mayOlder,
        );
        warmOnStorage = commit.rawCount;
        ChatHistoryTrace.log(
          'init_conv_migrate_alias_window',
          conversationID: conversationID,
          extras: <String, Object?>{
            'fromKey': convID,
            'toKey': conversationID,
            'count': aliasWindow.length,
            'mayHaveOlder': mayOlder,
            'warmOnStorageAfter': warmOnStorage,
          },
        );
      }
    }

    if (globalModel.hasInitialHistoryLoaded(conversationID) &&
        globalModel.rawMessageCount(conversationID) > 0) {
      final mayOlder = globalModel.mayHaveOlderHistory(conversationID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(conversationID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      // 兼容进页瞬间仍用旧 key（group_）写暖窗的情况。
      final mayOlder = globalModel.mayHaveOlderHistory(convID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(convID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else {
      _pagination.markHistoryUnknown();
    }
    haveMoreLatestData = false;

    isGroupExist = true;
    _groupInfo = null;
    groupMemberList = null;
    selfMemberInfo = null;
    groupMemberListComplete = false;
    _idleFullMemberLoadGeneration++;
    _fullMemberLoadInFlight = null;
    _openShellGeneration++;
    _openShellInFlight = null;
    _openShellCompletedGid = null;
    _warmOpenHistoryReconcileScheduled = false;
    _warmOpenTowardLocalScheduled = false;
    _fillTowardOlderHistoryResumeTimer?.cancel();
    _fillTowardOlderHistoryResumeTimer = null;
    _lastPeekIsFinished = false;
    _sdkOlderPageTail = null;

    globalModel.setCurrentConversation(
      CurrentConversation(conversationID, conversationType ?? ConvType.c2c),
      notify: false,
    );
    globalModel.lifeCycle = lifeCycle;
    if (globalModel.hasPendingScrollRestore(conversationID)) {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.notShowLatest,
        notify: false,
      );
    } else {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: false,
      );
    }
    globalModel.setChatConfig(chatConfig);

    if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(convID),
      );
    }

    if (conversationType == ConvType.group) {
      _groupID = groupID;
      final resolvedGroupId = groupID ?? convID;
      final selfId = selfModel.loginInfo?.userID?.trim() ?? '';
      if (selfId.isNotEmpty) {
        final cachedSelf = GroupMemberStore.instance.memberOf(
          resolvedGroupId,
          selfId,
        );
        if (cachedSelf != null) {
          selfMemberInfo = cachedSelf;
        }
      }
      final skipOpenNotify = globalModel.hasInitialHistoryLoaded(convID) &&
          globalModel.rawMessageCount(convID) > 0;
      if (!skipOpenNotify) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isChatGenerationCurrent(initGeneration, initConversationID)) {
            _notify();
          }
        });
      }
    }

    globalModel.removeRoamingSyncListener(_onRoamingSyncFinished);
    globalModel.addRoamingSyncListener(_onRoamingSyncFinished);
    _isInit = true;
  }
~~~

51. [TUIChatSeparateViewModel.loadChatRecord](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:1822>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，1822–1852 行。

~~~dart
Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,

    /// true：忽略「内存已有足够条数」短路，强制重拉最新一页（回底用）。
    bool forceReloadNewest = false,
  }) {
    // A retained outgoing/live row is not the edge of this history segment.
    if (direction == LoadDirection.latest &&
        !forceReloadNewest &&
        historyNewerPageCursor != null) {
      lastMsg = historyNewerPageCursor;
      lastMsgID = TencentUtils.checkString(lastMsg?.msgID);
      lastMsgSeq = int.tryParse(lastMsg?.seq ?? '') ?? -1;
    }
    // Ensure runner is initialized (binds into _pagination) before delegating.
    final runner = _historyLoadRunner;
    return runner.pagination.loadChatRecord(
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      direction: direction,
      lastMsg: lastMsg,
      forceReloadNewest: forceReloadNewest,
    );
  }
~~~

52. [TUIChatSeparateViewModel._sendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:5409>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，5409–5683 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    V2TimMessage? messageInfo,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    bool? isEditStatusMessage = false,
    bool? isExcludedFromContentModeration,
    bool preserveTargetGroupID = false,
  }) async {
    debugPrint(
      '[IM_SEND_INTENT] conv=$convID type=${convType.name} clientId=$id',
    );
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    final target = _resolveSendTarget(
      convID: convID,
      convType: convType,
      messageID: id,
    );
    if (target == null) {
      debugPrint(
        '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=invalid_target',
      );
      removeSendingMessageID(id);
      final invalidResult = _buildInvalidTargetResult(
        id: id,
        convID: convID,
        convType: convType,
        messageInfo: messageInfo,
      );
      if (messageInfo != null) {
        messageInfo.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        globalModel.updateMessage(
          invalidResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
      }
      return invalidResult;
    }
    String receiver = target.receiver;
    String groupID = target.groupID;
    // IM peer-blacklist is sendMessage code (20007 if console fails closed).
    // App POST /me/blocks does not produce 20007. This gate only reads
    // confirmed relation canMessage=false.
    if (convType == ConvType.c2c) {
      final snapshot = C2cFriendMessageGuard.cachedUiSnapshot(receiver);
      if (snapshot != null &&
          snapshot.decision == C2cSendPermissionDecision.blocked &&
          snapshot.relationConfirmed) {
        debugPrint(
          '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=relation_blocked',
        );
        removeSendingMessageID(id);
        final failedMessage = messageInfo ??
            V2TimMessage(
              id: id,
              msgID: id,
              elemType: MessageElemType.V2TIM_ELEM_TYPE_NONE,
            );
        failedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        final blockedResult = V2TimValueCallback<V2TimMessage>(
          code: C2cBlockedOutgoingMessageSync.blockedCode,
          desc: 'friend relation blocked',
          data: failedMessage,
        );
        globalModel.applyOutgoingSendResult(
          blockedResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
        return blockedResult;
      }
    }
    // Dispatch C2C messages without a blocking friend-relation HTTP lookup.
    // Provider send results own rejection; UI relation refresh runs separately.
    if (convType == ConvType.group &&
        _groupType == null &&
        !preserveTargetGroupID) {
      await loadGroupInfo(groupID);
    }
    // SelfHosted 拉到的真源 groupID（如 @TGS#_mc…）优先于会话里错误加成的 ID。
    final infoGroupId = _groupInfo?.groupID?.trim() ?? '';
    if (convType == ConvType.group &&
        !preserveTargetGroupID &&
        infoGroupId.isNotEmpty &&
        infoGroupId != groupID &&
        (_looksLikeCommunityGroupId(infoGroupId) ||
            !_looksLikeCommunityGroupId(groupID))) {
      groupID = infoGroupId;
      if (_groupID != infoGroupId) {
        _groupID = infoGroupId;
      }
    }
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group || _isReadReceiptAllowedGroup) &&
            !_looksLikeCommunityGroupId(groupID);
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    if (messageInfo != null) {
      setLoadingMessageMap(convID, messageInfo);
    }
    final mediaKind = switch (messageInfo?.elemType) {
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE => 'image',
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO => 'video',
      MessageElemType.V2TIM_ELEM_TYPE_FILE => 'file',
      _ => null,
    };
    if (mediaKind != null) {
      final raw = localCustomData ?? messageInfo?.localCustomData;
      try {
        final decoded = raw == null || raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
        if (decoded is Map) {
          localCustomData = jsonEncode({...decoded, 'mediaSendKind': mediaKind});
          messageInfo?.localCustomData = localCustomData;
        }
      } catch (_) {
        // Preserve opaque metadata; it keeps the legacy serial admission.
      }
    }
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      sdkLocalId: id,
      conversationId: convType == ConvType.group ? groupID : receiver,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData ?? messageInfo?.localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      onlineUserOnly: onlineUserOnly ?? false,
      isExcludedFromContentModeration: isExcludedFromContentModeration ?? false,
      businessCloudCustomData: cloudCustomData ??
          (showC2cMessageEditStatus == true
              ? json.encode({
                  "messageFeature": {"needTyping": 1, "version": 1},
                })
              : ""),
      persistOutbox: isEditStatusMessage != true,
      expectedSessionIdentity: _outgoingMediaIdentity,
      onSyncMsgID: (syncMsgID) {
        globalModel.bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    final sendMsgRes = coordinatedSend.sdkResult;
    if (!canSendCapturedMedia) return sendMsgRes;
    debugPrint(
      '[IM_SEND_COORDINATOR_RESULT] conv=$convID clientId=$id '
      'code=${sendMsgRes.code} desc=${sendMsgRes.desc} '
      'outcomeUnknown=${coordinatedSend.outcomeUnknown}',
    );
    if (_isOutgoingMediaCancelled(id) ||
        _isOutgoingMediaCancelled(messageInfo?.msgID) ||
        _isOutgoingMediaCancelled(sendMsgRes.data?.msgID)) {
      removeSendingMessageID(id);
      final sdkMsgID = TencentUtils.checkString(sendMsgRes.data?.msgID);
      if (sendMsgRes.code == 0 && sdkMsgID != null) {
        try {
          await _messageService.revokeMessage(
            msgID: sdkMsgID,
            webMessageInstance: sendMsgRes.data?.messageFromWeb,
          );
        } catch (_) {}
        await _messageService.deleteMessageFromLocalStorage(
          msgID: sdkMsgID,
          webMessageInstance: sendMsgRes.data?.messageFromWeb,
        );
      }
      globalModel.markOutgoingSendFailedByIdentity(
        conversationID: convID,
        clientId: id,
        msgID: sdkMsgID ?? messageInfo?.msgID,
        reason: 'cancelled',
      );
      globalModel.clearMessageProgress(id);
      globalModel.clearMessageProgress(messageInfo?.msgID);
      globalModel.clearMessageProgress(sendMsgRes.data?.msgID);
      _clearOutgoingMediaCancelled(id);
      _clearOutgoingMediaCancelled(messageInfo?.msgID);
      _clearOutgoingMediaCancelled(sendMsgRes.data?.msgID);
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'cancelled',
        data: messageInfo,
      );
    }
    removeSendingMessageID(id);
    OutgoingVisibleProbe.log(
      'send_sdk_result',
      conversationID: convID,
      message: sendMsgRes.data ?? messageInfo,
      extras: <String, Object?>{
        'code': sendMsgRes.code,
        'desc': sendMsgRes.desc,
        'clientId': id,
        'hasData': sendMsgRes.data != null,
        'dataMsgID': sendMsgRes.data?.msgID ?? '',
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(convID),
        ),
      },
    );
    if (sendMsgRes.data != null) {
      OutgoingVisibleProbe.rememberSent(
        conversationID: convID,
        message: sendMsgRes.data!,
      );
    }
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {
      projectionCommitted = globalModel.applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        groupType,
        setInputField,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (!coordinatedSend.outcomeUnknown) {
      globalModel.insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    if (lifeCycle?.messageDidSend != null) {
      lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }
~~~

53. [TUIChatSeparateViewModel.sendTextAtMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:5938>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，5938–6001 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> sendTextAtMessage({
    required String text,
    required String convID,
    required ConvType convType,
    required List<String> atUserList,
    List<GroupMentionOccurrence> mentionOccurrences = const [],
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final typingBase = showC2cMessageEditStatus == true
        ? json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          })
        : null;
    final cloudCustomData = mentionOccurrences.isEmpty
        ? null
        : GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
            typingBase,
            mentionOccurrences,
          );
    final optimisticId = _prependOptimisticTextPlaceholder(
      text: text,
      cloudCustomData: cloudCustomData,
      groupAtUserList: atUserList,
    );
    final textATMessageInfo = await _messageService.createTextAtMessage(
      text: text,
      atUserList: atUserList,
    );
    final messageInfo = textATMessageInfo?.messageInfo;
    if (textATMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textATMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    if (cloudCustomData != null) {
      messageInfoWithSender.cloudCustomData = cloudCustomData;
    }
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textATMessageInfo.id as String,
      convType: ConvType.group,
      messageInfo: messageInfoWithSender,
      cloudCustomData: cloudCustomData,
      offlinePushInfo: tools.buildMessagePushInfo(
        textATMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }
~~~

54. [TUIChatSeparateViewModel._currentResendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7488>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7488–7499 行。

~~~dart
V2TimMessage? _currentResendMessage(String convID, V2TimMessage original) {
    final clientId = original.id?.trim() ?? '';
    final msgID = original.msgID?.trim() ?? '';
    for (final current in globalModel.rawMessageList(convID) ??
        const <V2TimMessage>[]) {
      if ((clientId.isNotEmpty && current.id == clientId) ||
          (msgID.isNotEmpty && current.msgID == msgID)) {
        return current;
      }
    }
    return null;
  }
~~~

55. [TUIChatSeparateViewModel.reSendFailMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7501>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7501–7542 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> reSendFailMessage({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
  }) {
    final identity = SessionIdentityService.instance.capture();
    final current = _currentResendMessage(convID, message);
    if (current == null) return Future.value(null);
    final key = json.encode([
      identity.ownerUserId, identity.generation, convType.name,
      ArchiveHistoryProvider.normalizeConversationKey(convID),
      current.id?.isNotEmpty == true ? current.id : current.msgID,
    ]);
    final existing = _resendTasks[key];
    if (existing != null) return existing;
    bool canResend() {
      if (!SessionIdentityService.instance.isCurrent(identity) ||
          !canSendCapturedMedia) {
        return false;
      }
      final live = _currentResendMessage(convID, current);
      return live != null && live.isSelf != false &&
          globalModel.messageStatusInConversation(
            convID, clientId: live.id, msgID: live.msgID,
            fallback: OutgoingSendStatus.unconfirmed,
            elemType: live.elemType,
          ) == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (!canResend()) return Future.value(null);
    late final Future<V2TimValueCallback<V2TimMessage>?> task;
    task = Future<V2TimValueCallback<V2TimMessage>?>.microtask(() {
      if (!canResend()) return null;
      return _performFailedMessageResend(
        message: current, convID: convID, convType: convType,
        canResend: canResend,
      );
    }).whenComplete(() {
      if (identical(_resendTasks[key], task)) _resendTasks.remove(key);
    });
    _resendTasks[key] = task;
    return task;
  }
~~~

56. [TUIChatSeparateViewModel._performFailedMessageResend](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7544>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7544–7620 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> _performFailedMessageResend({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
    required bool Function() canResend,
  }) async {

    if (isWalletCardMessage(message)) {
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("钱包消息不可转发"),
        ),
      );
      return null;
    }
    final clientId = message.id?.trim() ?? '';
    final msgID = message.msgID?.trim() ?? '';
    _clearOutgoingMediaCancelled(clientId);
    _clearOutgoingMediaCancelled(msgID);
    final localPath = TencentUtils.checkString(
          globalModel.getFileMessageLocation(clientId),
        ) ??
        TencentUtils.checkString(globalModel.getFileMessageLocation(msgID));
    if (localPath != null) {
      switch (message.elemType) {
        case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
          message.imageElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
          message.videoElem?.videoPath = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
          message.soundElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_FILE:
          message.fileElem?.path = localPath;
          break;
      }
    }
    final recreated = await recreateOutgoingMessage(_messageService, message);
    final recreatedId = recreated?.id?.trim() ?? '';
    final recreatedMessage = recreated?.messageInfo;
    if (recreatedId.isEmpty || recreatedMessage == null || !canResend()) {
      return null;
    }
    _removeOutgoingMessage(
      convID: convID,
      clientId: clientId.isEmpty ? null : clientId,
      msgID: msgID.isEmpty ? null : msgID,
    );
    if (msgID.isNotEmpty) {
      try {
        await _messageService.deleteMessageFromLocalStorage(
          msgID: msgID,
          webMessageInstance: message.messageFromWeb,
        );
      } catch (_) {}
    }
    final outgoing = tools.setUserInfoForMessage(recreatedMessage, recreatedId);
    applyOutgoingStableIdToMessage(outgoing, recreatedId);
    outgoing.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    addSendingMessageID(recreatedId);
    _prependOutgoingMessageForConversation(
      convID,
      outgoing,
      skipEnterAnimation: true,
    );
    return _sendMessage(
      id: recreatedId,
      convID: convID,
      convType: convType,
      messageInfo: outgoing,
      cloudCustomData: TencentUtils.checkString(outgoing.cloudCustomData),
      offlinePushInfo: tools.buildMessagePushInfo(outgoing, convID, convType),
    );
  }
~~~

57. [TUIChatSeparateViewModel.sendTextMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7622>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7622–7661 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> sendTextMessage({
    required String text,
    required String convID,
    required ConvType convType,
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final optimisticId = _prependOptimisticTextPlaceholder(text: text);
    final textMessageInfo = await _messageService.createTextMessage(text: text);
    final messageInfo = textMessageInfo?.messageInfo;
    if (textMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textMessageInfo.id as String,
      convType: convType,
      messageInfo: messageInfoWithSender,
      offlinePushInfo: tools.buildMessagePushInfo(
        textMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }
~~~

58. [TUIChatSeparateViewModel._markOutgoingMediaSendFailed](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8585>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8585–8596 行。

~~~dart
void _markOutgoingMediaSendFailed({
    required String convID,
    String? clientId,
    String? msgID,
  }) {
    globalModel.markOutgoingSendFailedByIdentity(
      conversationID: convID,
      clientId: clientId,
      msgID: msgID,
      reason: 'media_failed',
    );
  }
~~~

59. [TUIChatSeparateViewModel._prependOptimisticTextPlaceholder](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8602>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8602–8623 行。

~~~dart
/// 点发送立刻上屏，不必等原生 createTextMessage。
  String _prependOptimisticTextPlaceholder({
    required String text,
    String? cloudCustomData,
    List<String>? groupAtUserList,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: text),
        cloudCustomData: cloudCustomData,
        groupAtUserList: groupAtUserList,
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    _prependOutgoingMessage(optimistic);
    return optimisticId;
  }
~~~

60. [TUIChatSeparateViewModel._adoptOptimisticOutgoingTextMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8625>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8625–8644 行。

~~~dart
void _adoptOptimisticOutgoingTextMessage({
    required String optimisticId,
    required V2TimMessage newMessage,
  }) {
    final convID = conversationID;
    _swapOutgoingMessage(
      convID: convID,
      oldClientId: optimisticId,
      newMessage: newMessage,
    );
    final clientId = newMessage.id;
    if (clientId != null && clientId.isNotEmpty) {
      chatUiStateStore.bindMessageAlias(
        convID,
        optimisticId,
        ChatUiStateStore.messageKeyOf(newMessage),
      );
      addSendingMessageID(clientId);
    }
  }
~~~

61. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat_page/chat_draft_controller.dart:1>)，原文件 lib/src/chat_page/chat_draft_controller.dart，1–101 行。

~~~dart
import 'dart:async';

/// Debounced local draft text for the open chat page.
class ChatDraftController {
  String? text;
  Timer? _debounce;
  int _writeGeneration = 0;
  int _stateRevision = 0;
  bool _sendClearBarrier = false;
  int get writeGeneration => _writeGeneration;
  bool get shouldSuppressLifecyclePersist => _sendClearBarrier;
  int get stateRevision => _stateRevision;

  static const Duration debounceDuration = Duration(milliseconds: 250);

  void setTextImmediate(String? value) {
    final trimmed = value?.trim() ?? '';
    text = trimmed.isEmpty ? null : value;
  }

  void onChanged(
    String value, {
    required void Function(String raw, int generation) persist,
  }) {
    _sendClearBarrier = false;
    _stateRevision++;
    setTextImmediate(value);
    _debounce?.cancel();
    // Programmatic controller.clear() after send does not emit TextField's
    // onChanged by itself. Once the input layer forwards it explicitly, clear
    // the persisted draft immediately so a fast route pop cannot expose stale
    // sent text in the conversation list.
    if (value.trim().isEmpty) {
      _writeGeneration++;
      persist(value, _writeGeneration);
      return;
    }
    final generation = _writeGeneration;
    _debounce = Timer(debounceDuration, () {
      if (generation == _writeGeneration) {
        persist(value, generation);
      }
    });
  }

  void cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
  }

  void clear() {
    _writeGeneration++;
    _stateRevision++;
    cancelDebounce();
    text = null;
  }

  void dispose() {
    cancelDebounce();
  }

  void markSendCompleted() {
    _sendClearBarrier = true;
    clear();
  }

  /// Invalidates work owned by the previous conversation while allowing the
  /// new conversation to start persisting immediately.
  void beginConversation() {
    _sendClearBarrier = false;
    clear();
  }

  bool canApplyLoadedDraft(int capturedRevision) =>
      !_sendClearBarrier && capturedRevision == _stateRevision;
}

/// Serializes draft mutations without allowing one failed write to poison all
/// writes scheduled after it.
class ChatDraftWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(
    Future<void> Function() operation, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        try {
          onError?.call(error, stackTrace);
        } catch (_) {
          // Diagnostics must never become the next queue failure.
        }
      },
    );
    return _tail;
  }
}

~~~

62. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_draft_service.dart:1>)，原文件 lib/src/services/conversation_local/conversation_draft_service.dart，1–267 行。

~~~dart
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';

/// 会话草稿：以 IMSDK 本地会话库为权威，SQLite 仅保留兼容镜像。
class ConversationDraftService {
  ConversationDraftService._();

  ConversationDraftService.forTesting(
      {required this.ownerForTest,
      required this.writeForTest,
      required this.readForTest,
      required this.commitForTest});
  String Function()? ownerForTest;
  Future<int> Function(String, String?)? writeForTest;
  Future<String?> Function(String)? readForTest;
  Future<void> Function(String, String)? commitForTest;

  static final ConversationDraftService instance = ConversationDraftService._();
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> _versions = {};
  String get _owner =>
      ownerForTest?.call() ?? ContactSocialCacheStore.safeLoginUserId();

  String _sdkId(String raw) {
    final id = ConversationIdCanonical.forStorage(raw);
    if (id.isEmpty || id.startsWith('c2c_')) return id;
    if (raw.trim().startsWith('group_') ||
        ChatIdFormat.isIMGroupOrCommunityId(id) ||
        ChatIdFormat.isCommunityShortToken(id)) {
      return 'group_$id';
    }
    return 'c2c_$id';
  }

  Future<void> _write(String rawId, String? text) {
    final id = _sdkId(rawId);
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    if (id.isEmpty || identity.ownerUserId.isEmpty) return Future.value();
    final key = '${identity.ownerUserId}|${identity.generation}|$id';
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    bool current() =>
        _versions[key] == version &&
        SessionIdentityService.instance
            .isCurrent(identity, currentOwnerUserId: _owner);
    final next = (_tails[key] ?? Future<void>.value()).then((_) async {
      if (!current()) return;
      final int code;
      if (writeForTest != null) {
        code = await writeForTest!(id, text);
      } else {
        code = (await TencentImSDKPlugin.v2TIMManager
                .getConversationManager()
                .setConversationDraft(conversationID: id, draftText: text))
            .code;
      }
      if (!current()) return;
      if (code != 0) {
        ConversationDraftLeaveTrace.stage(
          'sdk_draft_write_failed',
          conversationId: id,
          extras: <String, Object?>{'code': code},
        );
        throw StateError('setConversationDraft failed: $code');
      }
      ConversationDraftLeaveTrace.stage(
        'sdk_draft_write_done',
        conversationId: id,
        draftText: text ?? '',
      );
      if (commitForTest != null) {
        await commitForTest!(id, text ?? '');
      } else {
        final commit = await _commitDraft(id, text ?? '', canCommit: current);
        if (current()) await _notifyList(commit);
      }
    });
    late Future<void> tail;
    tail = next
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
      if (identical(_tails[key], tail)) {
        _tails.remove(key);
        _versions.remove(key);
      }
    });
    _tails[key] = tail;
    return next;
  }

  Future<void> persistDraft({
    required String conversationID,
    required String rawInputText,
  }) =>
      _write(conversationID, rawInputText);

  Future<void> clearDraft({required String conversationID}) =>
      _write(conversationID, null);

  /// Clears all IDs known to represent the same active conversation. This is
  /// used after send because group routes can expose both a bare IM ID and a
  /// `group_` UI storage ID during normalization.
  Future<void> clearDraftForConversationIds(
    Iterable<String> conversationIDs,
  ) async {
    final ids =
        conversationIDs.map(_sdkId).where((id) => id.isNotEmpty).toSet();
    for (final id in ids) {
      await clearDraft(conversationID: id);
    }
  }

  Future<String?> loadDraftText({required String conversationID}) async {
    final id = _sdkId(conversationID);
    if (id.isEmpty) {
      return null;
    }
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: _owner);
    final String? text;
    if (readForTest != null) {
      text = await readForTest!(id);
    } else {
      final result = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .getConversation(conversationID: id);
      if (result.code != 0) {
        throw StateError('getConversation draft failed: ${result.code}');
      }
      text = result.data?.draftText;
    }
    if (!SessionIdentityService.instance
        .isCurrent(identity, currentOwnerUserId: _owner)) {
      return null;
    }
    return (text?.trim().isEmpty ?? true) ? null : text;
  }

  Future<void> _notifyList(
    ConversationDatabaseCommitResult<V2TimConversation>? commit,
  ) async {
    if (commit == null || !commit.shouldNotifyUi) {
      ConversationDraftLeaveTrace.stage(
        'apply_committed_projection_skipped',
        extras: <String, Object?>{
          'reason': commit == null ? 'null_commit' : 'no_notify',
        },
      );
      return;
    }
    final snapshotDraft = commit.uiBatch.upsertedSnapshots.isEmpty
        ? null
        : commit.uiBatch.upsertedSnapshots.first.draftText;
    final snapshotId = commit.uiBatch.upsertedSnapshots.isEmpty
        ? ''
        : commit.uiBatch.upsertedSnapshots.first.conversationID;
    ConversationDraftLeaveTrace.stage(
      'apply_committed_projection_start',
      conversationId: snapshotId,
      draftText: snapshotDraft,
    );
    await ChatSessionController.instance.applyCommittedProjection(
      commit.uiBatch,
    );
    ConversationDraftLeaveTrace.stage(
      'apply_committed_projection_done',
      conversationId: snapshotId,
      draftText: snapshotDraft,
    );

    // In SDK-primary mode the just-persisted SDK conversation is already the
    // authoritative row. Do not re-read the potentially stale SQLite mirror
    // and let it overwrite the draft we just displayed.
    return;

    // The SDK conversation stream can publish an older snapshot while the
    // chat route is being removed. Re-read the committed local rows and apply
    // them as an explicit draft projection so that stale SDK data cannot make
    // the draft disappear from the conversation list.
  }

  Future<ConversationDatabaseCommitResult<V2TimConversation>?> _commitDraft(
    String id,
    String text, {
    required bool Function() canCommit,
  }) async {
    final owner = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    if (owner.isEmpty) {
      return null;
    }
    final durable =
        await ConversationLocalStore.instance.coordinatorDurableState(
      ownerUserId: owner,
      conversationId: id,
    );
    // The guard must be checked before the durable write, not only before UI
    // notification. Otherwise a slow old debounce may overwrite a newer
    // input/clear operation and silently resurrect a stale draft.
    if (!canCommit()) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'can_commit'},
      );
      return null;
    }
    ConversationMutationShadowBridge.instance.restoreDurableConversationState(
      ownerUserId: owner,
      conversationId: id,
      generation: durable.generation,
      tombstoned: durable.tombstoned,
    );
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: id,
      fieldPatch: <ConversationMutationField, Object?>{
        ConversationMutationField.draft: text,
      },
    );
    if (plan == null) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'plan_null'},
      );
      return null;
    }
    if (!canCommit()) {
      ConversationDraftLeaveTrace.stage(
        'sqlite_draft_commit_skipped',
        conversationId: id,
        extras: const <String, Object?>{'reason': 'can_commit'},
      );
      return null;
    }
    final result = await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: plan,
    );
    ConversationDraftLeaveTrace.stage(
      'sqlite_draft_commit_done',
      conversationId: id,
      draftText: text,
      extras: <String, Object?>{
        'disposition': result.disposition.name,
        'shouldNotifyUi': result.shouldNotifyUi,
        'upserted': result.upsertedSnapshots.length,
      },
    );
    return result;
  }
}

~~~

63. [ConversationLocalStore._createConversationTable](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:1322>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，1322–1360 行。

~~~dart
Future<void> _createConversationTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        conv_type INTEGER NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL DEFAULT '',
        group_id TEXT NOT NULL DEFAULT '',
        show_name TEXT NOT NULL DEFAULT '',
        face_url TEXT NOT NULL DEFAULT '',
        unread_count INTEGER NOT NULL DEFAULT 0,
        recv_opt INTEGER NOT NULL DEFAULT 0,
        group_type TEXT NOT NULL DEFAULT '',
        is_pinned INTEGER NOT NULL DEFAULT 0,
        order_key INTEGER NOT NULL DEFAULT 0,
        sdk_order_key INTEGER NOT NULL DEFAULT 0,
        active_time INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        raw_json_fingerprint TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL DEFAULT 0,
        read_cleared_at INTEGER NOT NULL DEFAULT 0,
        history_cleared_at INTEGER NOT NULL DEFAULT 0,
        local_draft_text TEXT NOT NULL DEFAULT '',
        local_draft_updated_at INTEGER NOT NULL DEFAULT 0,
        last_msg_id TEXT NOT NULL DEFAULT '',
        preview_text TEXT NOT NULL DEFAULT '',
        preview_elem_type INTEGER NOT NULL DEFAULT 0,
        preview_sender TEXT NOT NULL DEFAULT '',
        preview_sender_name TEXT NOT NULL DEFAULT '',
        preview_timestamp INTEGER NOT NULL DEFAULT 0,
        preview_status INTEGER NOT NULL DEFAULT 0,
        preview_is_self INTEGER NOT NULL DEFAULT 0,
        preview_client_id TEXT NOT NULL DEFAULT '',
        preview_is_peer_read INTEGER NOT NULL DEFAULT 0,
        preview_projection_version INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, conversation_id)
      )
    ''');
  }
~~~

64. [ConversationLocalStore._createCoordinatorStateTable](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:1387>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，1387–1402 行。

~~~dart
Future<void> _createCoordinatorStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_coordinatorStateTable (
        owner_user_id TEXT NOT NULL,
        canonical_conversation_id TEXT NOT NULL,
        generation INTEGER NOT NULL DEFAULT 0,
        tombstone_generation INTEGER,
        idempotency_keys_json TEXT NOT NULL DEFAULT '[]',
        removed_at INTEGER NOT NULL DEFAULT 0,
        reason TEXT NOT NULL DEFAULT '',
        expires_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, canonical_conversation_id)
      )
    ''');
  }
~~~

65. [ConversationLocalStore.commitCoordinatorPlan](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:6396>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，6396–6627 行。

~~~dart
Future<ConversationDatabaseCommitResult<V2TimConversation>>
      commitCoordinatorPlan({
    required ConversationDatabaseCommitPlan<V2TimConversation> plan,
  }) async {
    _profileCoordinatorPlanCommits++;
    final owner = plan.ownerUserId.trim();
    final canonicalId = plan.canonicalConversationId.trim();
    if (owner.isEmpty || canonicalId.isEmpty) {
      return ConversationDatabaseCommitResult<V2TimConversation>(
        disposition:
            ConversationDatabaseCommitDisposition.rejectedEmptyIdentity,
        plan: plan,
      );
    }
    final state = await _loadCoordinatorCommitState(
      owner: owner,
      canonicalConversationId: canonicalId,
    );
    Future<void> acceptState({required int? tombstoneGeneration}) async {
      state
        ..generation = plan.generation
        ..tombstoneGeneration = tombstoneGeneration;
      state.idempotencyKeys.add(plan.idempotencyKey);
      await _persistCoordinatorCommitState(
        owner: owner,
        canonicalConversationId: canonicalId,
        state: state,
      );
    }

    if (state.idempotencyKeys.contains(plan.idempotencyKey)) {
      return ConversationDatabaseCommitResult<V2TimConversation>(
        disposition: ConversationDatabaseCommitDisposition.ignoredDuplicate,
        plan: plan,
      );
    }
    if (plan.generation < state.generation) {
      return ConversationDatabaseCommitResult<V2TimConversation>(
        disposition:
            ConversationDatabaseCommitDisposition.rejectedStaleGeneration,
        plan: plan,
      );
    }
    final tombstoneGeneration = state.tombstoneGeneration;
    if (tombstoneGeneration != null &&
        plan.changeType == ConversationDatabaseChangeType.upsert &&
        !_isDraftOnlyCoordinatorPatch(plan.fieldPatch)) {
      final canRecreate = plan.recreatesDeletedConversation &&
          plan.generation > tombstoneGeneration;
      if (!canRecreate) {
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition:
              ConversationDatabaseCommitDisposition.rejectedByTombstone,
          plan: plan,
        );
      }
    }
    if (plan.changeType == ConversationDatabaseChangeType.upsert) {
      if (_isDraftOnlyCoordinatorPatch(plan.fieldPatch)) {
        final draft =
            plan.fieldPatch[ConversationMutationField.draft]?.toString() ?? '';
        final updated = draft.trim().isEmpty
            ? await clearLocalDraft(
                conversationID: canonicalId,
                ownerUserId: owner,
              )
            : await updateLocalDraft(
                conversationID: canonicalId,
                draftText: draft,
                ownerUserId: owner,
              );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      if (_isMarkReadCoordinatorPatch(plan.fieldPatch)) {
        final updated = await markConversationReadLocally(
          canonicalId,
          ownerUserId: owner,
        );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      if (_isUnreadCountCoordinatorPatch(plan.fieldPatch)) {
        final updated = await updateConversationUnreadCountLocally(
          conversationID: canonicalId,
          unreadCount: plan.fieldPatch[ConversationMutationField.unread] as int,
          ownerUserId: owner,
          snapshot: plan.fullSnapshot,
        );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      if (_isPinOnlyCoordinatorPatch(plan.fieldPatch)) {
        final updated = await updateConversationPinnedLocally(
          conversationID: canonicalId,
          isPinned: plan.fieldPatch[ConversationMutationField.pin] == true,
          ownerUserId: owner,
          snapshot: plan.fullSnapshot,
        );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      if (_isMuteOnlyCoordinatorPatch(plan.fieldPatch)) {
        final updated = await updateConversationRecvOptLocally(
          conversationID: canonicalId,
          recvOpt: plan.fieldPatch[ConversationMutationField.mute] as int,
          ownerUserId: owner,
          snapshot: plan.fullSnapshot,
        );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      if (_isMetadataCoordinatorPatch(plan.fieldPatch)) {
        final updated = await updateConversationMetadataLocally(
          conversationID: canonicalId,
          showName: plan.fieldPatch[ConversationMutationField.name] as String?,
          faceUrl: plan.fieldPatch[ConversationMutationField.avatar] as String?,
          ownerUserId: owner,
          snapshot: plan.fullSnapshot,
        );
        await acceptState(tombstoneGeneration: null);
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition: updated == null
              ? ConversationDatabaseCommitDisposition.noop
              : ConversationDatabaseCommitDisposition.applied,
          plan: plan,
          upsertedSnapshots: updated == null
              ? const <V2TimConversation>[]
              : <V2TimConversation>[updated],
          shouldNotifyUi: updated != null,
        );
      }
      final snapshot = plan.fullSnapshot;
      if (snapshot == null) {
        return ConversationDatabaseCommitResult<V2TimConversation>(
          disposition:
              ConversationDatabaseCommitDisposition.rejectedMissingSnapshot,
          plan: plan,
        );
      }
      final existed =
          await conversationById(canonicalId, ownerUserId: owner) != null;
      final upserted = await _upsertBatchImpl(
        conversations: <V2TimConversation>[snapshot],
        ownerUserId: owner,
      );
      await acceptState(tombstoneGeneration: null);
      return ConversationDatabaseCommitResult<V2TimConversation>(
        disposition: upserted.isEmpty
            ? ConversationDatabaseCommitDisposition.noop
            : ConversationDatabaseCommitDisposition.applied,
        plan: plan,
        upsertedSnapshots: upserted,
        shouldNotifyUi: upserted.isNotEmpty,
        structureChanged: !existed && upserted.isNotEmpty,
      );
    }

    final previousGeneration = state.generation;
    final previousTombstoneGeneration = state.tombstoneGeneration;
    state
      ..generation = plan.generation
      ..tombstoneGeneration = plan.generation;
    state.idempotencyKeys.add(plan.idempotencyKey);
    late final List<String> deleted;
    try {
      deleted = await _deleteWithCoordinatorState(
        owner: owner,
        canonicalConversationId: canonicalId,
        state: state,
      );
    } catch (_) {
      state
        ..generation = previousGeneration
        ..tombstoneGeneration = previousTombstoneGeneration;
      state.idempotencyKeys.remove(plan.idempotencyKey);
      rethrow;
    }
    return ConversationDatabaseCommitResult<V2TimConversation>(
      disposition: deleted.isEmpty
          ? ConversationDatabaseCommitDisposition.noop
          : ConversationDatabaseCommitDisposition.applied,
      plan: plan,
      deletedConversationIds: deleted,
      shouldNotifyUi: deleted.isNotEmpty,
    );
  }
~~~

66. [ConversationLocalStore.updateLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:8775>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，8775–8848 行。

~~~dart
Future<V2TimConversation?> updateLocalDraft({
    required String conversationID,
    required String draftText,
    String? ownerUserId,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return null;
    }
    final normalized = _normalizeDraftText(draftText);
    if (normalized.isEmpty) {
      return clearLocalDraft(conversationID: id, ownerUserId: ownerUserId);
    }
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return null;
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (_useMemoryOnly) {
      final list = List<V2TimConversation>.from(
        _memoryByOwner[owner] ?? const [],
      );
      final index = list.indexWhere((e) => e.conversationID == id);
      final conversation =
          index >= 0 ? list[index] : _minimalConversationForId(id);
      applyLocalDraftToConversation(
        conversation,
        text: normalized,
        updatedAtMs: nowMs,
      );
      if (index >= 0) {
        list[index] = conversation;
      } else {
        list.add(conversation);
      }
      list.sort(_sortConversations);
      _memoryByOwner[owner] = list;
      _decorateConversation(conversation);
      return conversation;
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _table,
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    final conversation = rows.isNotEmpty
        ? _conversationFromRow(rows.first)
        : _minimalConversationForId(id);
    if (conversation == null) {
      return null;
    }
    applyLocalDraftToConversation(
      conversation,
      text: normalized,
      updatedAtMs: nowMs,
    );
    await db.insert(
      _table,
      _rowFromConversation(
        owner,
        conversation,
        nowMs,
        readClearedAtMs:
            rows.isNotEmpty ? rows.first['read_cleared_at'] as int? ?? 0 : 0,
        localDraftText: normalized,
        localDraftUpdatedAtMs: nowMs,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _decorateConversation(conversation);
    return conversation;
  }
~~~

67. [ConversationLocalStore.clearLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:8850>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，8850–8905 行。

~~~dart
Future<V2TimConversation?> clearLocalDraft({
    required String conversationID,
    String? ownerUserId,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return null;
    }
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return null;
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (_useMemoryOnly) {
      final list = List<V2TimConversation>.from(
        _memoryByOwner[owner] ?? const [],
      );
      final index = list.indexWhere((e) => e.conversationID == id);
      if (index < 0) {
        return null;
      }
      applyLocalDraftToConversation(list[index], text: '', updatedAtMs: 0);
      _memoryByOwner[owner] = list;
      _decorateConversation(list[index]);
      return list[index];
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _table,
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final conversation = _conversationFromRow(rows.first);
    if (conversation == null) {
      return null;
    }
    applyLocalDraftToConversation(conversation, text: '', updatedAtMs: 0);
    await db.insert(
      _table,
      _rowFromConversation(
        owner,
        conversation,
        nowMs,
        readClearedAtMs: rows.first['read_cleared_at'] as int? ?? 0,
        localDraftText: '',
        localDraftUpdatedAtMs: 0,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _decorateConversation(conversation);
    return conversation;
  }
~~~

68. [ConversationLocalStore.localDraftTextFor](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:8907>)，原文件 lib/src/services/conversation_local/conversation_local_store.dart，8907–8939 行。

~~~dart
Future<String> localDraftTextFor({
    required String conversationID,
    String? ownerUserId,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return '';
    }
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return '';
    }
    if (_useMemoryOnly) {
      for (final item in _memoryByOwner[owner] ?? const <V2TimConversation>[]) {
        if (item.conversationID == id) {
          return _normalizeDraftText(item.draftText ?? '');
        }
      }
      return '';
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _table,
      columns: ['local_draft_text'],
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return '';
    }
    return _localDraftTextFromRow(rows.first);
  }
~~~

69. [ConversationMutationShadowBridge.restoreDurableConversationState](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart:70>)，原文件 lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart，70–93 行。

~~~dart
void restoreDurableConversationState({
    required String ownerUserId,
    required String conversationId,
    required int generation,
    required bool tombstoned,
  }) {
    final owner = ownerUserId.trim();
    final type = _conversationTypeFromId(conversationId);
    if (owner.isEmpty || type == null) {
      return;
    }
    _ensureOwner(owner);
    final canonical = canonicalizeConversationMutationId(conversationId, type);
    if (canonical.isEmpty) {
      return;
    }
    final current = _conversationGenerations[canonical] ?? 0;
    if (generation > current) {
      _conversationGenerations[canonical] = generation;
    }
    if (tombstoned) {
      _tombstoned.add(canonical);
    }
  }
~~~

70. [ConversationMutationShadowBridge.prepareLocalIntentCommit](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart:285>)，原文件 lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart，285–304 行。

~~~dart
/// Builds one typed local-intent plan. The Store remains the only place that
  /// interprets and persists [fieldPatch]; callers must not write the same
  /// field through a legacy Store API after consuming this plan.
  Future<ConversationDatabaseCommitPlan<V2TimConversation>?>
      prepareLocalIntentCommit({
    required String ownerUserId,
    required String conversationId,
    required Map<ConversationMutationField, Object?> fieldPatch,
    V2TimConversation? fullSnapshot,
    int? sourceVersion,
  }) {
    return prepareFieldPatchCommit(
      ownerUserId: ownerUserId,
      conversationId: conversationId,
      source: ConversationMutationSource.localIntent,
      fieldPatch: fieldPatch,
      fullSnapshot: fullSnapshot,
      sourceVersion: sourceVersion,
    );
  }
~~~

71. [ConversationMutationShadowBridge.prepareFieldPatchCommit](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart:306>)，原文件 lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart，306–352 行。

~~~dart
Future<ConversationDatabaseCommitPlan<V2TimConversation>?>
      prepareFieldPatchCommit({
    required String ownerUserId,
    required String conversationId,
    required ConversationMutationSource source,
    required Map<ConversationMutationField, Object?> fieldPatch,
    V2TimConversation? fullSnapshot,
    int? sourceVersion,
  }) async {
    final owner = ownerUserId.trim();
    final rawId = conversationId.trim();
    final type = _conversationTypeFromId(rawId);
    if (owner.isEmpty || rawId.isEmpty || type == null || fieldPatch.isEmpty) {
      return null;
    }
    _ensureOwner(owner);
    final canonical = canonicalizeConversationMutationId(rawId, type);
    if (canonical.isEmpty) {
      return null;
    }
    final sequence = ++_eventSequence;
    final eventVersion = sourceVersion != null && sourceVersion > sequence
        ? sourceVersion
        : sequence;
    final result =
        await _coordinator.submitForDatabaseCommit<V2TimConversation>(
      ConversationMutationEvent(
        eventId: _eventIdForFieldPatch(
          source: source,
          sequence: sequence,
          fieldPatch: fieldPatch,
        ),
        ownerUserId: owner,
        conversationId: canonical,
        conversationType: type,
        kind: ConversationMutationKind.patch,
        source: source,
        ownerGeneration: _ownerGeneration,
        conversationGeneration: _conversationGenerations[canonical] ?? 0,
        sourceVersion: eventVersion,
        values: fieldPatch,
      ),
      fullSnapshot: fullSnapshot,
      fieldPatch: fieldPatch,
    );
    return result.plan;
  }
~~~

72. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/outgoing_send_coordinator.dart:1>)，原文件 lib/src/services/im/outgoing_send_coordinator.dart，1–731 行。

~~~dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:crypto/crypto.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_message_adapter.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class ImCoordinatedSendResult {
  const ImCoordinatedSendResult({
    required this.sdkResult,
    required this.usedOutbox,
    this.identity,
    this.accountGeneration,
    this.domainGeneration,
    this.dispatchDecision,
    this.outcomeUnknown = false,
  });

  final V2TimValueCallback<V2TimMessage> sdkResult;
  final bool usedOutbox;
  final OutgoingIdentityContract? identity;
  final int? accountGeneration;
  final int? domainGeneration;
  final ImOutboxDispatchDecision? dispatchDecision;
  final bool outcomeUnknown;

  bool get canCompleteProjection =>
      usedOutbox && identity != null && sdkResult.code == 0;
}

class ImOutgoingSendCoordinator {
  ImOutgoingSendCoordinator._();

  static final ImOutgoingSendCoordinator instance =
      ImOutgoingSendCoordinator._();

  int _transientIngressSequence = 0;
  int _sendOperationGeneration = 0;

  Future<bool> abandonOutcomeUnknown({
    required String sdkLocalId,
    required String conversationId,
    required ImConversationType conversationType,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty) return false;
    final context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    if (context == null) return false;
    final scope = AccountScopedConversationKey.tryParse(
      ownerUserId: context.ownerUserId,
      conversationType: conversationType,
      conversationId: conversationId,
    );
    if (scope == null) return false;
    final persistence = Im05Persistence(store: context.store);
    // New sends use a UUID operation id, so resolve the durable row by the
    // provider-local id first. Keep the legacy hash fallback for rows written
    // by older app versions.
    final resolved = await persistence.findOutboxBySdkLocalId(
      ownerUserId: context.ownerUserId,
      conversationId: scope.storageKey,
      sdkLocalId: localId,
    );
    final operationId = resolved?.operationId ??
        hashOutgoingOperationId(scope: scope, sdkLocalId: localId);
    final assessment = await persistence.recoverOutbox(
      ownerUserId: context.ownerUserId,
      operationId: operationId,
    );
    final abandoned = await persistence.abandonOutcomeUnknown(
      ownerUserId: context.ownerUserId,
      operationId: operationId,
      leaseOwnerId: context.lease.leaseOwnerId,
      fencingToken: context.lease.fencingToken,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (abandoned) {
      await OutgoingMediaStager.instance.cleanup(
        assessment.main?.mediaLocalRef,
      );
    }
    return abandoned;
  }

  Future<ImCoordinatedSendResult> send({
    required MessageService messageService,
    required String sdkLocalId,
    required String conversationId,
    required ImConversationType conversationType,
    required String receiver,
    required String groupID,
    V2TimMessage? fallbackMessage,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool onlineUserOnly = false,
    bool isExcludedFromUnreadCount = false,
    bool needReadReceipt = false,
    OfflinePushInfo? offlinePushInfo,
    String? businessCloudCustomData,
    String? localCustomData,
    bool isExcludedFromContentModeration = false,
    bool persistOutbox = true,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    void Function(String syncMsgID)? onSyncMsgID,
    SessionIdentity? expectedSessionIdentity,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'sdkLocalId is required',
      );
    }
    final context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    if (expectedSessionIdentity != null &&
        (!SessionIdentityService.instance.isCurrent(expectedSessionIdentity) ||
            context?.ownerUserId != expectedSessionIdentity.ownerUserId ||
            context?.accountGeneration != expectedSessionIdentity.generation)) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'media send belongs to an earlier session',
      );
    }
    if (context == null) {
      // Keep this diagnostic next to the first pre-SDK return. A visible
      // optimistic bubble with no IM_SEND means the send stopped here.
      print(
          '[IM_SEND_BLOCKED] conversation=$conversationId reason=message_core_lease_unavailable');
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'message core lease unavailable',
      );
    }
    final scope = AccountScopedConversationKey.tryParse(
      ownerUserId: context.ownerUserId,
      conversationType: conversationType,
      conversationId: conversationId,
    );
    if (scope == null) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'invalid outgoing conversation scope',
      );
    }

    if (recoverPreparedOutbox && !persistOutbox) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'prepared recovery requires durable Outbox',
      );
    }
    if (!recoverPreparedOutbox &&
        ((operationIdOverride?.trim().isNotEmpty ?? false) ||
            (clientCorrelationIdOverride?.trim().isNotEmpty ?? false))) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'identity override is only valid for prepared recovery',
      );
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final persistence = Im05Persistence(store: context.store);
    final operationId = operationIdOverride?.trim().isNotEmpty == true
        ? operationIdOverride!.trim()
        : newOutgoingOperationId();
    final clientCorrelationId =
        clientCorrelationIdOverride?.trim().isNotEmpty == true
            ? clientCorrelationIdOverride!.trim()
            : newOutgoingClientCorrelationId();
    // The SDK-created local message is already the bubble adopted by the UI.
    // Recreating it here produces a second local id: the SDK sends that second
    // message while the visible bubble stays attached to the first one. This
    // is the root cause of duplicate media bubbles and media/audio rows stuck
    // in SENDING. Normal dispatch must always keep the original local id.
    final sendLocalId = localId;
    final sendMessage = fallbackMessage;
    var outboxMessage = fallbackMessage;
    String? stagedMediaRoot;
    if (persistOutbox && !recoverPreparedOutbox) {
      // Staging rewrites local paths. Apply that mutation only to a detached
      // Outbox copy so the live SDK/UI message continues to use its original
      // path and identity. Recovery may recreate an SDK message later from
      // this durable copy; the immediate send must not.
      outboxMessage = _cloneMessageForOutbox(fallbackMessage);
      if (fallbackMessage != null && outboxMessage == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          desc: 'outgoing message snapshot failed',
        );
      }
      final staged = await OutgoingMediaStager.instance.stageMessage(
        message: outboxMessage,
        operationId: operationId,
      );
      if (staged.shouldBlock) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          desc: 'outgoing media staging failed',
        );
      }
      stagedMediaRoot = staged.rootPath;
    }
    ImOutboxDispatchAssessment? recoveredPrepared;
    if (recoverPreparedOutbox) {
      recoveredPrepared = await persistence.assessOutboxForDispatch(
        ownerUserId: context.ownerUserId,
        operationId: operationId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: nowMs,
      );
      final recoveredMain = recoveredPrepared.main;
      if (!recoveredPrepared.canDispatch ||
          recoveredMain == null ||
          recoveredMain.state != ImOutboxState.prepared ||
          recoveredMain.operationId != operationId ||
          recoveredMain.clientCorrelationId != clientCorrelationId ||
          recoveredMain.conversationId != scope.storageKey) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          usedOutbox: true,
          decision: recoveredPrepared.decision,
          outcomeUnknown: recoveredPrepared.requiresOutcomeQuery,
          desc: 'prepared Outbox recovery identity rejected',
        );
      }
    }
    final messageKind = _messageKindFor(
      (outboxMessage ?? sendMessage)?.elemType,
    );
    final plaintextEnvelope = recoveredPrepared == null
        ? _encodeOutgoingEnvelope(
            message: outboxMessage,
            sdkLocalId: sendLocalId,
            conversationId: conversationId,
            receiver: receiver,
            groupID: groupID,
            priority: priority,
            onlineUserOnly: onlineUserOnly,
            isExcludedFromUnreadCount: isExcludedFromUnreadCount,
            needReadReceipt: needReadReceipt,
            offlinePushInfo: offlinePushInfo,
            businessCloudCustomData: businessCloudCustomData,
            localCustomData: localCustomData,
            isExcludedFromContentModeration: isExcludedFromContentModeration,
          )
        : null;
    final protectedPayload =
        persistOutbox && recoveredPrepared == null && plaintextEnvelope != null
            ? await OutboxPayloadCipher.instance.protect(
                ownerUserId: context.ownerUserId,
                plaintext: plaintextEnvelope,
              )
            : null;
    final payloadEnvelope = recoveredPrepared?.main?.payloadReference ??
        (persistOutbox ? protectedPayload?.value : plaintextEnvelope);
    if (persistOutbox && payloadEnvelope == null) {
      await OutgoingMediaStager.instance.cleanup(stagedMediaRoot);
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'durable outgoing payload is unavailable',
      );
    }
    // Hash the canonical plaintext envelope, not the AES-GCM ciphertext.
    // Encryption intentionally uses a fresh nonce on every send, so a
    // ciphertext hash would change even when the logical message is identical.
    final payloadFingerprint = recoveredPrepared?.main?.payloadHash ??
        sha256
            .convert(
                utf8.encode(plaintextEnvelope ?? 'sdkLocalId:$sendLocalId'))
            .toString();
    if (recoveredPrepared != null &&
        recoveredPrepared.main!.payloadHash != payloadFingerprint) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        usedOutbox: true,
        decision: ImOutboxDispatchDecision.identityConflict,
        desc: 'prepared Outbox payload fingerprint rejected',
      );
    }
    final identity = OutgoingIdentityContract(
      scope: scope,
      operationId: operationId,
      clientCorrelationId: clientCorrelationId,
      messageKind: messageKind,
      payloadFingerprint: payloadFingerprint,
      createdAtMs: recoveredPrepared?.main?.createdAtMs ?? nowMs,
      sdkLocalId: sendLocalId,
    );
    final sendGeneration = ++_sendOperationGeneration;

    if (persistOutbox) {
      final main = ImOutboxRecord(
        operationId: identity.operationId,
        ownerUserId: context.ownerUserId,
        conversationId: scope.storageKey,
        clientCorrelationId: identity.clientCorrelationId,
        messageType:
            (outboxMessage ?? sendMessage)?.elemType ?? messageKind.index,
        payloadReference: payloadEnvelope!,
        mediaLocalRef: stagedMediaRoot ??
            _mediaLocalReference(outboxMessage ?? sendMessage),
        encryptionVersion: recoveredPrepared?.main?.encryptionVersion ??
            (protectedPayload == null
                ? null
                : ProtectedOutboxPayload.encryptionVersion),
        keyId: recoveredPrepared?.main?.keyId ?? protectedPayload?.keyId,
        cipherAlgorithm: recoveredPrepared?.main?.cipherAlgorithm ??
            (protectedPayload == null
                ? null
                : ProtectedOutboxPayload.cipherAlgorithm),
        nonce: recoveredPrepared?.main?.nonce ?? protectedPayload?.nonce,
        payloadHash: identity.payloadFingerprint,
        contentChecksum: identity.payloadFingerprint,
        sdkMessageId: sendLocalId,
        state: ImOutboxState.prepared,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );
      final recovery = ImOutboxRecoveryRecord(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
        clientCorrelationId: identity.clientCorrelationId,
        conversationId: scope.storageKey,
        messageType: main.messageType,
        recoveryRevision: 1,
        state: ImOutboxCopyState.copyPrepared,
        payloadReferenceOrCiphertext: payloadEnvelope,
        payloadHash: identity.payloadFingerprint,
        checksum: identity.payloadFingerprint,
        sdkLocalId: sendLocalId,
        updatedAtMs: nowMs,
      );
      final prepared = recoveredPrepared ??
          await persistence.prepareOutbox(
            main: main,
            recoveryCopy: recovery,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: nowMs,
          );
      if (!prepared.canDispatch) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: prepared.decision,
          outcomeUnknown: prepared.requiresOutcomeQuery,
          desc: 'outbox dispatch rejected: ${prepared.decision.name}',
        );
      }
      final dispatch = await persistence.recordDispatchIntent(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
        dispatchAttemptId:
            'attempt:${identity.operationId}:$sendGeneration:$nowMs',
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: nowMs,
      );
      if (!dispatch.canDispatch || dispatch.main == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: dispatch.decision,
          outcomeUnknown: dispatch.requiresOutcomeQuery,
          desc: 'outbox dispatch rejected: ${dispatch.decision.name}',
        );
      }
      final sending = await persistence.transitionOutbox(
        next: dispatch.main!.copyWith(
          state: ImOutboxState.sending,
          sdkMessageId: sendLocalId,
        ),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (sending == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: ImOutboxDispatchDecision.fencingRejected,
          desc: 'outbox sending transition rejected',
        );
      }
    }

    final adapter = TencentMessageAdapter(
      port: TUIKitMessageServicePort(messageService),
      platform: ImPlatform.unknown,
      ownerUserId: context.ownerUserId,
      accountGeneration: context.accountGeneration,
      domainGeneration: context.domainGeneration,
      nextAccountIngressSequence: _nextTransientIngressSequence,
      nextScopeIngressSequence: (_) => _nextTransientIngressSequence(),
      onSyncIdentity: (event) {
        final serverId = event.payload?.serverMsgId?.trim() ?? '';
        if (serverId.isNotEmpty) {
          onSyncMsgID?.call(serverId);
        }
      },
    );
    final sdk = await adapter.send(
      identity: identity,
      sdkLocalId: sendLocalId,
      receiver: receiver,
      groupID: groupID,
      sendOperationGeneration: sendGeneration,
      priority: priority,
      onlineUserOnly: onlineUserOnly,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount,
      needReadReceipt: needReadReceipt,
      offlinePushInfo: offlinePushInfo,
      businessCloudCustomData: businessCloudCustomData,
      localCustomData: localCustomData,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
    );

    final formalIdentity = sdk.data?.identity ?? identity;
    var callback = V2TimValueCallback<V2TimMessage>(
      code: sdk.code ?? (sdk.isSuccess ? 0 : -1),
      desc: sdk.resultDesc ?? '',
      data: sdk.data?.message ?? sendMessage ?? fallbackMessage,
    );
    var providerConfirmed = false;
    if (persistOutbox) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (sdk.isSuccess) {
        await persistence.recordOutboxSdkSucceeded(
          ownerUserId: context.ownerUserId,
          operationId: identity.operationId,
          leaseOwnerId: context.lease.leaseOwnerId,
          fencingToken: context.lease.fencingToken,
          nowMs: now,
          sdkLocalId: sendLocalId,
          serverMsgId: formalIdentity.serverMsgId,
          resultCode: '${callback.code}',
        );
      } else if (sdk.isOutcomeUnknown) {
        final recorded = await persistence.recordOutcomeUnknown(
          ownerUserId: context.ownerUserId,
          operationId: identity.operationId,
          leaseOwnerId: context.lease.leaseOwnerId,
          fencingToken: context.lease.fencingToken,
          nowMs: now,
          resultCode: '${callback.code}',
        );
        if (!recorded) {
          providerConfirmed = await _providerAlreadyConfirmed(
            persistence,
            ownerUserId: context.ownerUserId,
            operationId: identity.operationId,
          );
        }
      } else {
        unawaited(() async {
          try {
            await persistence.recordOutboxSdkFailed(
              ownerUserId: context.ownerUserId,
              operationId: identity.operationId,
              leaseOwnerId: context.lease.leaseOwnerId,
              fencingToken: context.lease.fencingToken,
              nowMs: now,
              sdkLocalId: sendLocalId,
              serverMsgId: formalIdentity.serverMsgId,
              resultCode: '${callback.code}',
            );
          } catch (error) {
            debugPrint(
              '[IM_SEND_COORDINATOR] recordOutboxSdkFailed error=$error',
            );
          }
        }());
      }
    }
    if (providerConfirmed) {
      callback = V2TimValueCallback<V2TimMessage>(
        code: 0,
        desc: 'provider evidence confirmed delivery',
        data: sdk.data?.message ?? fallbackMessage,
      );
    }
    return ImCoordinatedSendResult(
      sdkResult: callback,
      usedOutbox: persistOutbox,
      identity: formalIdentity,
      accountGeneration: context.accountGeneration,
      domainGeneration: context.domainGeneration,
      outcomeUnknown: sdk.isOutcomeUnknown && !providerConfirmed,
    );
  }

  Future<bool> completeSuccessfulProjection(
    ImCoordinatedSendResult result,
  ) async {
    final identity = result.identity;
    if (!result.canCompleteProjection || identity == null) return false;
    final context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    if (context == null ||
        context.ownerUserId != identity.scope.ownerUserId ||
        context.accountGeneration != result.accountGeneration ||
        context.domainGeneration != result.domainGeneration) {
      return false;
    }
    final persistence = Im05Persistence(store: context.store);
    final assessment = await persistence.recoverOutbox(
      ownerUserId: context.ownerUserId,
      operationId: identity.operationId,
    );
    final completed = await persistence.completeOutboxProjection(
      ownerUserId: context.ownerUserId,
      operationId: identity.operationId,
      leaseOwnerId: context.lease.leaseOwnerId,
      fencingToken: context.lease.fencingToken,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (completed) {
      await OutgoingMediaStager.instance.cleanup(
        assessment.main?.mediaLocalRef,
      );
    }
    return completed;
  }

  /// Reconciles durable unknown sends from an already-committed history page.
  /// Only self messages carrying the exact outgoing identity envelope can
  /// advance an Outbox row.
  Future<int> adoptProviderHistory(
    Iterable<V2TimMessage> messages,
  ) async {
    final context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    if (context == null) return 0;
    final persistence = Im05Persistence(store: context.store);
    var adoptedCount = 0;
    for (final message in messages) {
      if (message.isSelf != true) continue;
      final conversationId = MessageConversationId.fromMessage(
        message,
        loginUserId: context.ownerUserId,
      );
      if (conversationId == null) continue;
      final scope = AccountScopedConversationKey.tryParse(
        ownerUserId: context.ownerUserId,
        conversationType: conversationId.startsWith('group_')
            ? ImConversationType.group
            : ImConversationType.c2c,
        conversationId: conversationId,
      );
      if (scope == null) continue;
      final outgoing = OutgoingIdentityContract.fromCloudCustomData(
        message.cloudCustomData,
        scope: scope,
      );
      if (outgoing == null) continue;
      final adopted = await persistence.adoptOutboxProviderSucceeded(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
        clientCorrelationId: outgoing.clientCorrelationId,
        conversationId: scope.storageKey,
        payloadHash: outgoing.payloadFingerprint,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        sdkLocalId: message.id,
        serverMsgId: message.msgID,
      );
      if (!adopted) continue;
      final assessment = await persistence.recoverOutbox(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
      );
      final completed = await persistence.completeOutboxProjection(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (completed) {
        await OutgoingMediaStager.instance.cleanup(
          assessment.main?.mediaLocalRef,
        );
        adoptedCount++;
      }
    }
    return adoptedCount;
  }

  int _nextTransientIngressSequence() => ++_transientIngressSequence;
}

Future<bool> _providerAlreadyConfirmed(
  Im05Persistence persistence, {
  required String ownerUserId,
  required String operationId,
}) async {
  final assessment = await persistence.recoverOutbox(
    ownerUserId: ownerUserId,
    operationId: operationId,
  );
  return assessment.main?.state == ImOutboxState.acknowledged ||
      assessment.main?.state == ImOutboxState.completed;
}

ImCoordinatedSendResult _blocked({
  required V2TimMessage? fallbackMessage,
  OutgoingIdentityContract? identity,
  bool usedOutbox = false,
  ImOutboxDispatchDecision? decision,
  bool outcomeUnknown = false,
  required String desc,
}) {
  return ImCoordinatedSendResult(
    sdkResult: V2TimValueCallback<V2TimMessage>(
      code: -1,
      desc: desc,
      data: fallbackMessage,
    ),
    usedOutbox: usedOutbox,
    identity: identity,
    dispatchDecision: decision,
    outcomeUnknown: outcomeUnknown,
  );
}

V2TimMessage? _cloneMessageForOutbox(V2TimMessage? message) {
  if (message == null) return null;
  try {
    return V2TimMessage.fromJson(
      Map<String, dynamic>.from(message.toJson()),
    );
  } catch (_) {
    return null;
  }
}

String? _encodeOutgoingEnvelope({
  required V2TimMessage? message,
  required String sdkLocalId,
  required String conversationId,
  required String receiver,
  required String groupID,
  required MessagePriorityEnum priority,
  required bool onlineUserOnly,
  required bool isExcludedFromUnreadCount,
  required bool needReadReceipt,
  required OfflinePushInfo? offlinePushInfo,
  required String? businessCloudCustomData,
  required String? localCustomData,
  required bool isExcludedFromContentModeration,
}) {
  if (message == null) return null;
  try {
    return jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'sdkLocalId': sdkLocalId.trim(),
      'conversationId': conversationId.trim(),
      'receiver': receiver.trim(),
      'groupID': groupID.trim(),
      'priority': priority.index,
      'onlineUserOnly': onlineUserOnly,
      'isExcludedFromUnreadCount': isExcludedFromUnreadCount,
      'needReadReceipt': needReadReceipt,
      'offlinePushInfo': offlinePushInfo?.toJson(),
      'businessCloudCustomData': businessCloudCustomData,
      'localCustomData': localCustomData,
      'isExcludedFromContentModeration': isExcludedFromContentModeration,
      // V2TimMessage.fromJson can rebuild the SDK-created local message after
      // a process restart. Media paths are retained separately as well.
      'message': message.toJson(),
    });
  } catch (_) {
    return null;
  }
}

String? _mediaLocalReference(V2TimMessage? message) {
  final candidates = <String?>[
    message?.imageElem?.path,
    message?.videoElem?.videoPath,
    message?.videoElem?.snapshotPath,
    message?.soundElem?.path,
    message?.fileElem?.path,
  ];
  for (final candidate in candidates) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

OutgoingMessageKind _messageKindFor(int? elemType) {
  switch (elemType) {
    case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
      return OutgoingMessageKind.text;
    case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      return OutgoingMessageKind.image;
    case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
      return OutgoingMessageKind.video;
    case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
      return OutgoingMessageKind.audio;
    default:
      return OutgoingMessageKind.custom;
  }
}

~~~

73. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im05_persistence.dart:1>)，原文件 lib/src/services/im/im05_persistence.dart，1–1509 行。

~~~dart
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';

/// First-round persistence coordinator for Commit Journal, Projection
/// Checkpoint, Effect Ledger, and the two-sided Outbox prepare boundary.
///
/// This class owns protocol decisions only. The actual database owner remains
/// [ConversationLocalStore] through [ImIngressStore.transaction].
class Im05Persistence {
  Im05Persistence({required ImIngressStore store}) : _store = store;

  final ImIngressStore _store;

  Future<List<ImOutboxRecord>> listOutboxesForRecovery({
    required String ownerUserId,
    required List<ImOutboxState> states,
    int limit = 100,
  }) {
    return _store.transaction<List<ImOutboxRecord>>(
      (transaction) => transaction.listOutboxesForRecovery(
        ownerUserId: ownerUserId,
        states: states,
        limit: limit,
      ),
    );
  }

  Future<ImOutboxRecord?> findOutboxBySdkLocalId({
    required String ownerUserId,
    required String conversationId,
    required String sdkLocalId,
  }) {
    return _store.transaction<ImOutboxRecord?>(
        (transaction) => transaction.findOutboxBySdkLocalId(
              ownerUserId: ownerUserId,
              conversationId: conversationId,
              sdkLocalId: sdkLocalId,
            ));
  }

  /// Persists the Journal's explicit PREPARED marker. The Inbox remains the
  /// event recovery anchor, but this marker makes the Journal state machine
  /// observable to recovery and contract tests.
  Future<ImCommitJournalRecord?> prepareJournal({
    required ImCommitJournalRecord record,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (record.state != ImCommitJournalState.prepared) {
      throw ArgumentError('prepareJournal requires prepared state');
    }
    return _store.transaction<ImCommitJournalRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findCommitJournal(
        ownerUserId: record.ownerUserId,
        journalId: record.journalId,
      );
      if (current != null) {
        _checkJournalIdentity(current, record);
        return current;
      }
      final prepared = record.copyWith(
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final inserted = await transaction.insertCommitJournalIfAbsent(prepared);
      if (inserted) return prepared;
      final duplicate = await transaction.findCommitJournal(
        ownerUserId: record.ownerUserId,
        journalId: record.journalId,
      );
      if (duplicate != null) _checkJournalIdentity(duplicate, record);
      return duplicate;
    });
  }

  Future<ImCommitJournalRecord?> commitMetadata({
    required ImCommitJournalRecord record,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (record.state != ImCommitJournalState.metadataCommitted) {
      throw ArgumentError('commitMetadata requires metadataCommitted state');
    }
    return _store.transaction<ImCommitJournalRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findCommitJournal(
        ownerUserId: record.ownerUserId,
        journalId: record.journalId,
      );
      var prepared = current;
      if (prepared == null) {
        final preparedRecord = record.copyWith(
          state: ImCommitJournalState.prepared,
          updatedAtMs: nowMs,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
        );
        final inserted = await transaction.insertCommitJournalIfAbsent(
          preparedRecord,
        );
        prepared = inserted
            ? preparedRecord
            : await transaction.findCommitJournal(
                ownerUserId: record.ownerUserId,
                journalId: record.journalId,
              );
      }
      if (prepared == null) return null;
      _checkJournalIdentity(prepared, record);
      if (prepared.state == ImCommitJournalState.metadataCommitted ||
          prepared.state == ImCommitJournalState.projectionPublished ||
          prepared.state == ImCommitJournalState.completed) {
        return prepared;
      }
      if (prepared.state != ImCommitJournalState.prepared) return null;
      final metadata = record.copyWith(
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final advanced = await transaction.updateCommitJournalIfCurrent(
        record: metadata,
        expectedState: ImCommitJournalState.prepared,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return advanced ? metadata : null;
    });
  }

  /// Saves the checkpoint and publishes the Journal stage in one transaction.
  /// A stale checkpoint or fencing token is rejected without changing either
  /// record.
  Future<ImCommitJournalRecord?> publishProjection({
    required ImCommitJournalRecord journal,
    required ImProjectionCheckpointRecord checkpoint,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<ImCommitJournalRecord?>((transaction) async {
      if (!await _hasCurrentLease(transaction, journal.ownerUserId,
          leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findCommitJournal(
        ownerUserId: journal.ownerUserId,
        journalId: journal.journalId,
      );
      if (current == null) return null;
      _checkJournalIdentity(current, journal);
      if (current.state == ImCommitJournalState.projectionPublished ||
          current.state == ImCommitJournalState.completed) {
        _checkCheckpointIdentity(checkpoint, journal);
        final persistedCheckpoint = await transaction.findProjectionCheckpoint(
          ownerUserId: checkpoint.ownerUserId,
          scope: checkpoint.scope,
        );
        if (persistedCheckpoint == null) return null;
        if (!_sameCheckpointValue(persistedCheckpoint, checkpoint)) {
          throw const Im05IdentityConflictException(
            'projection checkpoint conflict',
          );
        }
        return current;
      }
      if (current.state != ImCommitJournalState.metadataCommitted) {
        return null;
      }
      _checkCheckpointIdentity(checkpoint, journal);
      final checkpointToSave = ImProjectionCheckpointRecord(
        ownerUserId: checkpoint.ownerUserId,
        scope: checkpoint.scope,
        commitRevision: checkpoint.commitRevision,
        lastJournalId: checkpoint.lastJournalId,
        coverageRevision: checkpoint.coverageRevision,
        watermarkRevision: checkpoint.watermarkRevision,
        barrierRevision: checkpoint.barrierRevision,
        projectionVersion: checkpoint.projectionVersion,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final saved = await transaction.saveProjectionCheckpointIfCurrent(
        record: checkpointToSave,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      if (!saved) return null;
      final projected = current.copyWith(
        state: ImCommitJournalState.projectionPublished,
        projectionRevision: checkpoint.commitRevision,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final advanced = await transaction.updateCommitJournalIfCurrent(
        record: projected,
        expectedState: ImCommitJournalState.metadataCommitted,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return advanced ? projected : null;
    });
  }

  Future<ImCommitJournalRecord?> completeJournal({
    required String ownerUserId,
    required String journalId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    int? sideEffectRevision,
  }) {
    return _store.transaction<ImCommitJournalRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findCommitJournal(
        ownerUserId: ownerUserId,
        journalId: journalId,
      );
      if (current == null) return null;
      if (current.state == ImCommitJournalState.completed) return current;
      if (current.state != ImCommitJournalState.projectionPublished) {
        return null;
      }
      final completed = current.copyWith(
        state: ImCommitJournalState.completed,
        sideEffectRevision: sideEffectRevision ?? current.sideEffectRevision,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final advanced = await transaction.updateCommitJournalIfCurrent(
        record: completed,
        expectedState: ImCommitJournalState.projectionPublished,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return advanced ? completed : null;
    });
  }

  Future<ImOutboxRecord?> transitionOutbox({
    required ImOutboxRecord next,
    required ImOutboxState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (!isValidImOutboxTransition(expectedState, next.state)) {
      throw ArgumentError.value(
        next.state,
        'next.state',
        'is not valid after $expectedState',
      );
    }
    return _store.transaction<ImOutboxRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, next.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findOutbox(
        ownerUserId: next.ownerUserId,
        operationId: next.operationId,
      );
      if (current == null) return null;
      _checkOutboxRecordIdentity(current, next);
      if (current.state == next.state) return current;
      if (current.state != expectedState) return null;
      final persisted = next.copyWith(
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final changed = await transaction.updateOutboxIfCurrent(
        record: persisted,
        expectedState: expectedState,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return changed ? persisted : null;
    });
  }

  Future<ImOutboxRecoveryRecord?> transitionOutboxRecoveryCopy({
    required ImOutboxRecoveryRecord next,
    required ImOutboxCopyState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (!isValidImOutboxRecoveryTransition(expectedState, next.state)) {
      throw ArgumentError.value(
        next.state,
        'next.state',
        'is not valid after $expectedState',
      );
    }
    return _store.transaction<ImOutboxRecoveryRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, next.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findOutboxRecovery(
        ownerUserId: next.ownerUserId,
        operationId: next.operationId,
      );
      if (current == null) return null;
      _checkRecoveryIdentity(current, next);
      if (current.state == next.state) return current;
      if (current.state != expectedState) return null;
      final persisted = ImOutboxRecoveryRecord(
        ownerUserId: next.ownerUserId,
        operationId: next.operationId,
        clientCorrelationId: next.clientCorrelationId,
        conversationId: next.conversationId,
        messageType: next.messageType,
        recoveryRevision: next.recoveryRevision,
        state: next.state,
        dispatchAttemptId: next.dispatchAttemptId,
        dispatchIntentAtMs: next.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: next.payloadReferenceOrCiphertext,
        payloadHash: next.payloadHash,
        checksum: next.checksum,
        sdkLocalId: next.sdkLocalId,
        serverMsgId: next.serverMsgId,
        resultCode: next.resultCode,
        updatedAtMs: nowMs,
      );
      final changed = await transaction.updateOutboxRecoveryIfCurrent(
        record: persisted,
        expectedState: expectedState,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return changed ? persisted : null;
    });
  }

  Future<ImEffectLedgerRecord?> ensureEffect({
    required ImEffectLedgerRecord record,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<ImEffectLedgerRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findEffect(
        ownerUserId: record.ownerUserId,
        effectId: record.effectId,
      );
      if (current != null) {
        if (current.journalId != record.journalId ||
            current.effectKind != record.effectKind) {
          throw const Im05IdentityConflictException('effect identity conflict');
        }
        return current;
      }
      final persisted = ImEffectLedgerRecord(
        ownerUserId: record.ownerUserId,
        effectId: record.effectId,
        journalId: record.journalId,
        effectKind: record.effectKind,
        state: ImEffectLedgerState.pending,
        attemptCount: record.attemptCount,
        lastError: record.lastError,
        createdAtMs: record.createdAtMs,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final inserted = await transaction.insertEffectIfAbsent(persisted);
      if (inserted) return persisted;
      return transaction.findEffect(
        ownerUserId: record.ownerUserId,
        effectId: record.effectId,
      );
    });
  }

  Future<ImEffectLedgerRecord?> startEffect({
    required String ownerUserId,
    required String effectId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<ImEffectLedgerRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findEffect(
        ownerUserId: ownerUserId,
        effectId: effectId,
      );
      if (current == null) return null;
      if (current.state == ImEffectLedgerState.running ||
          current.state == ImEffectLedgerState.completed ||
          current.state == ImEffectLedgerState.failed) {
        return current;
      }
      final running = ImEffectLedgerRecord(
        ownerUserId: current.ownerUserId,
        effectId: current.effectId,
        journalId: current.journalId,
        effectKind: current.effectKind,
        state: ImEffectLedgerState.running,
        attemptCount: current.attemptCount + 1,
        lastError: null,
        createdAtMs: current.createdAtMs,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final changed = await transaction.updateEffectIfCurrent(
        record: running,
        expectedState: ImEffectLedgerState.pending,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return changed ? running : null;
    });
  }

  Future<ImEffectLedgerRecord?> finishEffect({
    required String ownerUserId,
    required String effectId,
    required bool succeeded,
    String? error,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<ImEffectLedgerRecord?>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return null;
      }
      final current = await transaction.findEffect(
        ownerUserId: ownerUserId,
        effectId: effectId,
      );
      if (current == null) return null;
      if (current.state == ImEffectLedgerState.completed ||
          current.state == ImEffectLedgerState.failed) {
        return current;
      }
      if (current.state != ImEffectLedgerState.running) return null;
      final finished = ImEffectLedgerRecord(
        ownerUserId: current.ownerUserId,
        effectId: current.effectId,
        journalId: current.journalId,
        effectKind: current.effectKind,
        state: succeeded
            ? ImEffectLedgerState.completed
            : ImEffectLedgerState.failed,
        attemptCount: current.attemptCount,
        lastError: succeeded ? null : error,
        createdAtMs: current.createdAtMs,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final changed = await transaction.updateEffectIfCurrent(
        record: finished,
        expectedState: ImEffectLedgerState.running,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      return changed ? finished : null;
    });
  }

  /// Persists both sides of the Prepared boundary before any SDK call.
  Future<ImOutboxDispatchAssessment> prepareOutbox({
    required ImOutboxRecord main,
    required ImOutboxRecoveryRecord recoveryCopy,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (main.state != ImOutboxState.prepared ||
        recoveryCopy.state != ImOutboxCopyState.copyPrepared) {
      throw ArgumentError('prepareOutbox requires both Prepared states');
    }
    return _store.transaction<ImOutboxDispatchAssessment>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, main.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return const ImOutboxDispatchAssessment(
          decision: ImOutboxDispatchDecision.fencingRejected,
        );
      }
      if (!_sameOutboxIdentity(main, recoveryCopy)) {
        throw const Im05IdentityConflictException('outbox identity conflict');
      }
      final currentMain = await transaction.findOutbox(
        ownerUserId: main.ownerUserId,
        operationId: main.operationId,
      );
      final currentCopy = await transaction.findOutboxRecovery(
        ownerUserId: recoveryCopy.ownerUserId,
        operationId: recoveryCopy.operationId,
      );
      if (currentMain == null) {
        await transaction.insertOutboxIfAbsent(main.copyWith(
          updatedAtMs: nowMs,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
        ));
      } else if (!_sameOutboxIdentity(currentMain, recoveryCopy)) {
        throw const Im05IdentityConflictException('main outbox conflict');
      }
      if (currentCopy == null) {
        await transaction.insertOutboxRecoveryIfAbsent(recoveryCopy);
      } else if (!_sameRecoveryIdentity(currentCopy, recoveryCopy)) {
        throw const Im05IdentityConflictException(
            'outbox recovery copy conflict');
      }
      return _assess(
        main: await transaction.findOutbox(
          ownerUserId: main.ownerUserId,
          operationId: main.operationId,
        ),
        recoveryCopy: await transaction.findOutboxRecovery(
          ownerUserId: main.ownerUserId,
          operationId: main.operationId,
        ),
        leaseValid: true,
      );
    });
  }

  /// Returns whether a fresh SDK dispatch is permitted. A recorded Intent is
  /// deliberately classified as OutcomeUnknown and never becomes dispatchable
  /// through recovery.
  Future<ImOutboxDispatchAssessment> assessOutboxForDispatch({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<ImOutboxDispatchAssessment>((transaction) async {
      final leaseValid = await _hasCurrentLease(
        transaction,
        ownerUserId,
        leaseOwnerId,
        fencingToken,
        nowMs,
      );
      return _assess(
        main: await transaction.findOutbox(
          ownerUserId: ownerUserId,
          operationId: operationId,
        ),
        recoveryCopy: await transaction.findOutboxRecovery(
          ownerUserId: ownerUserId,
          operationId: operationId,
        ),
        leaseValid: leaseValid,
      );
    });
  }

  /// Records the single dispatch decision after both Prepared records agree.
  /// The returned `ready` assessment means the caller may make the one SDK
  /// call for this dispatch attempt. After a crash, re-assessment is
  /// `outcomeUnknown` and cannot be used to send again.
  Future<ImOutboxDispatchAssessment> recordDispatchIntent({
    required String ownerUserId,
    required String operationId,
    required String dispatchAttemptId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    if (dispatchAttemptId.trim().isEmpty) {
      throw ArgumentError.value(
        dispatchAttemptId,
        'dispatchAttemptId',
        'must not be empty',
      );
    }
    return _store.transaction<ImOutboxDispatchAssessment>((transaction) async {
      final assessment = _assess(
        main: await transaction.findOutbox(
          ownerUserId: ownerUserId,
          operationId: operationId,
        ),
        recoveryCopy: await transaction.findOutboxRecovery(
          ownerUserId: ownerUserId,
          operationId: operationId,
        ),
        leaseValid: await _hasCurrentLease(
          transaction,
          ownerUserId,
          leaseOwnerId,
          fencingToken,
          nowMs,
        ),
      );
      if (!assessment.canDispatch) return assessment;
      final main = assessment.main!;
      final copy = assessment.recoveryCopy!;
      final intentMain = main.copyWith(
        state: ImOutboxState.dispatchIntent,
        dispatchAttemptId: dispatchAttemptId,
        dispatchIntentAtMs: nowMs,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final intentCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId,
        operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId,
        conversationId: copy.conversationId,
        messageType: copy.messageType,
        recoveryRevision: copy.recoveryRevision + 1,
        state: ImOutboxCopyState.dispatchIntent,
        dispatchAttemptId: dispatchAttemptId,
        dispatchIntentAtMs: nowMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash,
        checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId,
        serverMsgId: copy.serverMsgId,
        resultCode: copy.resultCode,
        updatedAtMs: nowMs,
      );
      final mainChanged = await transaction.updateOutboxIfCurrent(
        record: intentMain,
        expectedState: ImOutboxState.prepared,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
        record: intentCopy,
        expectedState: ImOutboxCopyState.copyPrepared,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      if (!mainChanged || !copyChanged) {
        return const ImOutboxDispatchAssessment(
          decision: ImOutboxDispatchDecision.recoveryConflict,
        );
      }
      return ImOutboxDispatchAssessment(
        decision: ImOutboxDispatchDecision.ready,
        main: intentMain,
        recoveryCopy: intentCopy,
      );
    });
  }

  /// Marks a recorded Intent as unknown on both ledgers. This is the only
  /// recovery transition exposed here; it never invokes the SDK.
  Future<bool> recordOutcomeUnknown({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    String? resultCode,
  }) {
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null ||
          copy == null ||
          main.dispatchAttemptId != copy.dispatchAttemptId) {
        return false;
      }
      if (main.state == ImOutboxState.outcomeUnknown &&
          copy.state == ImOutboxCopyState.outcomeUnknown) {
        return true;
      }
      if ((main.state != ImOutboxState.dispatchIntent &&
              main.state != ImOutboxState.sending) ||
          (copy.state != ImOutboxCopyState.dispatchIntent &&
              copy.state != ImOutboxCopyState.outcomeUnknown)) {
        return false;
      }
      final unknownMain = main.copyWith(
        state: ImOutboxState.outcomeUnknown,
        resultCode: resultCode ?? main.resultCode,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      final unknownCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId,
        operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId,
        conversationId: copy.conversationId,
        messageType: copy.messageType,
        recoveryRevision: copy.recoveryRevision + 1,
        state: ImOutboxCopyState.outcomeUnknown,
        dispatchAttemptId: copy.dispatchAttemptId,
        dispatchIntentAtMs: copy.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash,
        checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId,
        serverMsgId: copy.serverMsgId,
        resultCode: resultCode ?? copy.resultCode,
        updatedAtMs: nowMs,
      );
      final mainChanged = await transaction.updateOutboxIfCurrent(
        record: unknownMain,
        expectedState: main.state,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      final copyChanged = copy.state == ImOutboxCopyState.outcomeUnknown
          ? true
          : await transaction.updateOutboxRecoveryIfCurrent(
              record: unknownCopy,
              expectedState: ImOutboxCopyState.dispatchIntent,
              leaseOwnerId: leaseOwnerId,
              fencingToken: fencingToken,
              nowMs: nowMs,
            );
      return mainChanged && copyChanged;
    });
  }

  /// Stops automatic recovery when a Prepared operation cannot be decoded or
  /// recreated. No SDK dispatch happened, so this must never become
  /// OutcomeUnknown or enter an automatic retry loop.
  Future<bool> markPreparedOutboxManualRequired({
    required String ownerUserId,
    required String operationId,
    required String reason,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must not be empty');
    }
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null || copy == null || !_sameOutboxIdentity(main, copy)) {
        return false;
      }
      if (main.state == ImOutboxState.manualRequired &&
          copy.state == ImOutboxCopyState.manualRequired) {
        return true;
      }
      if (main.state != ImOutboxState.prepared ||
          copy.state != ImOutboxCopyState.copyPrepared) {
        return false;
      }
      final manualCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId,
        operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId,
        conversationId: copy.conversationId,
        messageType: copy.messageType,
        recoveryRevision: copy.recoveryRevision + 1,
        state: ImOutboxCopyState.manualRequired,
        dispatchAttemptId: copy.dispatchAttemptId,
        dispatchIntentAtMs: copy.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash,
        checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId,
        serverMsgId: copy.serverMsgId,
        resultCode: normalizedReason,
        updatedAtMs: nowMs,
      );
      final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
        record: manualCopy,
        expectedState: ImOutboxCopyState.copyPrepared,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      if (!copyChanged) return false;
      return transaction.updateOutboxIfCurrent(
        record: main.copyWith(
          state: ImOutboxState.manualRequired,
          resultCode: normalizedReason,
          updatedAtMs: nowMs,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
        ),
        expectedState: ImOutboxState.prepared,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
    });
  }

  /// Closes an unresolved send only after the user explicitly gives up
  /// waiting. This never implies that the provider rejected the original
  /// operation; a later retry must use a new operation identity.
  Future<bool> abandonOutcomeUnknown({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null ||
          copy == null ||
          !_sameOutboxIdentity(main, copy) ||
          main.state != ImOutboxState.outcomeUnknown ||
          copy.state != ImOutboxCopyState.outcomeUnknown) {
        return false;
      }
      final reconciledCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId,
        operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId,
        conversationId: copy.conversationId,
        messageType: copy.messageType,
        recoveryRevision: copy.recoveryRevision + 1,
        state: ImOutboxCopyState.reconciled,
        dispatchAttemptId: copy.dispatchAttemptId,
        dispatchIntentAtMs: copy.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash,
        checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId,
        serverMsgId: copy.serverMsgId,
        resultCode: 'abandoned_by_user',
        updatedAtMs: nowMs,
      );
      final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
        record: reconciledCopy,
        expectedState: ImOutboxCopyState.outcomeUnknown,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      if (!copyChanged) return false;
      return transaction.updateOutboxIfCurrent(
        record: main.copyWith(
          state: ImOutboxState.abandonedByUser,
          resultCode: 'abandoned_by_user',
          updatedAtMs: nowMs,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
        ),
        expectedState: ImOutboxState.outcomeUnknown,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
    });
  }

  Future<bool> recordOutboxSdkSucceeded({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    String? sdkLocalId,
    String? serverMsgId,
    String? resultCode,
  }) {
    return _recordOutboxSdkResult(
      ownerUserId: ownerUserId,
      operationId: operationId,
      leaseOwnerId: leaseOwnerId,
      fencingToken: fencingToken,
      nowMs: nowMs,
      nextMainState: ImOutboxState.acknowledged,
      sdkLocalId: sdkLocalId,
      serverMsgId: serverMsgId,
      resultCode: resultCode,
    );
  }

  /// Adopts authoritative provider evidence for an outgoing operation.
  ///
  /// Unlike an SDK callback, a realtime/history message carrying the exact
  /// account-scoped correlation contract is allowed to resolve
  /// [ImOutboxState.outcomeUnknown]. This is deliberately strict: all stable
  /// identity fields must match both Outbox copies before either ledger is
  /// advanced.
  Future<bool> adoptOutboxProviderSucceeded({
    required String ownerUserId,
    required String operationId,
    required String clientCorrelationId,
    required String conversationId,
    required String payloadHash,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    String? sdkLocalId,
    String? serverMsgId,
  }) {
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null || copy == null || !_sameOutboxIdentity(main, copy)) {
        return false;
      }
      if (main.ownerUserId != ownerUserId ||
          main.clientCorrelationId != clientCorrelationId ||
          main.conversationId != conversationId ||
          main.payloadHash != payloadHash) {
        return false;
      }
      if (main.dispatchAttemptId != null &&
          copy.dispatchAttemptId != null &&
          main.dispatchAttemptId != copy.dispatchAttemptId) {
        return false;
      }
      if (main.state == ImOutboxState.completed &&
          copy.state == ImOutboxCopyState.reconciled) {
        return true;
      }
      if (main.state == ImOutboxState.acknowledged &&
          (copy.state == ImOutboxCopyState.resultRecorded ||
              copy.state == ImOutboxCopyState.reconciled)) {
        return true;
      }

      final ImOutboxCopyState nextCopyState;
      if (main.state == ImOutboxState.sending &&
          copy.state == ImOutboxCopyState.dispatchIntent) {
        nextCopyState = ImOutboxCopyState.resultRecorded;
      } else if (main.state == ImOutboxState.outcomeUnknown &&
          copy.state == ImOutboxCopyState.outcomeUnknown) {
        nextCopyState = ImOutboxCopyState.reconciled;
      } else {
        return false;
      }

      final providerCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId,
        operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId,
        conversationId: copy.conversationId,
        messageType: copy.messageType,
        recoveryRevision: copy.recoveryRevision + 1,
        state: nextCopyState,
        dispatchAttemptId: copy.dispatchAttemptId,
        dispatchIntentAtMs: copy.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash,
        checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId ?? sdkLocalId,
        serverMsgId: serverMsgId ?? copy.serverMsgId,
        resultCode: 'provider_observed',
        updatedAtMs: nowMs,
      );
      final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
        record: providerCopy,
        expectedState: copy.state,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
      if (!copyChanged) return false;

      final providerMain = main.copyWith(
        state: ImOutboxState.acknowledged,
        sdkMessageId: main.sdkMessageId ?? sdkLocalId,
        serverMsgId: serverMsgId,
        resultCode: 'provider_observed',
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      return transaction.updateOutboxIfCurrent(
        record: providerMain,
        expectedState: main.state,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
    });
  }

  Future<bool> recordOutboxSdkFailed({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    String? sdkLocalId,
    String? serverMsgId,
    String? resultCode,
  }) {
    return _recordOutboxSdkResult(
      ownerUserId: ownerUserId,
      operationId: operationId,
      leaseOwnerId: leaseOwnerId,
      fencingToken: fencingToken,
      nowMs: nowMs,
      nextMainState: ImOutboxState.failedTerminal,
      sdkLocalId: sdkLocalId,
      serverMsgId: serverMsgId,
      resultCode: resultCode,
    );
  }

  Future<bool> completeOutboxProjection({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) {
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null || copy == null || !_sameOutboxIdentity(main, copy)) {
        return false;
      }
      if (main.dispatchAttemptId != null &&
          copy.dispatchAttemptId != null &&
          main.dispatchAttemptId != copy.dispatchAttemptId) {
        return false;
      }
      if (main.state == ImOutboxState.completed &&
          copy.state == ImOutboxCopyState.reconciled) {
        return true;
      }
      if (main.state != ImOutboxState.acknowledged) {
        return false;
      }
      if (copy.state != ImOutboxCopyState.resultRecorded &&
          copy.state != ImOutboxCopyState.reconciled) {
        return false;
      }
      if (copy.state == ImOutboxCopyState.resultRecorded) {
        final reconciled = ImOutboxRecoveryRecord(
          ownerUserId: copy.ownerUserId,
          operationId: copy.operationId,
          clientCorrelationId: copy.clientCorrelationId,
          conversationId: copy.conversationId,
          messageType: copy.messageType,
          recoveryRevision: copy.recoveryRevision + 1,
          state: ImOutboxCopyState.reconciled,
          dispatchAttemptId: copy.dispatchAttemptId,
          dispatchIntentAtMs: copy.dispatchIntentAtMs,
          payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
          payloadHash: copy.payloadHash,
          checksum: copy.checksum,
          sdkLocalId: copy.sdkLocalId,
          serverMsgId: copy.serverMsgId,
          resultCode: copy.resultCode,
          updatedAtMs: nowMs,
        );
        final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
          record: reconciled,
          expectedState: ImOutboxCopyState.resultRecorded,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
          nowMs: nowMs,
        );
        if (!copyChanged) return false;
      }
      final completed = main.copyWith(
        state: ImOutboxState.completed,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      return transaction.updateOutboxIfCurrent(
        record: completed,
        expectedState: ImOutboxState.acknowledged,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
    });
  }

  Future<bool> _recordOutboxSdkResult({
    required String ownerUserId,
    required String operationId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    required ImOutboxState nextMainState,
    String? sdkLocalId,
    String? serverMsgId,
    String? resultCode,
  }) {
    if (nextMainState != ImOutboxState.acknowledged &&
        nextMainState != ImOutboxState.failedTerminal) {
      throw ArgumentError.value(nextMainState, 'nextMainState');
    }
    return _store.transaction<bool>((transaction) async {
      if (!await _hasCurrentLease(
          transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return false;
      }
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      if (main == null || copy == null || !_sameOutboxIdentity(main, copy)) {
        return false;
      }
      if (main.dispatchAttemptId != null &&
          copy.dispatchAttemptId != null &&
          main.dispatchAttemptId != copy.dispatchAttemptId) {
        return false;
      }
      if (main.state == ImOutboxState.completed &&
          copy.state == ImOutboxCopyState.reconciled) {
        return true;
      }
      if (main.state == nextMainState &&
          (copy.state == ImOutboxCopyState.resultRecorded ||
              copy.state == ImOutboxCopyState.reconciled)) {
        return true;
      }
      // IM-08: a late SDK success/failure callback must never silently
      // overwrite an already-resolved OutcomeUnknown. The single Writer
      // keeps OutcomeUnknown open until history, realtime or an explicit
      // recovery query adopts the operation; transitioning it from the
      // dispatch path would resurrect or fail UI bubbles that the user
      // is still waiting on.
      if (main.state != ImOutboxState.sending) {
        return false;
      }

      if (copy.state == ImOutboxCopyState.dispatchIntent ||
          copy.state == ImOutboxCopyState.outcomeUnknown) {
        final nextCopyState = copy.state == ImOutboxCopyState.dispatchIntent
            ? ImOutboxCopyState.resultRecorded
            : ImOutboxCopyState.reconciled;
        final resultCopy = ImOutboxRecoveryRecord(
          ownerUserId: copy.ownerUserId,
          operationId: copy.operationId,
          clientCorrelationId: copy.clientCorrelationId,
          conversationId: copy.conversationId,
          messageType: copy.messageType,
          recoveryRevision: copy.recoveryRevision + 1,
          state: nextCopyState,
          dispatchAttemptId: copy.dispatchAttemptId,
          dispatchIntentAtMs: copy.dispatchIntentAtMs,
          payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
          payloadHash: copy.payloadHash,
          checksum: copy.checksum,
          sdkLocalId: sdkLocalId ?? copy.sdkLocalId,
          serverMsgId: serverMsgId ?? copy.serverMsgId,
          resultCode: resultCode ?? copy.resultCode,
          updatedAtMs: nowMs,
        );
        final copyChanged = await transaction.updateOutboxRecoveryIfCurrent(
          record: resultCopy,
          expectedState: copy.state,
          leaseOwnerId: leaseOwnerId,
          fencingToken: fencingToken,
          nowMs: nowMs,
        );
        if (!copyChanged) return false;
      } else if (copy.state != ImOutboxCopyState.resultRecorded &&
          copy.state != ImOutboxCopyState.reconciled) {
        return false;
      }

      final resultMain = main.copyWith(
        state: nextMainState,
        sdkMessageId: sdkLocalId,
        serverMsgId: serverMsgId,
        resultCode: resultCode,
        updatedAtMs: nowMs,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
      );
      return transaction.updateOutboxIfCurrent(
        record: resultMain,
        expectedState: main.state,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        nowMs: nowMs,
      );
    });
  }

  Future<ImOutboxDispatchAssessment> recoverOutbox({
    required String ownerUserId,
    required String operationId,
  }) {
    return _store.transaction<ImOutboxDispatchAssessment>((transaction) async {
      final main = await transaction.findOutbox(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      final copy = await transaction.findOutboxRecovery(
        ownerUserId: ownerUserId,
        operationId: operationId,
      );
      return _assess(main: main, recoveryCopy: copy, leaseValid: true);
    });
  }
}

class ImOutboxDispatchAssessment {
  const ImOutboxDispatchAssessment({
    required this.decision,
    this.main,
    this.recoveryCopy,
  });

  final ImOutboxDispatchDecision decision;
  final ImOutboxRecord? main;
  final ImOutboxRecoveryRecord? recoveryCopy;

  bool get canDispatch => decision == ImOutboxDispatchDecision.ready;

  bool get requiresOutcomeQuery =>
      decision == ImOutboxDispatchDecision.outcomeUnknown;
}

class Im05IdentityConflictException implements Exception {
  const Im05IdentityConflictException(this.message);

  final String message;

  @override
  String toString() => 'IM-05 identity conflict: $message';
}

Future<bool> _hasCurrentLease(
  Im05Transaction transaction,
  String ownerUserId,
  String leaseOwnerId,
  int fencingToken,
  int nowMs,
) async {
  final lease = await transaction.findWriterLease(ownerUserId);
  return lease != null &&
      lease.leaseOwnerId == leaseOwnerId &&
      lease.fencingToken == fencingToken &&
      !lease.isExpiredAt(nowMs);
}

void _checkJournalIdentity(
  ImCommitJournalRecord current,
  ImCommitJournalRecord expected,
) {
  if (current.eventNamespace != expected.eventNamespace ||
      current.eventId != expected.eventId ||
      current.scope != expected.scope ||
      current.commitRevision != expected.commitRevision) {
    throw const Im05IdentityConflictException('journal identity conflict');
  }
}

void _checkCheckpointIdentity(
  ImProjectionCheckpointRecord checkpoint,
  ImCommitJournalRecord journal,
) {
  if (checkpoint.ownerUserId != journal.ownerUserId ||
      checkpoint.scope != journal.scope ||
      checkpoint.commitRevision != journal.commitRevision ||
      checkpoint.lastJournalId != journal.journalId) {
    throw const Im05IdentityConflictException('checkpoint does not match');
  }
}

void _checkOutboxRecordIdentity(
  ImOutboxRecord current,
  ImOutboxRecord expected,
) {
  if (current.ownerUserId != expected.ownerUserId ||
      current.operationId != expected.operationId ||
      current.conversationId != expected.conversationId ||
      current.clientCorrelationId != expected.clientCorrelationId ||
      current.messageType != expected.messageType ||
      current.payloadReference != expected.payloadReference ||
      current.payloadHash != expected.payloadHash) {
    throw const Im05IdentityConflictException('outbox identity conflict');
  }
}

void _checkRecoveryIdentity(
  ImOutboxRecoveryRecord current,
  ImOutboxRecoveryRecord expected,
) {
  if (!_sameRecoveryIdentity(current, expected)) {
    throw const Im05IdentityConflictException(
      'outbox recovery identity conflict',
    );
  }
}

bool _sameOutboxIdentity(
  ImOutboxRecord main,
  ImOutboxRecoveryRecord copy,
) {
  return main.ownerUserId == copy.ownerUserId &&
      main.operationId == copy.operationId &&
      main.conversationId == copy.conversationId &&
      main.clientCorrelationId == copy.clientCorrelationId &&
      main.messageType == copy.messageType &&
      main.payloadHash == copy.payloadHash &&
      (main.contentChecksum == null ||
          main.contentChecksum!.isEmpty ||
          copy.checksum.isEmpty ||
          main.contentChecksum == copy.checksum);
}

bool _sameRecoveryIdentity(
  ImOutboxRecoveryRecord current,
  ImOutboxRecoveryRecord expected,
) {
  return current.ownerUserId == expected.ownerUserId &&
      current.operationId == expected.operationId &&
      current.clientCorrelationId == expected.clientCorrelationId &&
      current.conversationId == expected.conversationId &&
      current.messageType == expected.messageType &&
      current.payloadHash == expected.payloadHash &&
      current.checksum == expected.checksum &&
      current.payloadReferenceOrCiphertext ==
          expected.payloadReferenceOrCiphertext;
}

bool _sameCheckpointValue(
  ImProjectionCheckpointRecord left,
  ImProjectionCheckpointRecord right,
) {
  return left.ownerUserId == right.ownerUserId &&
      left.scope == right.scope &&
      left.commitRevision == right.commitRevision &&
      left.lastJournalId == right.lastJournalId &&
      left.coverageRevision == right.coverageRevision &&
      left.watermarkRevision == right.watermarkRevision &&
      left.barrierRevision == right.barrierRevision &&
      left.projectionVersion == right.projectionVersion;
}

ImOutboxDispatchAssessment _assess({
  required ImOutboxRecord? main,
  required ImOutboxRecoveryRecord? recoveryCopy,
  required bool leaseValid,
}) {
  if (!leaseValid) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.fencingRejected,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main == null) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.mainMissing,
      recoveryCopy: recoveryCopy,
    );
  }
  if (recoveryCopy == null) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.recoveryCopyMissing,
      main: main,
    );
  }
  if (!_sameOutboxIdentity(main, recoveryCopy)) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.identityConflict,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main.dispatchAttemptId != null &&
      recoveryCopy.dispatchAttemptId != null &&
      main.dispatchAttemptId != recoveryCopy.dispatchAttemptId) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.recoveryConflict,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main.recoveryConflict) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.recoveryConflict,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main.recoveryLag) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.recoveryLag,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main.state == ImOutboxState.dispatchIntent ||
      main.state == ImOutboxState.sending ||
      main.state == ImOutboxState.outcomeUnknown ||
      recoveryCopy.state == ImOutboxCopyState.dispatchIntent ||
      recoveryCopy.state == ImOutboxCopyState.outcomeUnknown) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.outcomeUnknown,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (main.state != ImOutboxState.prepared) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.mainNotPrepared,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  if (recoveryCopy.state != ImOutboxCopyState.copyPrepared) {
    return ImOutboxDispatchAssessment(
      decision: ImOutboxDispatchDecision.recoveryCopyNotPrepared,
      main: main,
      recoveryCopy: recoveryCopy,
    );
  }
  return ImOutboxDispatchAssessment(
    decision: ImOutboxDispatchDecision.ready,
    main: main,
    recoveryCopy: recoveryCopy,
  );
}

~~~

74. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im05_contracts.dart:1>)，原文件 lib/src/services/im/im05_contracts.dart，1–734 行。

~~~dart
// Durable state contracts for the first IM-05 infrastructure slice.
//
// The records in this file are deliberately storage-shaped. They can be
// encoded by SQLite, IndexedDB, or the deterministic in-memory test store,
// while the protocol decisions remain in [Im05Persistence].

import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';

enum ImCommitJournalState {
  prepared,
  metadataCommitted,
  projectionPublished,
  completed,
}

enum ImEffectLedgerState {
  pending,
  running,
  completed,
  failed,
}

enum ImOutboxState {
  created,
  preparing,
  prepared,
  dispatchIntent,
  sending,
  outcomeUnknown,
  retryable,
  acknowledged,
  completed,
  failedTerminal,
  manualRequired,
  pausedByLogout,
  abandonedByUser,
}

enum ImOutboxCopyState {
  copyPrepared,
  dispatchIntent,
  resultRecorded,
  outcomeUnknown,
  manualRequired,
  reconciled,
  gcEligible,
}

enum ImOutboxDispatchDecision {
  ready,
  mainMissing,
  mainNotPrepared,
  recoveryCopyMissing,
  recoveryCopyNotPrepared,
  identityConflict,
  recoveryConflict,
  recoveryLag,
  outcomeUnknown,
  fencingRejected,
}

class ImCommitJournalRecord {
  const ImCommitJournalRecord({
    required this.ownerUserId,
    required this.journalId,
    required this.eventNamespace,
    required this.eventId,
    required this.scope,
    required this.commitRevision,
    required this.state,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.metadataRevision,
    this.projectionRevision,
    this.sideEffectRevision,
    this.leaseOwnerId = '',
    this.fencingToken = 0,
  });

  final String ownerUserId;
  final String journalId;
  final String eventNamespace;
  final String eventId;
  final String scope;
  final int commitRevision;
  final ImCommitJournalState state;
  final int? metadataRevision;
  final int? projectionRevision;
  final int? sideEffectRevision;
  final int createdAtMs;
  final int updatedAtMs;
  final String leaseOwnerId;
  final int fencingToken;

  ImCommitJournalRecord copyWith({
    ImCommitJournalState? state,
    int? metadataRevision,
    int? projectionRevision,
    int? sideEffectRevision,
    int? updatedAtMs,
    String? leaseOwnerId,
    int? fencingToken,
  }) {
    return ImCommitJournalRecord(
      ownerUserId: ownerUserId,
      journalId: journalId,
      eventNamespace: eventNamespace,
      eventId: eventId,
      scope: scope,
      commitRevision: commitRevision,
      state: state ?? this.state,
      metadataRevision: metadataRevision ?? this.metadataRevision,
      projectionRevision: projectionRevision ?? this.projectionRevision,
      sideEffectRevision: sideEffectRevision ?? this.sideEffectRevision,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      leaseOwnerId: leaseOwnerId ?? this.leaseOwnerId,
      fencingToken: fencingToken ?? this.fencingToken,
    );
  }
}

class ImProjectionCheckpointRecord {
  const ImProjectionCheckpointRecord({
    required this.ownerUserId,
    required this.scope,
    required this.commitRevision,
    required this.lastJournalId,
    required this.coverageRevision,
    required this.watermarkRevision,
    required this.barrierRevision,
    required this.projectionVersion,
    required this.updatedAtMs,
    this.leaseOwnerId = '',
    this.fencingToken = 0,
  });

  final String ownerUserId;
  final String scope;
  final int commitRevision;
  final String lastJournalId;
  final int coverageRevision;
  final int watermarkRevision;
  final int barrierRevision;
  final int projectionVersion;
  final int updatedAtMs;
  final String leaseOwnerId;
  final int fencingToken;
}

class ImEffectLedgerRecord {
  const ImEffectLedgerRecord({
    required this.ownerUserId,
    required this.effectId,
    required this.journalId,
    required this.effectKind,
    required this.state,
    required this.attemptCount,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.lastError,
    this.leaseOwnerId = '',
    this.fencingToken = 0,
  });

  final String ownerUserId;
  final String effectId;
  final String journalId;
  final String effectKind;
  final ImEffectLedgerState state;
  final int attemptCount;
  final String? lastError;
  final int createdAtMs;
  final int updatedAtMs;
  final String leaseOwnerId;
  final int fencingToken;
}

class ImOutboxRecord {
  const ImOutboxRecord({
    required this.operationId,
    required this.ownerUserId,
    required this.conversationId,
    required this.clientCorrelationId,
    required this.messageType,
    required this.payloadReference,
    required this.state,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.mediaLocalRef,
    this.encryptionVersion,
    this.keyId,
    this.cipherAlgorithm,
    this.nonce,
    this.contentChecksum,
    this.payloadHash = '',
    this.sdkMessageId,
    this.serverMsgId,
    this.dispatchAttemptId,
    this.dispatchIntentAtMs,
    this.resultCode,
    this.retryCount = 0,
    this.nextRetryAtMs,
    this.leaseOwnerId = '',
    this.fencingToken = 0,
    this.recoveryLag = false,
    this.recoveryConflict = false,
  });

  final String operationId;
  final String ownerUserId;
  final String conversationId;
  final String clientCorrelationId;
  final int messageType;
  final String payloadReference;
  final String? mediaLocalRef;
  final int? encryptionVersion;
  final String? keyId;
  final String? cipherAlgorithm;
  final String? nonce;
  final String? contentChecksum;
  final String payloadHash;
  final ImOutboxState state;
  final String? sdkMessageId;
  final String? serverMsgId;
  final String? dispatchAttemptId;
  final int? dispatchIntentAtMs;
  final String? resultCode;
  final int retryCount;
  final int? nextRetryAtMs;
  final int createdAtMs;
  final int updatedAtMs;
  final String leaseOwnerId;
  final int fencingToken;
  final bool recoveryLag;
  final bool recoveryConflict;

  ImOutboxRecord copyWith({
    ImOutboxState? state,
    String? sdkMessageId,
    String? serverMsgId,
    String? dispatchAttemptId,
    int? dispatchIntentAtMs,
    String? resultCode,
    int? retryCount,
    int? nextRetryAtMs,
    int? updatedAtMs,
    String? leaseOwnerId,
    int? fencingToken,
    bool? recoveryLag,
    bool? recoveryConflict,
  }) {
    return ImOutboxRecord(
      operationId: operationId,
      ownerUserId: ownerUserId,
      conversationId: conversationId,
      clientCorrelationId: clientCorrelationId,
      messageType: messageType,
      payloadReference: payloadReference,
      state: state ?? this.state,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      mediaLocalRef: mediaLocalRef,
      encryptionVersion: encryptionVersion,
      keyId: keyId,
      cipherAlgorithm: cipherAlgorithm,
      nonce: nonce,
      contentChecksum: contentChecksum,
      payloadHash: payloadHash,
      sdkMessageId: sdkMessageId ?? this.sdkMessageId,
      serverMsgId: serverMsgId ?? this.serverMsgId,
      dispatchAttemptId: dispatchAttemptId ?? this.dispatchAttemptId,
      dispatchIntentAtMs: dispatchIntentAtMs ?? this.dispatchIntentAtMs,
      resultCode: resultCode ?? this.resultCode,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAtMs: nextRetryAtMs ?? this.nextRetryAtMs,
      leaseOwnerId: leaseOwnerId ?? this.leaseOwnerId,
      fencingToken: fencingToken ?? this.fencingToken,
      recoveryLag: recoveryLag ?? this.recoveryLag,
      recoveryConflict: recoveryConflict ?? this.recoveryConflict,
    );
  }
}

class ImOutboxRecoveryRecord {
  const ImOutboxRecoveryRecord({
    required this.ownerUserId,
    required this.operationId,
    required this.clientCorrelationId,
    required this.conversationId,
    required this.messageType,
    required this.recoveryRevision,
    required this.state,
    required this.payloadReferenceOrCiphertext,
    required this.payloadHash,
    required this.checksum,
    required this.updatedAtMs,
    this.dispatchAttemptId,
    this.dispatchIntentAtMs,
    this.sdkLocalId,
    this.serverMsgId,
    this.resultCode,
  });

  final String ownerUserId;
  final String operationId;
  final String clientCorrelationId;
  final String conversationId;
  final int messageType;
  final int recoveryRevision;
  final ImOutboxCopyState state;
  final int? dispatchIntentAtMs;
  final String? dispatchAttemptId;
  final String payloadReferenceOrCiphertext;
  final String payloadHash;
  final String checksum;
  final String? sdkLocalId;
  final String? serverMsgId;
  final String? resultCode;
  final int updatedAtMs;
}

abstract interface class Im05Transaction {
  Future<ImWriterLeaseRecord?> findWriterLease(String ownerUserId);

  Future<ImCommitJournalRecord?> findCommitJournal({
    required String ownerUserId,
    required String journalId,
  });

  Future<bool> insertCommitJournalIfAbsent(ImCommitJournalRecord record);

  Future<bool> updateCommitJournalIfCurrent({
    required ImCommitJournalRecord record,
    required ImCommitJournalState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  });

  Future<ImProjectionCheckpointRecord?> findProjectionCheckpoint({
    required String ownerUserId,
    required String scope,
  });

  Future<bool> saveProjectionCheckpointIfCurrent({
    required ImProjectionCheckpointRecord record,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  });

  Future<ImEffectLedgerRecord?> findEffect({
    required String ownerUserId,
    required String effectId,
  });

  Future<bool> insertEffectIfAbsent(ImEffectLedgerRecord record);

  Future<bool> updateEffectIfCurrent({
    required ImEffectLedgerRecord record,
    required ImEffectLedgerState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  });

  Future<ImOutboxRecord?> findOutbox({
    required String ownerUserId,
    required String operationId,
  });

  Future<ImOutboxRecord?> findOutboxBySdkLocalId({
    required String ownerUserId,
    required String conversationId,
    required String sdkLocalId,
  });

  Future<List<ImOutboxRecord>> listOutboxesForRecovery({
    required String ownerUserId,
    required List<ImOutboxState> states,
    required int limit,
  });

  Future<bool> insertOutboxIfAbsent(ImOutboxRecord record);

  Future<bool> updateOutboxIfCurrent({
    required ImOutboxRecord record,
    required ImOutboxState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  });

  Future<ImOutboxRecoveryRecord?> findOutboxRecovery({
    required String ownerUserId,
    required String operationId,
  });

  Future<bool> insertOutboxRecoveryIfAbsent(ImOutboxRecoveryRecord record);

  Future<bool> updateOutboxRecoveryIfCurrent({
    required ImOutboxRecoveryRecord record,
    required ImOutboxCopyState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  });
}

bool isValidImCommitJournalTransition(
  ImCommitJournalState expected,
  ImCommitJournalState next,
) {
  return (expected == ImCommitJournalState.prepared &&
          next == ImCommitJournalState.metadataCommitted) ||
      (expected == ImCommitJournalState.metadataCommitted &&
          next == ImCommitJournalState.projectionPublished) ||
      (expected == ImCommitJournalState.projectionPublished &&
          next == ImCommitJournalState.completed);
}

bool isValidImOutboxRecoveryTransition(
  ImOutboxCopyState expected,
  ImOutboxCopyState next,
) {
  return (expected == ImOutboxCopyState.copyPrepared &&
          (next == ImOutboxCopyState.dispatchIntent ||
              next == ImOutboxCopyState.manualRequired)) ||
      (expected == ImOutboxCopyState.dispatchIntent &&
          (next == ImOutboxCopyState.resultRecorded ||
              next == ImOutboxCopyState.outcomeUnknown)) ||
      (expected == ImOutboxCopyState.resultRecorded &&
          next == ImOutboxCopyState.reconciled) ||
      (expected == ImOutboxCopyState.outcomeUnknown &&
          next == ImOutboxCopyState.reconciled) ||
      (expected == ImOutboxCopyState.reconciled &&
          next == ImOutboxCopyState.gcEligible);
}

bool isValidImEffectTransition(
  ImEffectLedgerState expected,
  ImEffectLedgerState next,
) {
  return (expected == ImEffectLedgerState.pending &&
          next == ImEffectLedgerState.running) ||
      (expected == ImEffectLedgerState.running &&
          (next == ImEffectLedgerState.completed ||
              next == ImEffectLedgerState.failed));
}

bool isValidImOutboxTransition(ImOutboxState expected, ImOutboxState next) {
  switch (expected) {
    case ImOutboxState.created:
      return next == ImOutboxState.preparing;
    case ImOutboxState.preparing:
      return next == ImOutboxState.prepared;
    case ImOutboxState.prepared:
      return next == ImOutboxState.dispatchIntent ||
          next == ImOutboxState.manualRequired ||
          next == ImOutboxState.pausedByLogout;
    case ImOutboxState.dispatchIntent:
      return next == ImOutboxState.sending ||
          next == ImOutboxState.outcomeUnknown;
    case ImOutboxState.sending:
      return next == ImOutboxState.acknowledged ||
          next == ImOutboxState.failedTerminal ||
          next == ImOutboxState.retryable ||
          next == ImOutboxState.outcomeUnknown;
    case ImOutboxState.outcomeUnknown:
      return next == ImOutboxState.acknowledged ||
          next == ImOutboxState.failedTerminal ||
          next == ImOutboxState.retryable ||
          next == ImOutboxState.abandonedByUser;
    case ImOutboxState.retryable:
      return next == ImOutboxState.prepared;
    case ImOutboxState.acknowledged:
      return next == ImOutboxState.completed;
    case ImOutboxState.pausedByLogout:
      return next == ImOutboxState.prepared ||
          next == ImOutboxState.abandonedByUser;
    case ImOutboxState.completed:
    case ImOutboxState.failedTerminal:
    case ImOutboxState.manualRequired:
    case ImOutboxState.abandonedByUser:
      return false;
  }
}

Map<String, Object?> imCommitJournalToStorageMap(
        ImCommitJournalRecord record) =>
    <String, Object?>{
      'owner_user_id': record.ownerUserId,
      'journal_id': record.journalId,
      'event_namespace': record.eventNamespace,
      'event_id': record.eventId,
      'scope': record.scope,
      'commit_revision': record.commitRevision,
      'state': record.state.name,
      'metadata_revision': record.metadataRevision,
      'projection_revision': record.projectionRevision,
      'side_effect_revision': record.sideEffectRevision,
      'created_at': record.createdAtMs,
      'updated_at': record.updatedAtMs,
      'lease_owner_id': record.leaseOwnerId,
      'fencing_token': record.fencingToken,
    };

ImCommitJournalRecord imCommitJournalFromStorageMap(Map<String, Object?> row) =>
    ImCommitJournalRecord(
      ownerUserId: _string(row['owner_user_id']),
      journalId: _string(row['journal_id']),
      eventNamespace: _string(row['event_namespace']),
      eventId: _string(row['event_id']),
      scope: _string(row['scope']),
      commitRevision: _int(row['commit_revision']),
      state: _enumByName(
        ImCommitJournalState.values,
        row['state']?.toString(),
        ImCommitJournalState.prepared,
      ),
      metadataRevision: _optionalInt(row['metadata_revision']),
      projectionRevision: _optionalInt(row['projection_revision']),
      sideEffectRevision: _optionalInt(row['side_effect_revision']),
      createdAtMs: _int(row['created_at']),
      updatedAtMs: _int(row['updated_at']),
      leaseOwnerId: _string(row['lease_owner_id']),
      fencingToken: _int(row['fencing_token']),
    );

Map<String, Object?> imProjectionCheckpointToStorageMap(
  ImProjectionCheckpointRecord record,
) =>
    <String, Object?>{
      'owner_user_id': record.ownerUserId,
      'scope': record.scope,
      'commit_revision': record.commitRevision,
      'last_journal_id': record.lastJournalId,
      'coverage_revision': record.coverageRevision,
      'watermark_revision': record.watermarkRevision,
      'barrier_revision': record.barrierRevision,
      'projection_version': record.projectionVersion,
      'updated_at': record.updatedAtMs,
      'lease_owner_id': record.leaseOwnerId,
      'fencing_token': record.fencingToken,
    };

ImProjectionCheckpointRecord imProjectionCheckpointFromStorageMap(
  Map<String, Object?> row,
) =>
    ImProjectionCheckpointRecord(
      ownerUserId: _string(row['owner_user_id']),
      scope: _string(row['scope']),
      commitRevision: _int(row['commit_revision']),
      lastJournalId: _string(row['last_journal_id']),
      coverageRevision: _int(row['coverage_revision']),
      watermarkRevision: _int(row['watermark_revision']),
      barrierRevision: _int(row['barrier_revision']),
      projectionVersion: _int(row['projection_version']),
      updatedAtMs: _int(row['updated_at']),
      leaseOwnerId: _string(row['lease_owner_id']),
      fencingToken: _int(row['fencing_token']),
    );

Map<String, Object?> imEffectLedgerToStorageMap(ImEffectLedgerRecord record) =>
    <String, Object?>{
      'owner_user_id': record.ownerUserId,
      'effect_id': record.effectId,
      'journal_id': record.journalId,
      'effect_kind': record.effectKind,
      'state': record.state.name,
      'attempt_count': record.attemptCount,
      'last_error': record.lastError,
      'created_at': record.createdAtMs,
      'updated_at': record.updatedAtMs,
      'lease_owner_id': record.leaseOwnerId,
      'fencing_token': record.fencingToken,
    };

ImEffectLedgerRecord imEffectLedgerFromStorageMap(Map<String, Object?> row) =>
    ImEffectLedgerRecord(
      ownerUserId: _string(row['owner_user_id']),
      effectId: _string(row['effect_id']),
      journalId: _string(row['journal_id']),
      effectKind: _string(row['effect_kind']),
      state: _enumByName(
        ImEffectLedgerState.values,
        row['state']?.toString(),
        ImEffectLedgerState.pending,
      ),
      attemptCount: _int(row['attempt_count']),
      lastError: _optionalString(row['last_error']),
      createdAtMs: _int(row['created_at']),
      updatedAtMs: _int(row['updated_at']),
      leaseOwnerId: _string(row['lease_owner_id']),
      fencingToken: _int(row['fencing_token']),
    );

Map<String, Object?> imOutboxToStorageMap(ImOutboxRecord record) =>
    <String, Object?>{
      'operation_id': record.operationId,
      'owner_user_id': record.ownerUserId,
      'conversation_id': record.conversationId,
      'client_correlation_id': record.clientCorrelationId,
      'message_type': record.messageType,
      'payload_reference': record.payloadReference,
      'media_local_ref': record.mediaLocalRef,
      'encryption_version': record.encryptionVersion,
      'key_id': record.keyId,
      'cipher_algorithm': record.cipherAlgorithm,
      'nonce': record.nonce,
      'content_checksum': record.contentChecksum,
      'payload_hash': record.payloadHash,
      'state': record.state.name,
      'sdk_message_id': record.sdkMessageId,
      'server_msg_id': record.serverMsgId,
      'dispatch_attempt_id': record.dispatchAttemptId,
      'dispatch_intent_at': record.dispatchIntentAtMs,
      'result_code': record.resultCode,
      'retry_count': record.retryCount,
      'next_retry_at': record.nextRetryAtMs,
      'created_at': record.createdAtMs,
      'updated_at': record.updatedAtMs,
      'lease_owner_id': record.leaseOwnerId,
      'fencing_token': record.fencingToken,
      'recovery_lag': record.recoveryLag ? 1 : 0,
      'recovery_conflict': record.recoveryConflict ? 1 : 0,
    };

ImOutboxRecord imOutboxFromStorageMap(Map<String, Object?> row) =>
    ImOutboxRecord(
      operationId: _string(row['operation_id']),
      ownerUserId: _string(row['owner_user_id']),
      conversationId: _string(row['conversation_id']),
      clientCorrelationId: _string(row['client_correlation_id']),
      messageType: _int(row['message_type']),
      payloadReference: _string(row['payload_reference']),
      state: _enumByName(
        ImOutboxState.values,
        row['state']?.toString(),
        ImOutboxState.created,
      ),
      createdAtMs: _int(row['created_at']),
      updatedAtMs: _int(row['updated_at']),
      mediaLocalRef: _optionalString(row['media_local_ref']),
      encryptionVersion: _optionalInt(row['encryption_version']),
      keyId: _optionalString(row['key_id']),
      cipherAlgorithm: _optionalString(row['cipher_algorithm']),
      nonce: _optionalString(row['nonce']),
      contentChecksum: _optionalString(row['content_checksum']),
      payloadHash: _string(row['payload_hash']),
      sdkMessageId: _optionalString(row['sdk_message_id']),
      serverMsgId: _optionalString(row['server_msg_id']),
      dispatchAttemptId: _optionalString(row['dispatch_attempt_id']),
      dispatchIntentAtMs: _optionalInt(row['dispatch_intent_at']),
      resultCode: _optionalString(row['result_code']),
      retryCount: _int(row['retry_count']),
      nextRetryAtMs: _optionalInt(row['next_retry_at']),
      leaseOwnerId: _string(row['lease_owner_id']),
      fencingToken: _int(row['fencing_token']),
      recoveryLag: _int(row['recovery_lag']) != 0,
      recoveryConflict: _int(row['recovery_conflict']) != 0,
    );

Map<String, Object?> imOutboxRecoveryToStorageMap(
  ImOutboxRecoveryRecord record,
) =>
    <String, Object?>{
      'owner_user_id': record.ownerUserId,
      'operation_id': record.operationId,
      'client_correlation_id': record.clientCorrelationId,
      'conversation_id': record.conversationId,
      'message_type': record.messageType,
      'recovery_revision': record.recoveryRevision,
      'state': record.state.name,
      'dispatch_attempt_id': record.dispatchAttemptId,
      'dispatch_intent_at': record.dispatchIntentAtMs,
      'payload_reference_or_ciphertext': record.payloadReferenceOrCiphertext,
      'payload_hash': record.payloadHash,
      'checksum': record.checksum,
      'sdk_local_id': record.sdkLocalId,
      'server_msg_id': record.serverMsgId,
      'result_code': record.resultCode,
      'updated_at': record.updatedAtMs,
    };

ImOutboxRecoveryRecord imOutboxRecoveryFromStorageMap(
  Map<String, Object?> row,
) =>
    ImOutboxRecoveryRecord(
      ownerUserId: _string(row['owner_user_id']),
      operationId: _string(row['operation_id']),
      clientCorrelationId: _string(row['client_correlation_id']),
      conversationId: _string(row['conversation_id']),
      messageType: _int(row['message_type']),
      recoveryRevision: _int(row['recovery_revision']),
      state: _enumByName(
        ImOutboxCopyState.values,
        row['state']?.toString(),
        ImOutboxCopyState.copyPrepared,
      ),
      dispatchAttemptId: _optionalString(row['dispatch_attempt_id']),
      dispatchIntentAtMs: _optionalInt(row['dispatch_intent_at']),
      payloadReferenceOrCiphertext:
          _string(row['payload_reference_or_ciphertext']),
      payloadHash: _string(row['payload_hash']),
      checksum: _string(row['checksum']),
      sdkLocalId: _optionalString(row['sdk_local_id']),
      serverMsgId: _optionalString(row['server_msg_id']),
      resultCode: _optionalString(row['result_code']),
      updatedAtMs: _int(row['updated_at']),
    );

String _string(Object? value) => value?.toString() ?? '';

String? _optionalString(Object? value) {
  final valueText = value?.toString().trim() ?? '';
  return valueText.isEmpty ? null : valueText;
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

int? _optionalInt(Object? value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

T _enumByName<T extends Enum>(Iterable<T> values, String? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

~~~

75. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/contracts/outgoing_identity_contract.dart:1>)，原文件 lib/src/services/im/contracts/outgoing_identity_contract.dart，1–233 行。

~~~dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'account_scoped_conversation_key.dart';

const String kOutgoingIdentitySchema = '99chat.outgoing.v1';

/// Creates an Outbox key that is independent of Tencent's process-local
/// `created_temp_id-*` message IDs. The value is persisted with both Outbox
/// copies and reused for recovery, so a restart cannot collide with a prior
/// send in the same conversation.
String newOutgoingOperationId() => 'send_${const Uuid().v4()}';

/// Correlation IDs are also per-send identities; the SDK local ID is only a
/// provider handle and is not stable across process restarts.
String newOutgoingClientCorrelationId() => 'client_${const Uuid().v4()}';

enum OutgoingMessageKind { text, image, video, audio, custom }

/// Cross-process and cross-platform identity for one outbound operation.
///
/// Only [toCloudCustomData] belongs in Tencent's cloudCustomData. Local file
/// paths, credentials, message bodies and page objects are deliberately absent.
class OutgoingIdentityContract {
  factory OutgoingIdentityContract({
    required AccountScopedConversationKey scope,
    required String operationId,
    required String clientCorrelationId,
    required OutgoingMessageKind messageKind,
    required String payloadFingerprint,
    required int createdAtMs,
    String? sdkLocalId,
    String? serverMsgId,
  }) {
    final operation = _requiredId(operationId, 'operationId');
    final correlation = _requiredId(
      clientCorrelationId,
      'clientCorrelationId',
    );
    final fingerprint = _requiredId(payloadFingerprint, 'payloadFingerprint');
    if (createdAtMs < 0) {
      throw ArgumentError.value(
          createdAtMs, 'createdAtMs', 'must be non-negative');
    }
    return OutgoingIdentityContract._(
      scope: scope,
      operationId: operation,
      clientCorrelationId: correlation,
      messageKind: messageKind,
      payloadFingerprint: fingerprint,
      createdAtMs: createdAtMs,
      sdkLocalId: _optionalId(sdkLocalId),
      serverMsgId: _optionalId(serverMsgId),
    );
  }

  const OutgoingIdentityContract._({
    required this.scope,
    required this.operationId,
    required this.clientCorrelationId,
    required this.messageKind,
    required this.payloadFingerprint,
    required this.createdAtMs,
    required this.sdkLocalId,
    required this.serverMsgId,
  });

  final AccountScopedConversationKey scope;
  final String operationId;
  final String clientCorrelationId;
  final OutgoingMessageKind messageKind;
  final String payloadFingerprint;
  final int createdAtMs;
  final String? sdkLocalId;
  final String? serverMsgId;

  Map<String, Object?> toCloudCustomData({String? businessCloudCustomData}) {
    final data = <String, Object?>{};
    final business = businessCloudCustomData?.trim() ?? '';
    if (business.isNotEmpty) {
      try {
        final decoded = jsonDecode(business);
        if (decoded is Map) {
          // UIKit consumes messageReply/messageFeature at the JSON root. Do
          // not hide application metadata inside a string-valued `business`
          // field or every quoted/replied message loses its protocol shape.
          for (final entry in decoded.entries) {
            final key = entry.key?.toString() ?? '';
            if (key.isNotEmpty) data[key] = entry.value;
          }
        } else {
          data['business'] = business;
        }
      } catch (_) {
        // Preserve non-JSON legacy metadata without making a normal send fail.
        data['business'] = business;
      }
    }

    // Correlation fields are reserved and authoritative even if a business
    // payload accidentally contains fields with the same names.
    data.addAll(<String, Object?>{
      'schema': kOutgoingIdentitySchema,
      'operationId': operationId,
      'clientCorrelationId': clientCorrelationId,
      'messageKind': messageKind.name,
      'payloadFingerprint': payloadFingerprint,
      'createdAtMs': createdAtMs,
    });
    return data;
  }

  String encodeCloudCustomData({String? businessCloudCustomData}) => jsonEncode(
        toCloudCustomData(businessCloudCustomData: businessCloudCustomData),
      );

  static OutgoingIdentityContract? fromCloudCustomData(
    String? raw, {
    required AccountScopedConversationKey scope,
  }) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schema'] != kOutgoingIdentitySchema) return null;
      final kindName = map['messageKind'] ?? map['messageType'];
      final kind = OutgoingMessageKind.values.firstWhere(
        (value) => value.name == kindName?.toString(),
        orElse: () => throw const FormatException('unknown message kind'),
      );
      final createdAtMs = _asInt(map['createdAtMs']);
      if (createdAtMs == null) return null;
      return OutgoingIdentityContract(
        scope: scope,
        operationId: map['operationId']?.toString() ?? '',
        clientCorrelationId: map['clientCorrelationId']?.toString() ?? '',
        messageKind: kind,
        payloadFingerprint: map['payloadFingerprint']?.toString() ?? '',
        createdAtMs: createdAtMs,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  OutgoingIdentityContract withFormalIdentity({
    String? sdkLocalId,
    String? serverMsgId,
  }) {
    return OutgoingIdentityContract(
      scope: scope,
      operationId: operationId,
      clientCorrelationId: clientCorrelationId,
      messageKind: messageKind,
      payloadFingerprint: payloadFingerprint,
      createdAtMs: createdAtMs,
      sdkLocalId: sdkLocalId ?? this.sdkLocalId,
      serverMsgId: serverMsgId ?? this.serverMsgId,
    );
  }

  bool matchesCandidate({
    required AccountScopedConversationKey candidateScope,
    required OutgoingMessageKind candidateKind,
    required String candidatePayloadFingerprint,
    String? candidateCorrelationId,
  }) {
    return scope == candidateScope &&
        messageKind == candidateKind &&
        payloadFingerprint == candidatePayloadFingerprint &&
        (candidateCorrelationId == null ||
            candidateCorrelationId == clientCorrelationId);
  }

  Map<String, Object?> toMetadataJson() => <String, Object?>{
        ...toCloudCustomData(),
        'ownerUserId': scope.ownerUserId,
        'conversationKey': scope.canonicalConversationId,
        'sdkLocalId': sdkLocalId,
        'serverMsgId': serverMsgId,
      };
}

String _requiredId(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String? _optionalId(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

/// Legacy deterministic key retained only for rows written before UUID send
/// identities were introduced. New sends use [newOutgoingOperationId].
String hashOutgoingOperationId({
  required AccountScopedConversationKey scope,
  required String sdkLocalId,
}) {
  final localId = sdkLocalId.trim();
  if (localId.isEmpty) {
    throw ArgumentError.value(sdkLocalId, 'sdkLocalId', 'must not be empty');
  }
  final digest = sha256
      .convert(utf8.encode('send|${scope.storageKey}|$localId'))
      .toString()
      .substring(0, 32);
  return 'send_$digest';
}

String hashOutgoingClientCorrelationId(String sdkLocalId) {
  final localId = sdkLocalId.trim();
  if (localId.isEmpty) {
    throw ArgumentError.value(sdkLocalId, 'sdkLocalId', 'must not be empty');
  }
  final digest = sha256.convert(utf8.encode('client|$localId')).toString();
  return 'client_${digest.substring(0, 24)}';
}

~~~

76. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/tencent_message_adapter.dart:1>)，原文件 lib/src/services/im/tencent_message_adapter.dart，1–524 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

typedef ImSyncIdentitySink = void Function(
  EventEnvelope<OutgoingIdentityContract> event,
);

/// Minimal SDK port used by [TencentMessageAdapter].
///
/// Keeping this interface small lets contract tests use a fake and prevents
/// the domain layer from depending on TUIKit's service locator or model.
abstract interface class ImTencentMessagePort {
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    required String id,
    required String receiver,
    required String groupID,
    required MessagePriorityEnum priority,
    required bool onlineUserOnly,
    required bool isExcludedFromUnreadCount,
    required bool needReadReceipt,
    required OfflinePushInfo? offlinePushInfo,
    required String cloudCustomData,
    required String? localCustomData,
    required bool isExcludedFromContentModeration,
    required void Function(String syncMsgID) onSyncMsgID,
  });

  Future<ImSdkHistoryResponse?> getHistoryMessageListWithComplete({
    required HistoryMsgGetTypeEnum getType,
    required String? userID,
    required String? groupID,
    required int lastMsgSeq,
    required int count,
    required String? lastMsgID,
    V2TimMessage? lastMsg,
    required List<int>? messageTypeList,
    required List<int>? messageSeqList,
    required int? timeBegin,
    required int? timePeriod,
  });
}

/// Transitional port for the existing TUIKit MessageService.
///
/// It deliberately does not expose TUIKit models or invoke a UI writer. The
/// old `onSyncMsgID` side effect remains in MessageServiceImpl until the next
/// migration step replaces that implementation with this port.
class TUIKitMessageServicePort implements ImTencentMessagePort {
  const TUIKitMessageServicePort(this.service);

  final MessageService service;

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    required String id,
    required String receiver,
    required String groupID,
    required MessagePriorityEnum priority,
    required bool onlineUserOnly,
    required bool isExcludedFromUnreadCount,
    required bool needReadReceipt,
    required OfflinePushInfo? offlinePushInfo,
    required String cloudCustomData,
    required String? localCustomData,
    required bool isExcludedFromContentModeration,
    required void Function(String syncMsgID) onSyncMsgID,
  }) {
    return service.sendMessage(
      id: id,
      receiver: receiver,
      groupID: groupID,
      priority: priority,
      onlineUserOnly: onlineUserOnly,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount,
      needReadReceipt: needReadReceipt,
      offlinePushInfo: offlinePushInfo,
      cloudCustomData: cloudCustomData,
      localCustomData: localCustomData,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
      onSyncMsgID: onSyncMsgID,
    );
  }

  @override
  Future<ImSdkHistoryResponse?> getHistoryMessageListWithComplete({
    required HistoryMsgGetTypeEnum getType,
    required String? userID,
    required String? groupID,
    required int lastMsgSeq,
    required int count,
    required String? lastMsgID,
    V2TimMessage? lastMsg,
    required List<int>? messageTypeList,
    required List<int>? messageSeqList,
    required int? timeBegin,
    required int? timePeriod,
  }) async {
    final result = await service.getHistoryMessageListWithStatus(
      getType: getType,
      userID: userID,
      groupID: groupID,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      lastMsg: lastMsg,
      messageTypeList: messageTypeList,
      messageSeqList: messageSeqList,
      timeBegin: timeBegin,
      timePeriod: timePeriod,
    );
    if (result.data == null && result.code == 0) return null;
    return ImSdkHistoryResponse(
      result: result.data,
      code: result.code,
      description: result.desc,
      actualSource: _sourceForGetType(getType),
      proofLevel: ImHistoryProofLevel.none,
    );
  }
}

class ImSdkHistoryResponse {
  const ImSdkHistoryResponse({
    required this.result,
    this.code = 0,
    this.description = 'OK',
    required this.actualSource,
    required this.proofLevel,
  });

  final V2TimMessageListResult? result;
  final int code;
  final String description;
  final ImHistorySource actualSource;
  final ImHistoryProofLevel proofLevel;
}

class ImSendResponse {
  const ImSendResponse({required this.identity, this.message});

  final OutgoingIdentityContract identity;
  final V2TimMessage? message;
}

class ImHistoryReadResponse {
  const ImHistoryReadResponse({required this.messages, required this.proof});

  final List<V2TimMessage> messages;
  final HistoryProof proof;
}

/// First SDK Adapter boundary for the IM migration.
///
/// This class owns cloudCustomData injection and converts SDK send/history
/// results into typed domain DTOs. It has no dependency on pages, TUIKit
/// global state, or the conversation store.
class TencentMessageAdapter {
  TencentMessageAdapter({
    required this.port,
    required this.platform,
    required String ownerUserId,
    required this.accountGeneration,
    required this.domainGeneration,
    required this.nextAccountIngressSequence,
    required this.nextScopeIngressSequence,
    this.onSyncIdentity,
  }) : ownerUserId = _requiredOwner(ownerUserId) {
    if (accountGeneration < 0 || domainGeneration < 0) {
      throw ArgumentError('adapter generations must be non-negative');
    }
  }

  final ImTencentMessagePort port;
  final ImPlatform platform;
  final String ownerUserId;
  final int accountGeneration;
  final int domainGeneration;
  final int Function() nextAccountIngressSequence;
  final int Function(AccountScopedConversationKey scope)
      nextScopeIngressSequence;
  final ImSyncIdentitySink? onSyncIdentity;

  Future<SdkResult<ImSendResponse>> send({
    required OutgoingIdentityContract identity,
    required String sdkLocalId,
    required String receiver,
    required String groupID,
    int sendOperationGeneration = 0,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool onlineUserOnly = false,
    bool isExcludedFromUnreadCount = false,
    bool needReadReceipt = false,
    OfflinePushInfo? offlinePushInfo,
    String? localCustomData,
    String? businessCloudCustomData,
    bool isExcludedFromContentModeration = false,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty) {
      return SdkResult<ImSendResponse>.failure(
        errorKind: SdkErrorKind.invalidArgument,
        resultDesc: 'sdkLocalId is required',
      );
    }
    final addressError = _validateAddress(identity.scope, receiver, groupID);
    if (addressError != null) {
      return SdkResult<ImSendResponse>.failure(
        errorKind: SdkErrorKind.invalidArgument,
        resultDesc: addressError,
      );
    }
    if (sendOperationGeneration < 0) {
      return SdkResult<ImSendResponse>.failure(
        errorKind: SdkErrorKind.invalidArgument,
        resultDesc: 'sendOperationGeneration must be non-negative',
      );
    }

    try {
      final result = await port.sendMessage(
        id: localId,
        receiver: receiver,
        groupID: groupID,
        priority: priority,
        onlineUserOnly: onlineUserOnly,
        isExcludedFromUnreadCount: isExcludedFromUnreadCount,
        needReadReceipt: needReadReceipt,
        offlinePushInfo: offlinePushInfo,
        cloudCustomData: identity.encodeCloudCustomData(
          businessCloudCustomData: businessCloudCustomData,
        ),
        localCustomData: localCustomData,
        isExcludedFromContentModeration: isExcludedFromContentModeration,
        onSyncMsgID: (syncMsgID) {
          _emitSyncIdentity(
            identity: identity,
            sdkLocalId: localId,
            syncMsgID: syncMsgID,
            sendOperationGeneration: sendOperationGeneration,
          );
        },
      );
      if (result.code != 0) {
        return SdkResult<ImSendResponse>.failure(
          errorKind: SdkErrorKind.sdk,
          code: result.code,
          resultDesc: result.desc,
        );
      }
      final formalIdentity = identity.withFormalIdentity(
        sdkLocalId: localId,
        serverMsgId: result.data?.msgID,
      );
      return SdkResult<ImSendResponse>.success(
        data: ImSendResponse(identity: formalIdentity, message: result.data),
        code: result.code,
        resultDesc: result.desc,
      );
    } on TimeoutException catch (error) {
      return SdkResult<ImSendResponse>.outcomeUnknown(
        resultDesc: error.toString(),
      );
    } catch (error) {
      // A transport exception does not prove that the provider rejected the
      // operation. The Outbox must query/adopt before offering a retry.
      return SdkResult<ImSendResponse>.outcomeUnknown(
        resultDesc: error.toString(),
      );
    }
  }

  Future<SdkResult<ImHistoryReadResponse>> readHistory({
    required AccountScopedConversationKey scope,
    required ImHistoryDirection direction,
    required ImHistorySource requestedSource,
    required int requestGeneration,
    required String requestId,
    required int count,
    int lastMsgSeq = -1,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
    String? requestFingerprint,
  }) async {
    if (scope.ownerUserId != ownerUserId) {
      return SdkResult<ImHistoryReadResponse>.failure(
        errorKind: SdkErrorKind.invalidArgument,
        resultDesc: 'history scope belongs to another account',
      );
    }
    if (requestGeneration < 0 || count <= 0) {
      return SdkResult<ImHistoryReadResponse>.failure(
        errorKind: SdkErrorKind.invalidArgument,
        resultDesc: 'invalid history request generation or count',
      );
    }
    final actualSource =
        platform == ImPlatform.web ? ImHistorySource.cloud : requestedSource;
    final getType = _historyGetType(
      source: actualSource,
      direction: direction,
    );
    final isC2c = scope.conversationType == ImConversationType.c2c;
    // Tencent's native C2C paginator is anchored by the complete last
    // message. Keep the ID for tracing/proof, but do not send two competing
    // cursor representations across the SDK boundary.
    final providerLastMsgID = isC2c && lastMsg != null ? null : lastMsgID;
    final providerLastMsgSeq = isC2c ? -1 : lastMsgSeq;
    try {
      final sdkResponse = await port
          .getHistoryMessageListWithComplete(
            getType: getType,
            userID: scope.conversationType == ImConversationType.c2c
                ? scope.conversationId.substring(4)
                : null,
            groupID: scope.conversationType == ImConversationType.group
                ? scope.conversationId.substring(6)
                : null,
            lastMsgSeq: providerLastMsgSeq,
            count: count,
            lastMsgID: providerLastMsgID,
            lastMsg: lastMsg,
            messageTypeList: messageTypeList,
            messageSeqList: messageSeqList,
            timeBegin: timeBegin,
            timePeriod: timePeriod,
          )
          .timeout(const Duration(seconds: 20));
      if (sdkResponse == null) {
        return SdkResult<ImHistoryReadResponse>.failure(
          errorKind: SdkErrorKind.unknown,
          resultDesc: 'SDK returned no history result',
        );
      }
      if (sdkResponse.code != 0 || sdkResponse.result == null) {
        return SdkResult<ImHistoryReadResponse>.failure(
          errorKind:
              sdkResponse.code == 0 ? SdkErrorKind.unknown : SdkErrorKind.sdk,
          code: sdkResponse.code == 0 ? null : sdkResponse.code,
          resultDesc: sdkResponse.description,
        );
      }
      final result = sdkResponse.result!;
      final messages = List<V2TimMessage>.unmodifiable(result.messageList);
      final proof = HistoryProof(
        scope: scope,
        platform: platform,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        requestGeneration: requestGeneration,
        requestId: requestId,
        direction: direction,
        requestedSource: requestedSource,
        actualSource: sdkResponse.actualSource,
        level: sdkResponse.proofLevel,
        returnedCount: messages.length,
        isFinished: result.isFinished,
        boundaryMessageIds: _messageIds(messages),
        overlapMessageIds: _overlapIds(
          messages,
          lastMsgID ?? lastMsg?.msgID,
        ),
        cursor: ImHistoryCursor(
            messageId: lastMsgID ?? lastMsg?.msgID,
            sequence: isC2c || lastMsgSeq <= 0 ? null : lastMsgSeq),
        oldestSequence: _oldestSequence(messages),
        newestSequence: _newestSequence(messages),
        requestFingerprint: requestFingerprint,
      );
      return SdkResult<ImHistoryReadResponse>.success(
        data: ImHistoryReadResponse(messages: messages, proof: proof),
      );
    } on TimeoutException catch (error) {
      return SdkResult<ImHistoryReadResponse>.failure(
        errorKind: SdkErrorKind.timeout,
        resultDesc: error.toString(),
      );
    } catch (error) {
      return SdkResult<ImHistoryReadResponse>.failure(
        errorKind: SdkErrorKind.unknown,
        resultDesc: error.toString(),
      );
    }
  }

  void _emitSyncIdentity({
    required OutgoingIdentityContract identity,
    required String sdkLocalId,
    required String syncMsgID,
    required int sendOperationGeneration,
  }) {
    final formalId = syncMsgID.trim();
    if (formalId.isEmpty || onSyncIdentity == null) return;
    final accountSequence = nextAccountIngressSequence();
    final scopeSequence = nextScopeIngressSequence(identity.scope);
    final event = EventEnvelope<OutgoingIdentityContract>(
      eventId: 'send-sync:${identity.operationId}:$formalId',
      eventNamespace: 'chat',
      kind: ImEventKind.outgoingAdoption,
      scope: identity.scope,
      ownerUserId: ownerUserId,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
      sendOperationGeneration: sendOperationGeneration,
      clearEpoch: 0,
      accountIngressSequence: accountSequence,
      scopeIngressSequence: scopeSequence,
      source: ImEventSource.sdkSend,
      authority: ImEventAuthority.provider,
      operationId: identity.operationId,
      observedAtMs: DateTime.now().millisecondsSinceEpoch,
      payload: identity.withFormalIdentity(
        sdkLocalId: sdkLocalId,
        serverMsgId: formalId,
      ),
    );
    onSyncIdentity!(event);
  }

  String? _validateAddress(
    AccountScopedConversationKey scope,
    String receiver,
    String groupID,
  ) {
    if (scope.ownerUserId != ownerUserId) {
      return 'outgoing scope belongs to another account';
    }
    final hasReceiver = receiver.trim().isNotEmpty;
    final hasGroup = groupID.trim().isNotEmpty;
    if (hasReceiver == hasGroup) {
      return 'exactly one of receiver and groupID is required';
    }
    final expected = AccountScopedConversationKey(
      ownerUserId: ownerUserId,
      conversationType:
          hasGroup ? ImConversationType.group : ImConversationType.c2c,
      conversationId: hasGroup ? groupID : receiver,
    );
    return expected == scope ? null : 'send address does not match scope';
  }
}

String _requiredOwner(String raw) {
  final owner = ChatIdFormat.rawUserUid(raw);
  if (owner.isEmpty) throw ArgumentError.value(raw, 'ownerUserId');
  return owner;
}

HistoryMsgGetTypeEnum _historyGetType({
  required ImHistorySource source,
  required ImHistoryDirection direction,
}) {
  final newer = direction == ImHistoryDirection.newer;
  if (source == ImHistorySource.local) {
    return newer
        ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
        : HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG;
  }
  return newer
      ? HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG
      : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG;
}

ImHistorySource _sourceForGetType(HistoryMsgGetTypeEnum getType) {
  switch (getType) {
    case HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG:
    case HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG:
      return ImHistorySource.local;
    case HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG:
    case HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG:
      return ImHistorySource.cloud;
    case HistoryMsgGetTypeEnum.V2TIM_NULL:
      return ImHistorySource.cloud;
  }
}

List<String> _messageIds(Iterable<V2TimMessage> messages) =>
    List<String>.unmodifiable(
      messages
          .map((message) => message.msgID?.trim() ?? '')
          .where((id) => id.isNotEmpty),
    );

List<String> _overlapIds(Iterable<V2TimMessage> messages, String? cursor) {
  final id = cursor?.trim() ?? '';
  if (id.isEmpty) return const <String>[];
  return _messageIds(messages)
      .where((value) => value == id)
      .toList(growable: false);
}

int? _oldestSequence(Iterable<V2TimMessage> messages) {
  final values = messages
      .map((message) => int.tryParse(message.seq?.trim() ?? ''))
      .whereType<int>()
      .toList();
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a < b ? a : b);
}

int? _newestSequence(Iterable<V2TimMessage> messages) {
  final values = messages
      .map((message) => int.tryParse(message.seq?.trim() ?? ''))
      .whereType<int>()
      .toList();
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a > b ? a : b);
}

~~~

77. [ConversationLocalImIngressStore](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:206>)，原文件 lib/src/services/im/im_ingress_store.dart，206–240 行。

~~~dart
/// Adapter from the project's existing SQLite owner to the IM persistence
/// contract. It deliberately exposes only IM table operations.
class ConversationLocalImIngressStore implements ImIngressStore {
  ConversationLocalImIngressStore({
    ConversationLocalStore? owner,
    MessageCoreStore? core,
  })  : _legacyOwner = owner,
        _core = core ?? MessageCoreStore.instance;

  /// Optional legacy owner is kept for existing contract tests and explicit
  /// migration tooling. Production construction uses [MessageCoreStore].
  final ConversationLocalStore? _legacyOwner;
  final MessageCoreStore _core;

  @override
  Future<T> transaction<T>(
    Future<T> Function(ImIngressTransaction transaction) action, {
    MessagePersistPriority persistPriority = MessagePersistPriority.realtime,
  }) {
    if (_legacyOwner != null) {
      return _legacyOwner!.runLegacyImIngressTransaction<T>(
        (transaction) => action(_SqliteImIngressTransaction(transaction)),
      );
    }
    return _core.runTransaction<T>(
      (transaction) => action(_SqliteImIngressTransaction(transaction)),
      persistPriority: persistPriority,
      persistSource: persistPriority == MessagePersistPriority.realtime
          ? MessagePersistSource.realtime
          : persistPriority == MessagePersistPriority.userHistory
              ? MessagePersistSource.userHistory
              : MessagePersistSource.backgroundRepair,
    );
  }
}
~~~

78. [_SqliteImIngressTransaction.findOutbox](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:820>)，原文件 lib/src/services/im/im_ingress_store.dart，820–832 行。

~~~dart
@override
  Future<ImOutboxRecord?> findOutbox({
    required String ownerUserId,
    required String operationId,
  }) async {
    final rows = await _db.query(
      _outboxTable,
      where: 'owner_user_id = ? AND operation_id = ?',
      whereArgs: <Object?>[ownerUserId, operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : imOutboxFromStorageMap(rows.first);
  }
~~~

79. [_SqliteImIngressTransaction.updateOutboxIfCurrent](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:878>)，原文件 lib/src/services/im/im_ingress_store.dart，878–906 行。

~~~dart
@override
  Future<bool> updateOutboxIfCurrent({
    required ImOutboxRecord record,
    required ImOutboxState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImOutboxTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
          record.ownerUserId,
          leaseOwnerId,
          fencingToken,
          nowMs,
        )) {
      return false;
    }
    final changed = await _db.update(
      _outboxTable,
      imOutboxToStorageMap(record),
      where: 'owner_user_id = ? AND operation_id = ? AND state = ?',
      whereArgs: <Object?>[
        record.ownerUserId,
        record.operationId,
        expectedState.name,
      ],
    );
    return changed == 1;
  }
~~~

80. [_SqliteImIngressTransaction.findOutboxRecovery](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:908>)，原文件 lib/src/services/im/im_ingress_store.dart，908–920 行。

~~~dart
@override
  Future<ImOutboxRecoveryRecord?> findOutboxRecovery({
    required String ownerUserId,
    required String operationId,
  }) async {
    final rows = await _db.query(
      _outboxRecoveryTable,
      where: 'owner_user_id = ? AND operation_id = ?',
      whereArgs: <Object?>[ownerUserId, operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : imOutboxRecoveryFromStorageMap(rows.first);
  }
~~~

81. [_SqliteImIngressTransaction.updateOutboxRecoveryIfCurrent](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:934>)，原文件 lib/src/services/im/im_ingress_store.dart，934–962 行。

~~~dart
@override
  Future<bool> updateOutboxRecoveryIfCurrent({
    required ImOutboxRecoveryRecord record,
    required ImOutboxCopyState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImOutboxRecoveryTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
          record.ownerUserId,
          leaseOwnerId,
          fencingToken,
          nowMs,
        )) {
      return false;
    }
    final changed = await _db.update(
      _outboxRecoveryTable,
      imOutboxRecoveryToStorageMap(record),
      where: 'owner_user_id = ? AND operation_id = ? AND state = ?',
      whereArgs: <Object?>[
        record.ownerUserId,
        record.operationId,
        expectedState.name,
      ],
    );
    return changed == 1;
  }
~~~

82. [_InputTextFieldState._setProgrammaticText](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart:231>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart，231–248 行。

~~~dart
/// 更新输入框内容时一次性提交 text/selection/composing，避免 iOS 中文输入法
  /// 在拼音组合期间收到“先改 text、再改 selection”的两次状态同步后切换输入模式。
  void _setProgrammaticText(
    String text, {
    int? selectionOffset,
    bool notifyChanged = true,
  }) {
    final previousText = textEditingController.text;
    final offset = (selectionOffset ?? text.length).clamp(0, text.length);
    textEditingController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
    if (notifyChanged && previousText != text) {
      widget.onChanged?.call(text);
    }
  }
~~~

83. [_InputTextFieldState.handleSetDraftText](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart:339>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart，339–359 行。

~~~dart
Future handleSetDraftText(
      {String? id, ConvType? convType, String? groupID}) async {
    if (!widget.model.chatConfig.isUseDraft) {
      return V2TimCallback(code: 0, desc: '');
    }
    String text = textEditingController.text;
    String convID = id ?? widget.conversationID;
    final isTopic = convID.contains("@TOPIC#");
    String conversationID = isTopic
        ? convID
        : ((convType ?? widget.conversationType) == ConvType.c2c
            ? "${TUIConversationViewModel.conversationC2CPrefix}$convID"
            : "${TUIConversationViewModel.conversationGroupPrefix}$convID");
    String draftText = _filterU200b(text);
    return await conversationModel.setConversationDraft(
        groupID: groupID ?? widget.groupID,
        isTopic: isTopic,
        isAllowWeb: widget.model.chatConfig.isUseDraftOnWeb,
        conversationID: conversationID,
        draftText: draftText);
  }
~~~

84. [_InputTextFieldState._onEmojiSubmitted](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart:362>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart，362–394 行。

~~~dart
_onEmojiSubmitted() {
    lastText = "";
    final text = textEditingController.text.trim();
    final convType = widget.conversationType;
    conversationModel.clearWebDraft(conversationID: widget.conversationID);
    if (text.isNotEmpty && text != zeroWidthSpace) {
      if (widget.model.repliedMessage != null) {
        MessageUtils.handleMessageError(
            widget.model.sendReplyMessage(
              text: text,
              convID: widget.conversationID,
              convType: convType,
              atUserIDList: getUserIdFromMemberInfoMap(),
            ),
            context);
      } else {
        MessageUtils.handleMessageError(
            widget.model.sendTextMessage(
              text: text,
              convID: widget.conversationID,
              convType: convType,
            ),
            context);
      }
      textEditingController.clear();
      // Controller mutations do not invoke TextField.onChanged. Notify the
      // host explicitly so its local draft is cleared at send intent instead
      // of waiting for the asynchronous messageDidSend callback.
      widget.onChanged?.call("");
      goDownBottom(fromOutgoingSend: true);
    }
    currentCursor = null;
  }
~~~

85. [_InputTextFieldState.onSubmitted](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart:471>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart，471–510 行。

~~~dart
onSubmitted() async {
    conversationModel.clearWebDraft(conversationID: widget.conversationID);
    lastText = "";
    final text = textEditingController.text.trim();
    final convType = widget.conversationType;
    if (text.isNotEmpty && text != zeroWidthSpace) {
      final mentionOccurrences = _mentionOccurrencesForSend(text);
      if (widget.model.repliedMessage != null) {
        MessageUtils.handleMessageError(
            widget.model.sendReplyMessage(
                text: text,
                convID: widget.conversationID,
                convType: convType,
                atUserIDList: getUserIdFromMemberInfoMap(),
                mentionOccurrences: mentionOccurrences),
            context);
      } else if (mentionedMembersMap.isNotEmpty) {
        widget.model.sendTextAtMessage(
            text: text,
            convType: widget.conversationType,
            convID: widget.conversationID,
            atUserList: getUserIdFromMemberInfoMap(),
            mentionOccurrences: mentionOccurrences);
      } else {
        MessageUtils.handleMessageError(
            widget.model.sendTextMessage(
                text: text, convID: widget.conversationID, convType: convType),
            context);
      }
      textEditingController.clear();
      widget.onChanged?.call("");
      currentCursor = null;
      lastText = "";
      _clearMentionState();

      widget.controller?.markOutgoingMessageSend();
      goDownBottom(fromOutgoingSend: true);
      _handleSendEditStatus("", false);
    }
  }
~~~

86. [_InputTextFieldState.controllerHandler](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart:1039>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart，1039–1087 行。

~~~dart
controllerHandler() {
    final actionType = widget.controller?.actionType;
    if (actionType == ActionType.longPressToAt) {
      final pinToLatestAfterAt =
          widget.controller?.pinToLatestAfterAt ?? false;
      widget.controller?.pinToLatestAfterAt = false;
      widget.controller?.actionType = null;
      final atUserID = widget.controller?.atUserID;
      final atUserName = widget.controller?.atUserName;
      if (pinToLatestAfterAt) {
        unawaited(_pinToLatestThenMention(atUserID, atUserName));
      } else {
        mentionMemberInMessage(atUserID, atUserName);
      }
      return;
    } else if (actionType == ActionType.setTextField) {
      final newText = widget.controller?.inputText ?? "";
      _setProgrammaticText(
        newText,
        notifyChanged: widget.controller?.notifyOnSetTextField ?? true,
      );
      widget.controller?.notifyOnSetTextField = true;
      lastText = textEditingController.text;
      focusNode.requestFocus();
      _narrowTextFieldKey.currentState?.setSendButton();
      widget.controller?.actionType = null;
      return;
    } else if (actionType == ActionType.requestFocus) {
      focusNode.requestFocus();
      widget.controller?.actionType = null;
      return;
    } else if (actionType == ActionType.handleAtMember) {
      handleAtMember(memberInfo: widget.controller?.groupMemberFullInfo);
      widget.controller?.actionType = null;
      return;
    } else if (actionType == ActionType.hideAllPanel) {
      widget.controller?.actionType = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _narrowTextFieldKey.currentState?.hideAllPanel();
      });
      return;
    } else if (actionType == ActionType.hideAccessoryPanel) {
      widget.controller?.actionType = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _narrowTextFieldKey.currentState?.hideAccessoryPanels();
      });
      return;
    }
  }
~~~

87. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/message_core_store.dart:1>)，原文件 lib/src/services/im/message_core_store.dart，1–554 行。

~~~dart
import 'receipt_recovery_compat.dart';
import 'dart:async';

import 'im_inbox_recovery_query.dart';
import 'runtime_commit_schema.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

/// SQLite owner for the realtime message core.
///
/// This database intentionally contains only ingress, lease, journal,
/// projection and outbox state.  Conversation indexes and contact snapshots
/// remain in their existing databases, so a large sync write cannot hold the
/// realtime writer transaction open.
class MessageCoreStore {
  MessageCoreStore._();

  static final MessageCoreStore instance = MessageCoreStore._();

  static const String dbName = 'message_core.db';
  static const int _dbVersion = 1;

  static const List<String> _coreTables = <String>[
    'message_event_inbox',
    'message_writer_lease',
    'message_ingress_counter',
    'message_commit_journal',
    'message_projection_checkpoint',
    'message_commit_effect',
    'message_outbox',
    'message_outbox_recovery_copy',
    // These two durable P0 queues are created lazily by their stores, but are
    // part of the message-core failure domain as well.
    'read_receipt_outbox',
    'conversation_read_outbox',
  ];

  Database? _db;
  Future<Database>? _openInFlight;
  bool _factoryReady = false;

  Future<void> _ensureFactory() async {
    if (_factoryReady) return;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryReady = true;
  }

  Future<Database> _openDb() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) return existing;
    final pending = _openInFlight;
    if (pending != null) return pending;
    final task = _openDbOnce();
    _openInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_openInFlight, task)) _openInFlight = null;
    }
  }

  Future<Database> _openDbOnce() async {
    final stopwatch = Stopwatch()..start();
    var created = false;
    await _ensureFactory();
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (database) async {
        // PRAGMA assignments return a result row on Android SQLite. sqflite
        // therefore requires rawQuery rather than execute; execute closes the
        // database with "Queries can be performed ... only".
        await database.rawQuery('PRAGMA journal_mode=WAL');
        // FFB-2 扩散：iOS sqflite_darwin 启动期 PRAGMA 救火。
        // 失败不阻断 DB open（WAL 已经生效，busy_timeout 失败仅降低并发排队上限）。
        await SqfliteBootstrapHelper.withTag('msg_core')
            .runOnOpenPragmasRawQuery(database);
      },
      onCreate: (database, _) async {
        await _createSchema(database);
        created = true;
      },
      onOpen: (database) async {
        await _ensureInboxRecoveryColumns(database);
        // Keep upgrades/recovered databases safe even when onCreate did not
        // run (for example, a partially restored file).
        if (!created) {
          final rows = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
          );
          final names = rows.map((row) => row['name']).toSet();
          if (!_schemaObjects.every(names.contains)) {
            await _createSchema(database);
          }
        }
      },
    );
    StartupPerfLog.markTagged('message_core_db_open',
        category: 'cold_start',
        details: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'created': created
        });
    try {
      await _migrateLegacyTablesIfNeeded(db, basePath);
    } catch (_) {
      // The new database remains usable.  The old database is never deleted or
      // modified, and the migration marker is intentionally not written so a
      // later open can retry it.
    }
    try {
      await migratePendingReceiptBatches(db);
    } catch (_) {
      // A failed atomic conversion remains pending for retry. Do not leak an
      // opened handle outside _db or let recovery observe a partial upgrade.
      await SqfliteLifecycleGuard.closeDatabase(db);
      rethrow;
    }
    if (!SqfliteLifecycleGuard.instance.canOpenDatabase) {
      await SqfliteLifecycleGuard.closeDatabase(db);
      _db = null;
      throw const SqfliteClosedForBackground();
    }
    _db = db;
    StartupPerfLog.markTagged('message_core_db_ready',
        category: 'cold_start',
        details: {'durationMs': stopwatch.elapsedMilliseconds});
    return db;
  }

  static const _schemaObjects = <String>{
    ...RuntimeCommitSchema.objects,
    'message_event_inbox',
    'idx_message_event_scope',
    'idx_message_event_recovery_operation',
    'idx_message_event_account_sequence',
    'idx_message_event_scope_sequence',
    ImInboxRecoveryQuery.indexName,
    'message_writer_lease',
    'message_ingress_counter',
    'message_commit_journal',
    'message_projection_checkpoint',
    'message_commit_effect',
    'message_outbox',
    'idx_message_outbox_ready',
    'message_outbox_recovery_copy',
    'read_receipt_outbox',
    'idx_read_receipt_outbox_due',
    'conversation_read_outbox',
    'idx_conversation_read_outbox_due',
    'message_core_meta',
  };

  Future<void> _createSchema(DatabaseExecutor db) async {
    final batch = db.batch();
    RuntimeCommitSchema.addTo(batch);
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_event_inbox (
        owner_user_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_namespace TEXT NOT NULL,
        conversation_id TEXT NOT NULL DEFAULT '',
        event_kind TEXT NOT NULL,
        operation_id TEXT NOT NULL DEFAULT '',
        account_generation INTEGER NOT NULL,
        domain_generation INTEGER NOT NULL,
        source TEXT NOT NULL,
        authority TEXT NOT NULL,
        view_instance_id TEXT NOT NULL DEFAULT '',
        surface_id TEXT NOT NULL DEFAULT '',
        view_session_generation INTEGER,
        history_request_generation INTEGER,
        send_operation_generation INTEGER,
        clear_epoch INTEGER NOT NULL,
        account_ingress_sequence INTEGER NOT NULL,
        scope_ingress_sequence INTEGER NOT NULL,
        provider_sequence INTEGER,
        source_revision INTEGER,
        membership_revision INTEGER,
        payload_hash TEXT NOT NULL,
        recovery_mode TEXT NOT NULL,
        recovery_ref TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        observed_at INTEGER NOT NULL,
        committed_at INTEGER,
        processing_started_at INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        last_error_class TEXT NOT NULL DEFAULT '',
        recovery_priority INTEGER NOT NULL DEFAULT 2,
        PRIMARY KEY(owner_user_id, event_namespace, event_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_event_scope
      ON message_event_inbox(owner_user_id, conversation_id, status)
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_event_recovery_operation
      ON message_event_inbox(owner_user_id, event_namespace, operation_id)
    ''');
    batch.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_message_event_account_sequence
      ON message_event_inbox(owner_user_id, account_ingress_sequence)
    ''');
    batch.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_message_event_scope_sequence
      ON message_event_inbox(owner_user_id, conversation_id, scope_ingress_sequence)
      WHERE conversation_id <> ''
    ''');
    // Completed/abandoned identities stay durable. Recovery only walks due
    // rows through (status, next_retry_at) matching this partial index.
    batch.execute('''
      CREATE INDEX IF NOT EXISTS ${ImInboxRecoveryQuery.indexName}
      ON message_event_inbox(owner_user_id, account_generation,
                            recovery_priority, next_retry_at)
      WHERE ${ImInboxRecoveryQuery.pendingPredicate}
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_writer_lease (
        owner_user_id TEXT PRIMARY KEY,
        lease_owner_id TEXT NOT NULL,
        fencing_token INTEGER NOT NULL,
        acquired_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        heartbeat_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_ingress_counter (
        owner_user_id TEXT NOT NULL,
        scope_key TEXT NOT NULL,
        next_sequence INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, scope_key)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_commit_journal (
        owner_user_id TEXT NOT NULL,
        journal_id TEXT NOT NULL,
        event_namespace TEXT NOT NULL,
        event_id TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT '',
        commit_revision INTEGER NOT NULL,
        state TEXT NOT NULL,
        metadata_revision INTEGER,
        projection_revision INTEGER,
        side_effect_revision INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, journal_id),
        UNIQUE(owner_user_id, event_namespace, event_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_projection_checkpoint (
        owner_user_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        commit_revision INTEGER NOT NULL,
        last_journal_id TEXT NOT NULL,
        coverage_revision INTEGER NOT NULL,
        watermark_revision INTEGER NOT NULL,
        barrier_revision INTEGER NOT NULL,
        projection_version INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, scope)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_commit_effect (
        owner_user_id TEXT NOT NULL,
        effect_id TEXT NOT NULL,
        journal_id TEXT NOT NULL,
        effect_kind TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, effect_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_outbox (
        operation_id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        client_correlation_id TEXT NOT NULL,
        message_type INTEGER NOT NULL,
        payload_reference TEXT NOT NULL,
        media_local_ref TEXT,
        encryption_version INTEGER,
        key_id TEXT,
        cipher_algorithm TEXT,
        nonce TEXT,
        content_checksum TEXT,
        payload_hash TEXT NOT NULL DEFAULT '',
        state TEXT NOT NULL,
        sdk_message_id TEXT,
        server_msg_id TEXT,
        dispatch_attempt_id TEXT,
        dispatch_intent_at INTEGER,
        result_code TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        recovery_lag INTEGER NOT NULL DEFAULT 0,
        recovery_conflict INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_outbox_ready
      ON message_outbox(owner_user_id, state, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_outbox_recovery_copy (
        owner_user_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        client_correlation_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        message_type INTEGER NOT NULL,
        recovery_revision INTEGER NOT NULL,
        state TEXT NOT NULL,
        dispatch_attempt_id TEXT,
        dispatch_intent_at INTEGER,
        payload_reference_or_ciphertext TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        checksum TEXT NOT NULL,
        sdk_local_id TEXT,
        server_msg_id TEXT,
        result_code TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, operation_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS read_receipt_outbox (
        owner_user_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, message_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_read_receipt_outbox_due
      ON read_receipt_outbox(owner_user_id, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS conversation_read_outbox (
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        last_read_message_id TEXT NOT NULL DEFAULT '',
        clean_timestamp INTEGER NOT NULL DEFAULT 0,
        clean_sequence INTEGER NOT NULL DEFAULT 0,
        last_read_at INTEGER NOT NULL DEFAULT 0,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, conversation_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_conversation_read_outbox_due
      ON conversation_read_outbox(owner_user_id, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_core_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await batch.commit(noResult: true);
  }

  Future<void> _ensureInboxRecoveryColumns(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(message_event_inbox)');
    if (info.isEmpty) return;
    final names = info.map((row) => row['name']?.toString() ?? '').toSet();
    Future<void> add(String column, String spec) async {
      if (names.contains(column)) return;
      await db.execute(
        'ALTER TABLE message_event_inbox ADD COLUMN $column $spec',
      );
    }

    await add('retry_count', 'INTEGER NOT NULL DEFAULT 0');
    await add('next_retry_at', 'INTEGER NOT NULL DEFAULT 0');
    await add('last_error_class', "TEXT NOT NULL DEFAULT ''");
    await add('recovery_priority', 'INTEGER NOT NULL DEFAULT 2');
    await db.execute(
      'DROP INDEX IF EXISTS ${ImInboxRecoveryQuery.legacyIndexName}',
    );
  }

  Future<void> _migrateLegacyTablesIfNeeded(
    Database target,
    String basePath,
  ) async {
    final marker = await target.query(
      'message_core_meta',
      where: 'key = ?',
      whereArgs: const <Object?>['legacy_migration_v1'],
      limit: 1,
    );
    if (marker.isNotEmpty) return;
    final legacyPath = p.join(basePath, 'conversation_local_v1.db');
    if (!await databaseFactory.databaseExists(legacyPath)) {
      await _markLegacyMigrationComplete(target);
      return;
    }

    // ConversationLocalStore may still have the legacy file open while the
    // first realtime transaction starts. Use a separate read-only handle so
    // migration never steals or closes that owner connection.
    final legacy = await openDatabase(
      legacyPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final tables = await legacy.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final available =
          tables.map((row) => row['name']?.toString() ?? '').toSet();
      for (final table in _coreTables) {
        if (!available.contains(table)) {
          continue;
        }
        await _copyTable(legacy, target, table);
      }
      await _markLegacyMigrationComplete(target);
    } finally {
      await SqfliteLifecycleGuard.closeDatabase(legacy);
    }
  }

  Future<void> _markLegacyMigrationComplete(Database target) => target
      .insert(
        'message_core_meta',
        const {'key': 'legacy_migration_v1', 'value': 'complete'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      )
      .then((_) {});

  Future<void> _copyTable(
    Database source,
    Database target,
    String table,
  ) async {
    final sourceInfo = await source.rawQuery('PRAGMA table_info($table)');
    final targetInfo = await target.rawQuery('PRAGMA table_info($table)');
    final targetColumns = targetInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final columns = sourceInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty && targetColumns.contains(name))
        .toList(growable: false);
    if (columns.isEmpty) return;
    final names = columns.map(_quoteIdentifier).join(', ');
    final placeholders = List<String>.filled(columns.length, '?').join(', ');
    var offset = 0;
    while (true) {
      final rows = await source.query(
        table,
        columns: columns,
        limit: 500,
        offset: offset,
      );
      if (rows.isEmpty) break;
      await target.transaction<void>((txn) async {
        final batch = txn.batch();
        for (final row in rows) {
          batch.rawInsert(
            'INSERT OR IGNORE INTO ${_quoteIdentifier(table)} ($names) '
            'VALUES ($placeholders)',
            columns.map((column) => row[column]).toList(growable: false),
          );
        }
        await batch.commit(noResult: true);
      });
      offset += rows.length;
      if (rows.length < 500) break;
    }
  }

  static String _quoteIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  Future<T> runTransaction<T>(
    Future<T> Function(DatabaseExecutor transaction) action, {
    MessagePersistPriority persistPriority =
        MessagePersistPriority.userHistory,
    MessagePersistSource persistSource = MessagePersistSource.userHistory,
    String conversationId = '',
    int accountGeneration = 0,
    int itemCount = 1,
  }) {
    return MessagePersistCoordinator.instance.enqueue<T>(
      priority: persistPriority,
      source: persistSource,
      conversationId: conversationId,
      accountGeneration: accountGeneration,
      itemCount: itemCount,
      run: () async {
        final db = await _openDb();
        return db.transaction<T>((transaction) => action(transaction));
      },
    );
  }

  Future<void> closeIfOpen() async {
    final opening = _openInFlight;
    if (opening != null) {
      try {
        await opening.timeout(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
  }
}

~~~

88. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/utils/c2c_blocked_outgoing_message_sync.dart:1>)，原文件 lib/src/utils/c2c_blocked_outgoing_message_sync.dart，1–85 行。

~~~dart
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';

/// When C2C send permission becomes blocked, reconcile in-flight self messages.
class C2cBlockedOutgoingMessageSync {
  C2cBlockedOutgoingMessageSync._();

  static const int blockedCode = 20011;
  static const String relationBlockedReason = 'relation_blocked';

  /// Returns a failed clone when [message] is an in-flight self message.
  static V2TimMessage? reconcileInFlightMessage(V2TimMessage message) {
    if (message.isSelf != true) {
      return null;
    }
    if (message.status != MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      return null;
    }
    V2TimMessage updated;
    try {
      final map = Map<String, dynamic>.from(message.toJson());
      map['message_status'] = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
      updated = V2TimMessage.fromJson(map);
    } catch (_) {
      updated = message;
      updated.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    ErrorMessageConverter.attachSendFailCode(updated, blockedCode);
    return updated;
  }

  static bool shouldMarkInFlight({required String reason}) {
    return reason == relationBlockedReason;
  }

  static void markInFlightAsFriendBlocked({
    required String conversationID,
    required TUIChatGlobalModel globalModel,
    String reason = '',
  }) {
    if (!shouldMarkInFlight(reason: reason)) {
      return;
    }
    final convID = conversationID.trim();
    if (convID.isEmpty) {
      return;
    }
    final list = globalModel.messageListMap[convID];
    if (list == null || list.isEmpty) {
      return;
    }

    for (final msg in list) {
      final reconciled = reconcileInFlightMessage(msg);
      if (reconciled == null) {
        continue;
      }
      final clientId = msg.id?.trim().isNotEmpty == true
          ? msg.id!.trim()
          : (msg.msgID?.trim() ?? '');
      if (clientId.isEmpty) {
        continue;
      }
      globalModel.applyOutgoingSendResult(
        V2TimValueCallback<V2TimMessage>(
          code: blockedCode,
          desc: 'friend relation blocked',
          data: reconciled,
        ),
        convID,
        clientId,
        ConvType.c2c,
        null,
        null,
      );
    }
  }
}

~~~

89. [ConversationSyncService._adoptProviderOutgoingMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1251>)，原文件 lib/src/services/conversation_local/conversation_sync_service.dart，1251–1273 行。

~~~dart
Future<bool> _adoptProviderOutgoingMessage(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
    required ImWriterLease lease,
  }) async {
    final outgoing = _providerOutgoingIdentity(event, identity: identity);
    if (outgoing == null) return false;
    final payload = event.payload as V2TimMessage;
    return Im05Persistence(
      store: _messageIngressStore,
    ).adoptOutboxProviderSucceeded(
      ownerUserId: identity.ownerUserId,
      operationId: outgoing.operationId,
      clientCorrelationId: outgoing.clientCorrelationId,
      conversationId: outgoing.scope.storageKey,
      payloadHash: outgoing.payloadFingerprint,
      leaseOwnerId: lease.leaseOwnerId,
      fencingToken: lease.fencingToken,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      sdkLocalId: payload.id,
      serverMsgId: payload.msgID,
    );
  }
~~~

90. [ConversationSyncService._handleMessageIngress](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1081>)，原文件 lib/src/services/conversation_local/conversation_sync_service.dart，1081–1180 行。

~~~dart
Future<void> _handleMessageIngress(EventEnvelope<dynamic> event) async {
    final identity = _realtimeIdentity;
    if (identity == null ||
        !event.belongsToDomain(
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
          domainGeneration: _messageDomainGeneration,
        )) {
      return;
    }
    if (event.eventNamespace ==
        TencentAdvancedMessageAdapter.sdkRealtimeNamespace) {
      await _handleSdkRealtimeMessage(event, identity);
      return;
    }
    if (!await _hasCurrentMessageCoreLease(identity)) {
      return;
    }
    final lease = _messageCoreLease;
    if (lease == null) return;
    final claimed = await _messageIngress.claimForWriter(
      event: event,
      lease: lease,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      allowStaleProcessing: true,
      processingTimeoutMs: _messageRecoveryInterval.inMilliseconds,
    );
    if (claimed == null || claimed.status == ImInboxStatus.completed) {
      return;
    }
    try {
      await const RuntimeIngressProcessor().run(
        status: claimed.status,
        // Heartbeats renew the lease object without replacing its ownership.
        // Fence by owner/token so healthy renewals do not reject a valid turn.
        isCurrent: () =>
            _isCurrentRealtimeIdentity(identity) &&
            event.domainGeneration == _messageDomainGeneration &&
            _messageCoreLease?.leaseOwnerId == lease.leaseOwnerId &&
            _messageCoreLease?.fencingToken == lease.fencingToken,
        applyMetadata: () =>
            _applyMessageIngressMetadata(event, identity: identity),
        flushMetadata: () => _ingressPersistFlush.request(),
        advance: (from, to) => _advanceMessageInboxStatus(
          event: event,
          identity: identity,
          expectedStatus: from,
          nextStatus: to,
        ),
        adoptOutgoing: () => _adoptProviderOutgoingMessage(
          event, identity: identity, lease: lease),
        publish: () =>
            _publishMessageIngressProjection(event, identity: identity),
        completeOutgoing: () async {
          final outgoing = _providerOutgoingIdentity(event, identity: identity);
          if (outgoing == null) return;
          final completed = await Im05Persistence(store: _messageIngressStore)
              .completeOutboxProjection(
            ownerUserId: identity.ownerUserId,
            operationId: outgoing.operationId,
            leaseOwnerId: lease.leaseOwnerId,
            fencingToken: lease.fencingToken,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (!completed) {
            throw StateError(
              'provider Outbox projection completion was rejected',
            );
          }
        },
      );
    } catch (error, stack) {
      // Leave PROCESSING durable. Recovery must replay the event rather than
      // treating a failed compatibility projection as completed.
      debugPrint(
        'CHAT_INGRESS_HANDLER_FAILURE kind=${event.kind.name} '
        'eventId=${event.eventId} errorType=${error.runtimeType} '
        'error=$error\n$stack',
      );
      if (claimed.status != ImInboxStatus.completed) {
        try {
          await _messageIngress.scheduleRetry(
            record: claimed,
            errorClass: InboxRecoveryPolicy.classify(error),
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {}
        InboxRecoveryCoordinator.instance.request(
          trigger: InboxRecoveryTrigger.retryDue,
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
          nextRetryAtMs: InboxRecoveryPolicy.nextRetryAtMs(
            nowMs: DateTime.now().millisecondsSinceEpoch,
            retryCount: claimed.retryCount,
            jitterMs: 0,
          ),
        );
      }
    }
  }
~~~

91. [ConversationSyncService._handleSdkRealtimeMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1182>)，原文件 lib/src/services/conversation_local/conversation_sync_service.dart，1182–1206 行。

~~~dart
Future<void> _handleSdkRealtimeMessage(
      EventEnvelope<dynamic> event, SessionIdentity identity) async {
    final message = event.payload;
    final conversationID = event.scope?.canonicalConversationId;
    if (message is! V2TimMessage || conversationID == null) return;
    final model = serviceLocator<TUIChatGlobalModel>();
    if (!_isCurrentRealtimeIdentity(identity) ||
        model.messageDeltaClearEpochFor(conversationID) != event.clearEpoch)
      return;
    // The adapter sequence is process-local mailbox order, not an Inbox fence.
    // SDK history supplies recovery; reading-away delivery keeps its existing
    // stable message identity and durable UI watermark without a formal sequence.
    await model.applyAppRealtimeMessage(
      message,
      ingressEventID: event.eventId,
      projectMessageList:
          ActiveChatRegistry.instance.matchesOpenConversation(conversationID),
    );
    if (!_isCurrentRealtimeIdentity(identity) ||
        model.messageDeltaClearEpochFor(conversationID) != event.clearEpoch)
      return;
    // Notification work must not hold the next message behind an app database
    // or platform call. SDK conversation callbacks own preview and unread state.
    unawaited(_publishSdkRealtimeSideEffects(message, identity));
  }
~~~

92. [ConversationSyncService._providerOutgoingIdentity](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1229>)，原文件 lib/src/services/conversation_local/conversation_sync_service.dart，1229–1249 行。

~~~dart
OutgoingIdentityContract? _providerOutgoingIdentity(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
  }) {
    if (event.kind != ImEventKind.realtimeMessage &&
        event.kind != ImEventKind.messageMutation) {
      return null;
    }
    final payload = event.payload;
    final scope = event.scope;
    if (payload is! V2TimMessage ||
        payload.isSelf != true ||
        scope == null ||
        scope.ownerUserId != identity.ownerUserId) {
      return null;
    }
    return OutgoingIdentityContract.fromCloudCustomData(
      payload.cloudCustomData,
      scope: scope,
    );
  }
~~~

93. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/outgoing_outbox_recovery_service.dart:1>)，原文件 lib/src/services/im/outgoing_outbox_recovery_service.dart，1–258 行。

~~~dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_message_recreator.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// Recovers only operations that never crossed DispatchIntent.
///
/// Prepared is safe to dispatch because the Coordinator writes
/// DispatchIntent immediately before the SDK call. dispatchIntent/sending are
/// OutcomeUnknown and are never automatically resent.
class OutgoingOutboxRecoveryService {
  OutgoingOutboxRecoveryService._();

  static final OutgoingOutboxRecoveryService instance =
      OutgoingOutboxRecoveryService._();

  Future<void>? _inFlight;

  Future<void> recoverPending() {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> task;
    task = _recover().whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
    _inFlight = task;
    return task;
  }

  Future<void> _recover() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    var context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    for (var attempt = 0; context == null && attempt < 5; attempt++) {
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      await Future<void>.delayed(
        Duration(milliseconds: 100 * (1 << attempt)),
      );
      context = await ConversationSyncService.instance
          .messageCoreLeaseForOutgoingSend();
    }
    if (context == null || context.ownerUserId != identity.ownerUserId) return;
    final persistence = Im05Persistence(store: context.store);
    final activeRows = await persistence.listOutboxesForRecovery(
      ownerUserId: identity.ownerUserId,
      states: const <ImOutboxState>[
        ImOutboxState.created,
        ImOutboxState.preparing,
        ImOutboxState.prepared,
        ImOutboxState.dispatchIntent,
        ImOutboxState.sending,
        ImOutboxState.outcomeUnknown,
        ImOutboxState.retryable,
        ImOutboxState.acknowledged,
        ImOutboxState.manualRequired,
        ImOutboxState.pausedByLogout,
      ],
      limit: 5000,
    );
    // If the safety scan hit its cap, preserve everything instead of deleting
    // a directory whose Outbox row may be beyond this page.
    if (activeRows.length < 5000) {
      await OutgoingMediaStager.instance.cleanupOrphans(
        activeRootPaths: activeRows.map((row) => row.mediaLocalRef),
      );
      await OutgoingMediaStager.instance.cleanupLiveOrphans();
    }
    for (var page = 0; page < 10; page++) {
      final rows = await persistence.listOutboxesForRecovery(
        ownerUserId: identity.ownerUserId,
        states: const <ImOutboxState>[
          ImOutboxState.prepared,
          ImOutboxState.dispatchIntent,
          ImOutboxState.sending,
        ],
        limit: 100,
      );
      if (rows.isEmpty) return;
      var madeProgress = false;
      for (final row in rows) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        if (row.state != ImOutboxState.prepared) {
          madeProgress = await persistence.recordOutcomeUnknown(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
                resultCode: 'recovered_after_dispatch_intent',
              ) ||
              madeProgress;
          continue;
        }
        final plaintext = await OutboxPayloadCipher.instance.reveal(
          ownerUserId: identity.ownerUserId,
          value: row.payloadReference,
        );
        final envelope = plaintext == null ? null : _decodeEnvelope(plaintext);
        if (envelope == null) {
          madeProgress = await persistence.markPreparedOutboxManualRequired(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                reason: plaintext == null
                    ? 'payload_key_unavailable_or_ciphertext_invalid'
                    : 'payload_envelope_invalid',
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
              ) ||
              madeProgress;
          debugPrint(
            'OUTBOX_RECOVERY manual required for prepared payload '
            'operationId=${row.operationId}',
          );
          continue;
        }
        final recreated = await recreateOutgoingMessage(
          serviceLocator<MessageService>(),
          envelope.message,
        );
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        if (recreated?.messageInfo == null ||
            (recreated?.id?.trim().isEmpty ?? true)) {
          madeProgress = await persistence.markPreparedOutboxManualRequired(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                reason: 'message_recreation_failed',
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
              ) ||
              madeProgress;
          debugPrint(
            'OUTBOX_RECOVERY manual required; cannot recreate payload '
            'operationId=${row.operationId}',
          );
          continue;
        }
        final result =
            await ChatExternalMessageSender.sendCreatedMessageDetailed(
          messageInfo: recreated!.messageInfo,
          receiverUserId: envelope.receiver,
          groupId: envelope.groupId,
          reason: 'outbox_prepared_recovery',
          isExcludedFromUnreadCount: envelope.isExcludedFromUnreadCount,
          priority: envelope.priority,
          onlineUserOnly: envelope.onlineUserOnly,
          needReadReceipt: envelope.needReadReceipt,
          offlinePushInfo: envelope.offlinePushInfo,
          cloudCustomData: envelope.cloudCustomData,
          localCustomData: envelope.localCustomData,
          recoverPreparedOutbox: true,
          operationIdOverride: row.operationId,
          clientCorrelationIdOverride: row.clientCorrelationId,
        );
        madeProgress =
            result.state != ExternalMessageSendState.blocked || madeProgress;
        if (result.state == ExternalMessageSendState.blocked) {
          debugPrint(
            'OUTBOX_RECOVERY blocked operationId=${row.operationId}',
          );
        }
      }
      if (rows.length < 100 || !madeProgress) return;
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _RecoveredOutgoingEnvelope {
  const _RecoveredOutgoingEnvelope({
    required this.message,
    required this.receiver,
    required this.groupId,
    required this.isExcludedFromUnreadCount,
    required this.priority,
    required this.onlineUserOnly,
    required this.needReadReceipt,
    required this.offlinePushInfo,
    required this.cloudCustomData,
    required this.localCustomData,
  });

  final V2TimMessage message;
  final String receiver;
  final String groupId;
  final bool isExcludedFromUnreadCount;
  final MessagePriorityEnum priority;
  final bool onlineUserOnly;
  final bool needReadReceipt;
  final OfflinePushInfo? offlinePushInfo;
  final String? cloudCustomData;
  final String? localCustomData;
}

_RecoveredOutgoingEnvelope? _decodeEnvelope(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['schemaVersion'] != 1) return null;
    final messageJson = decoded['message'];
    if (messageJson is! Map) return null;
    final message = V2TimMessage.fromJson(
      Map<String, dynamic>.from(messageJson),
    );
    final storedLocalId = decoded['sdkLocalId']?.toString().trim() ?? '';
    final messageLocalId = message.id?.trim() ?? '';
    if (storedLocalId.isEmpty ||
        (messageLocalId.isNotEmpty && messageLocalId != storedLocalId)) {
      return null;
    }
    if (messageLocalId.isEmpty) message.id = storedLocalId;
    final receiver = decoded['receiver']?.toString().trim() ?? '';
    final groupId = decoded['groupID']?.toString().trim() ?? '';
    if ((receiver.isEmpty && groupId.isEmpty) ||
        (receiver.isNotEmpty && groupId.isNotEmpty)) {
      return null;
    }
    final priorityIndex = decoded['priority'] is int
        ? decoded['priority'] as int
        : MessagePriorityEnum.V2TIM_PRIORITY_NORMAL.index;
    final priority =
        priorityIndex >= 0 && priorityIndex < MessagePriorityEnum.values.length
            ? MessagePriorityEnum.values[priorityIndex]
            : MessagePriorityEnum.V2TIM_PRIORITY_NORMAL;
    final pushJson = decoded['offlinePushInfo'];
    return _RecoveredOutgoingEnvelope(
      message: message,
      receiver: receiver,
      groupId: groupId,
      isExcludedFromUnreadCount: decoded['isExcludedFromUnreadCount'] == true,
      priority: priority,
      onlineUserOnly: decoded['onlineUserOnly'] == true,
      needReadReceipt: decoded['needReadReceipt'] == true,
      offlinePushInfo: pushJson is Map
          ? OfflinePushInfo.fromJson(Map<String, dynamic>.from(pushJson))
          : null,
      cloudCustomData: decoded['businessCloudCustomData']?.toString(),
      localCustomData: decoded['localCustomData']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

~~~

