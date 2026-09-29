import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';

class ProjectionTrap extends TUIChatGlobalModel {
  @override
  List<V2TimMessage>? getMessageList(String conversationID) =>
      throw StateError('feed must not build a chat projection');
}

class _BootstrapSdk extends MessageService {
  var localRelease = Completer<void>();
  var cloudRelease = Completer<void>();
  int localCalls = 0;
  int cloudCalls = 0;
  bool emptyCloud = false;

  void reset() {
    localRelease = Completer<void>();
    cloudRelease = Completer<void>();
    localCalls = 0;
    cloudCalls = 0;
    emptyCloud = false;
  }

  bool _isCloud(HistoryMsgGetTypeEnum type) {
    return type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG ||
        type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG;
  }

  Future<V2TimMessageListResult> _read(HistoryMsgGetTypeEnum type) async {
    if (_isCloud(type)) {
      cloudCalls++;
      await cloudRelease.future;
    } else {
      localCalls++;
      await localRelease.future;
    }
    return V2TimMessageListResult(
      isFinished: false,
      messageList: _isCloud(type) && emptyCloud
          ? []
          : List<V2TimMessage>.generate(
              20,
              (index) => V2TimMessage.fromJson({
                'message_msg_id': 'bootstrap_${index + 1}',
                'message_server_time': index + 1,
                'message_status': 2,
                'message_risk_type_identified': 0,
              })
                ..elemType = 1,
            ),
    );
  }

  @override
  Future<V2TimMessageListResult?> getHistoryMessageListWithComplete({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    return _read(getType);
  }

  @override
  Future<MessageHistorySdkResult> getHistoryMessageListWithStatus({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    return MessageHistorySdkResult(
      code: 0,
      desc: 'bootstrap test',
      data: await _read(getType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

Future<void> _waitFor(String label, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $label');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sdk = _BootstrapSdk();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(sdk);
  });
  setUp(() async {
    sdk.reset();
    SessionIdentityService.instance.invalidate();
    ChatHistoryPeekBootstrap.clearSession();
    ChatViewportCollection.instance.resetForTest();
    await ApiClient.instance
        .saveToken('fixture-token', userId: 'bootstrap-owner');
  });
  tearDown(() async {
    ChatHistoryPeekBootstrap.clearSession();
    await ApiClient.instance.clearToken();
  });

  test(
      'thousands of cold feed previews do not create history buckets or projections',
      () {
    final model = ProjectionTrap();
    final before = model.messageListMap.length;
    for (var i = 0; i < 3000; i++) {
      expect(
          ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
            globalModel: model,
            conversation: V2TimConversation(
                conversationID: 'c2c_cold$i', userID: 'cold$i', type: 1),
          ),
          isNull);
    }
    expect(model.messageListMap.length, before);
    model.dispose();
  });

  test('missing older-history hint stays unknown instead of becoming exhausted',
      () {
    final model = TUIChatSeparateViewModel()
      ..conversationID = 'c2c_unknown_history';
    model.haveMoreData = true;
    model.syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
    expect(model.historyAvailability, HistoryAvailability.unknown);
    model.syncHaveMoreDataFromCachedHistory(mayHaveOlder: true);
    expect(model.historyAvailability, HistoryAvailability.available);
    model.dispose();
  });

  test('warm thin local window releases repeated entries without an SDK read',
      () async {
    final model = ProjectionTrap();
    final message = V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
      'message_msg_id': 'newest',
      'message_server_time': 10
    })
      ..elemType = 1;
    const key = 'c2c_bootstrap_thin';
    model.setMessageList(key, [message],
        replace: true, needResetNewMessageCount: false);
    model.markLocalInitialHistoryVisible(key);
    var commits = 0;
    final conversation = V2TimConversation(
        conversationID: key,
        userID: 'bootstrap_thin',
        type: 1,
        lastMessage: message);
    for (var i = 0; i < 3; i++) {
      expect(
          await ChatHistoryPeekBootstrap.apply(
              conversation: conversation,
              globalModel: model,
              allowCloudVerification: false,
              onFirstWindowCommitted: () => commits++),
          isTrue);
    }
    expect(commits, 3);
    expect(
        ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
                globalModel: model, conversation: conversation)
            ?.msgID,
        'newest');
    model.removeMessageList(key);
    await Future<void>.delayed(Duration.zero);
    model.dispose();
  });

  test('cloud bootstrap waits for an in-flight local open handoff', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_shared',
      userID: 'bootstrap_shared',
      type: 1,
    );
    addTearDown(() async {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });

    final local = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      allowCloudVerification: false,
    );
    await _waitFor('local SDK flight', () => sdk.localCalls == 1);
    expect(sdk.localCalls, 1);

    final cloud = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);

    sdk.localRelease.complete();
    await local;
    await Future<void>.delayed(Duration.zero);
    expect(sdk.localCalls, 1);
    await _waitFor('cloud SDK flight', () => sdk.cloudCalls == 1);
    expect(sdk.cloudCalls, 1);
    sdk.cloudRelease.complete();
    expect(await cloud, isTrue);
  });

  test('clearing bootstrap rejects a late local result before cloud starts',
      () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    var clearEpoch = 0;
    ArchiveHistoryProvider.registerHistoryClearedAtResolver(
      (_) async => clearEpoch,
    );
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_clear',
      userID: 'bootstrap_clear',
      type: 1,
    );
    addTearDown(() async {
      ChatHistoryPeekBootstrap.clearSession();
      ArchiveHistoryProvider.registerHistoryClearedAtResolver(null);
      model.dispose();
    });

    final local = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      allowCloudVerification: false,
    );
    await _waitFor('clear test local SDK flight', () => sdk.localCalls == 1);
    final cloud = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
    );
    clearEpoch = 1;
    sdk.localRelease.complete();

    expect(await local, isFalse);
    expect(await cloud, isFalse);
    expect(sdk.cloudCalls, 0);
    expect(model.rawMessageList(conversation.conversationID), isNull);
  });

  test('re-entering cloud verification shares the same SDK flight', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_reentry',
      userID: 'bootstrap_reentry',
      type: 1,
    );
    addTearDown(() async {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });

    final first = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
    );
    await _waitFor('reentry local SDK flight', () => sdk.localCalls == 1);
    final reentry = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);
    sdk.localRelease.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sdk.localCalls, 1);
    await _waitFor('cloud SDK flight', () => sdk.cloudCalls == 1);
    expect(sdk.cloudCalls, 1);
    sdk.cloudRelease.complete();
    expect(await first, isTrue);
    expect(await reentry, isTrue);
  });

  test('local-only entry joins a cloud-first local phase', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_reverse',
      userID: 'bootstrap_reverse',
      type: 1,
    );
    addTearDown(() async {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });

    final cloud = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
    );
    await _waitFor('reverse cloud local SDK flight', () => sdk.localCalls == 1);
    final local = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      allowCloudVerification: false,
    );
    sdk.localRelease.complete();

    expect(await local, isTrue);
    expect(sdk.localCalls, 1);
    await _waitFor('cloud SDK flight', () => sdk.cloudCalls == 1);
    expect(sdk.cloudCalls, 1);
    sdk.cloudRelease.complete();
    expect(await cloud, isTrue);
  });

  test('evicting a completed local phase reloads it while cloud stays singleflight',
      () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = '@TGS#_mc2SX4NMM62CZ';
    final conversation = V2TimConversation(
        conversationID: 'group_$key', groupID: key, type: 2,
        groupType: 'Community');
    addTearDown(() {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });
    sdk.localRelease.complete();
    final cloud = ChatHistoryPeekBootstrap.apply(
        conversation: conversation, globalModel: model,
        retryDelays: const [Duration.zero]);
    await _waitFor('cloud holding a completed local phase',
        () => sdk.cloudCalls == 1);
    expect(model.rawMessageCount(key), 20);
    model.removeMessageList(key);
    expect(model.hasInitialHistoryLoaded(key), isFalse);
    expect(model.rawMessageList(key), isNull);
    try {
      expect(await ChatHistoryPeekBootstrap.apply(
          conversation: conversation, globalModel: model,
          allowCloudVerification: false), isTrue);
      expect(sdk.localCalls, 2,
          reason: 'evicted data cannot be supplied by a completed handoff');
      expect(model.rawMessageCount(key), 20);
      expect(model.hasInitialHistoryLoaded(key), isTrue);
      expect(sdk.cloudCalls, 1);
    } finally {
      sdk.cloudRelease.complete();
      await cloud;
    }
  });

  test('explicit reentry resumes a cancelled delayed verifier without duplication',
      () async {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    coordinator.invalidate();
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = '@TGS#_mcReentry123';
    final conversation = V2TimConversation(
        conversationID: 'group_$key', groupID: key, type: 2,
        groupType: 'Community');
    addTearDown(() {
      coordinator.invalidate();
      model.dispose();
    });
    final first = coordinator.verifyAfterFirstFrame(
        conversation: conversation, delay: const Duration(milliseconds: 20));
    coordinator.cancelConversation(key);
    final reentry = coordinator.verifyAfterFirstFrame(
        conversation: conversation, delay: Duration.zero);
    expect(identical(first, reentry), isTrue);
    sdk.localRelease.complete();
    await _waitFor('resumed shared cloud SDK flight', () => sdk.cloudCalls == 1);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 1);
    sdk.cloudRelease.complete();
    final outcome = await reentry;
    await first;
    expect(outcome, isNot(ConversationHistorySyncOutcome.stale),
        reason: 'a live reentry must not consume the cancelled route outcome');
    expect(sdk.localCalls, 1);
    // The fixture has no online network provider/continuity proof. The shared
    // task retains its three bounded tries and the offline recovery outcome.
    expect(outcome, ConversationHistorySyncOutcome.offline);
    expect(sdk.cloudCalls, 3);
    expect(model.rawMessageCount(key), 20);
  });

  test('bound reentry replaces the abandoned generation verifier',
      () async {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    coordinator.invalidate();
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = '@TGS#_mcReentry123';
    final conversation = V2TimConversation(
        conversationID: 'group_$key', groupID: key, type: 2,
        groupType: 'Community');
    addTearDown(() {
      coordinator.invalidate();
      model.dispose();
    });
    final collection = ChatViewportCollection.instance;
    collection.attach(conversationKey: key,
        identity: SessionIdentityService.instance.capture());
    final oldGeneration = collection.openGeneration;
    final first = coordinator.verifyAfterFirstFrame(
        conversation: conversation, boundOpenGeneration: oldGeneration,
        delay: const Duration(milliseconds: 20));
    collection.detachUi(conversationKey: key, openGeneration: oldGeneration);
    coordinator.cancelConversation(key);
    collection.attach(conversationKey: key,
        identity: SessionIdentityService.instance.capture());
    expect(collection.openGeneration, isNot(oldGeneration));
    final reentry = coordinator.verifyAfterFirstFrame(
        conversation: conversation, boundOpenGeneration: collection.openGeneration,
        delay: Duration.zero);

    sdk.localRelease.complete();
    await _waitFor('resumed shared cloud SDK flight', () => sdk.cloudCalls == 1);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 1);
    sdk.cloudRelease.complete();
    final outcome = await reentry;
    expect(await first, ConversationHistorySyncOutcome.stale);
    expect(outcome, isNot(ConversationHistorySyncOutcome.stale),
        reason: 'a live reentry must not consume the cancelled route outcome');
    expect(sdk.localCalls, 1);
    // The fixture has no online network provider/continuity proof. The shared
    // task retains its three bounded tries and the offline recovery outcome.
    expect(outcome, ConversationHistorySyncOutcome.offline);
    expect(sdk.cloudCalls, 3);
    expect(model.rawMessageCount(key), 20);
  });

  test('reentering an evicted Community loads SDK despite old durable arrivals',
      () async {
    final directory = await Directory.systemTemp.createTemp('bootstrap-visit-');
    final store = HistoryWindowStore(
        debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = '@TGS#_mcReopen321';
    final conversation = V2TimConversation(
        conversationID: 'group_$key', groupID: key, type: 2,
        groupType: 'Community');
    addTearDown(() async {
      ChatHistoryPeekBootstrap.clearSession();
      model.clearCurrentConversation();
      model.dispose();
      HistoryWindowRepositoryProvider.repository = null;
      await store.closeIfOpen();
      await directory.delete(recursive: true);
    });
    model.setCurrentConversation(CurrentConversation(key, ConvType.group));
    model.setMessageListPosition(key, HistoryMessagePosition.notShowLatest,
        notify: false);
    await model.applyAppRealtimeMessage(V2TimMessage.fromJson({
      'message_msg_id': 'pending-after-old-page',
      'message_server_time': 99,
      'message_risk_type_identified': 0,
    })..groupID = key..isSelf = false..elemType = 1,
        ingressEventID: 'visit-entry-event', ingressSequence: 99);
    expect(model.hasDurableHistoryDeferred(key), isTrue);
    model.clearCurrentConversation();
    model.setCurrentConversation(CurrentConversation(key, ConvType.group));
    final baseline = model.beginHistoryUnreadVisit(key);
    model.removeMessageList(key);
    model.setMessageListPosition(key, HistoryMessagePosition.bottom,
        notify: false);
    await baseline;
    sdk.localRelease.complete();
    expect(await ChatHistoryPeekBootstrap.apply(
        conversation: conversation, globalModel: model,
        allowCloudVerification: false), isTrue);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);
    expect(model.rawMessageCount(key), 20);
    expect(model.getMessageListPosition(key), HistoryMessagePosition.bottom);
    // Loading an older local SDK page is not proof of consuming the newer
    // durable boundary. Restoring the viewport must never drop that arrival.
    expect(model.hasDurableHistoryDeferred(key), isTrue);
    expect((await store.deferredState(model.historyWindowScopeFor(key)!))
        .receivedCount, 1);
  });

  test('session clear during first-paint delay prevents the cloud request',
      () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    addTearDown(model.dispose);
    final firstPaint = Completer<void>();
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    final task = ChatHistoryPeekBootstrap.apply(
      conversation: V2TimConversation(
          conversationID: 'c2c_delay_clear', userID: 'delay_clear', type: 1),
      globalModel: model,
      retryDelays: const [Duration.zero],
      onFirstWindowCommitted: () {
        if (!firstPaint.isCompleted) firstPaint.complete();
      },
    );
    await firstPaint.future;
    ChatHistoryPeekBootstrap.clearSession();
    expect(await task, isFalse);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);
  });

  test('cloud backoff releases its phase so a local-only entry can finish',
      () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    addTearDown(model.dispose);
    final conversation = V2TimConversation(
        conversationID: 'c2c_empty_backoff', userID: 'empty_backoff', type: 1);
    sdk.emptyCloud = true;
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    Future<bool> cloud() => ChatHistoryPeekBootstrap.apply(
        conversation: conversation,
        globalModel: model,
        retryDelays: const [Duration.zero]);
    expect(await cloud(), isFalse);
    expect(ChatHistoryPeekBootstrap.isCloudRetryDeferred(conversation, model),
        isTrue);
    expect(await cloud(), isFalse);
    expect(
        await ChatHistoryPeekBootstrap.apply(
                conversation: conversation,
                globalModel: model,
                allowCloudVerification: false)
            .timeout(const Duration(seconds: 1)),
        isTrue);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 1);
  });

  test('cloud verify after a loaded local window does not re-read LOCAL',
      () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_no_dup_local',
      userID: 'bootstrap_no_dup_local',
      type: 1,
    );
    addTearDown(() {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    expect(
        await ChatHistoryPeekBootstrap.apply(
            conversation: conversation,
            globalModel: model,
            allowCloudVerification: false),
        isTrue);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);
    expect(
        await ChatHistoryPeekBootstrap.apply(
            conversation: conversation,
            globalModel: model,
            retryDelays: const <Duration>[Duration.zero],
            allowCloudVerification: true),
        isTrue);
    expect(sdk.localCalls, 1,
        reason: 'cloud verify must not replay the same LOCAL bootstrap');
    expect(sdk.cloudCalls, 1);
  });

  test('empty-window cloud apply still performs a first LOCAL read', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    final conversation = V2TimConversation(
      conversationID: 'c2c_bootstrap_empty_needs_local',
      userID: 'bootstrap_empty_needs_local',
      type: 1,
    );
    addTearDown(() {
      ChatHistoryPeekBootstrap.clearSession();
      model.dispose();
    });
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    expect(
        await ChatHistoryPeekBootstrap.apply(
            conversation: conversation,
            globalModel: model,
            retryDelays: const <Duration>[Duration.zero],
            allowCloudVerification: true),
        isTrue);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 1);
  });

  test('bound cloud apply abandons after detach without writing', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = 'c2c_bootstrap_abandon';
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'bootstrap_abandon',
      type: 1,
    );
    addTearDown(() {
      ChatHistoryPeekBootstrap.clearSession();
      ChatViewportCollection.instance.resetForTest();
      model.dispose();
    });
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: SessionIdentityService.instance.capture(),
    );
    final gen = collection.openGeneration;
    var commits = 0;
    final task = ChatHistoryPeekBootstrap.apply(
      conversation: conversation,
      globalModel: model,
      retryDelays: const <Duration>[Duration.zero],
      allowCloudVerification: true,
      boundOpenGeneration: gen,
      onFirstWindowCommitted: () => commits++,
    );
    await _waitFor('bound local SDK flight', () => sdk.localCalls == 1);
    collection.detachUi(conversationKey: key, openGeneration: gen);
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    expect(await task, isFalse);
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, 0);
    expect(commits, 0);
    expect(model.rawMessageList(key), isNull);
  });

  test('unbound apply is not fenced by detachUi', () async {
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = 'c2c_bootstrap_unbound';
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'bootstrap_unbound',
      type: 1,
    );
    addTearDown(() {
      ChatHistoryPeekBootstrap.clearSession();
      ChatViewportCollection.instance.resetForTest();
      model.dispose();
    });
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: SessionIdentityService.instance.capture(),
    );
    collection.detachUi(
      conversationKey: key,
      openGeneration: collection.openGeneration,
    );
    sdk.localRelease.complete();
    expect(
        await ChatHistoryPeekBootstrap.apply(
            conversation: conversation,
            globalModel: model,
            allowCloudVerification: false),
        isTrue);
    expect(sdk.localCalls, 1);
    expect(model.rawMessageCount(key), 20);
  });

  test('repairOpenViewport is stale after detach and does not write', () async {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    coordinator.invalidate();
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = 'c2c_bootstrap_h0_abandon';
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'bootstrap_h0_abandon',
      type: 1,
    );
    addTearDown(() {
      coordinator.invalidate();
      ChatViewportCollection.instance.resetForTest();
      model.dispose();
    });
    final identity = SessionIdentityService.instance.capture();
    final collection = ChatViewportCollection.instance;
    collection.attach(conversationKey: key, identity: identity);
    final ticket = ChatViewportRepairTicket(
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
      conversationKey: key,
      openGeneration: collection.openGeneration,
    );
    final task = coordinator.repairOpenViewport(
      conversation: conversation,
      ticket: ticket,
    );
    await _waitFor('h0 local SDK flight', () => sdk.localCalls == 1);
    collection.detachUi(
      conversationKey: key,
      openGeneration: ticket.openGeneration,
    );
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    expect(await task, ConversationHistorySyncOutcome.stale);
    expect(sdk.cloudCalls, 0);
    expect(model.rawMessageList(key), isNull);
  });

  test('attached verifyAfterFirstFrame still performs cloud apply', () async {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    coordinator.invalidate();
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = 'c2c_bootstrap_live_verify';
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'bootstrap_live_verify',
      type: 1,
    );
    addTearDown(() {
      coordinator.invalidate();
      ChatViewportCollection.instance.resetForTest();
      model.dispose();
    });
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: SessionIdentityService.instance.capture(),
    );
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    final outcome = await coordinator.verifyAfterFirstFrame(
      conversation: conversation,
      delay: Duration.zero,
      boundOpenGeneration: collection.openGeneration,
    );
    expect(outcome, isNot(ConversationHistorySyncOutcome.stale));
    expect(sdk.localCalls, 1);
    expect(sdk.cloudCalls, greaterThanOrEqualTo(1));
    expect(model.rawMessageCount(key), 20);
  });
  test('new preview bypasses exhausted old window', () async {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    coordinator.invalidate();
    final model = TUIChatGlobalModel();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(model);
    model.configureMessageWriterScope(
        ownerUserID: 'bootstrap-owner',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    const key = 'c2c_bootstrap_fresh_preview';
    final old = V2TimMessage.fromJson({
      'message_msg_id': 'old', 'message_server_time': 1,
      'message_status': 2, 'message_risk_type_identified': 0,
    })..elemType = 1;
    model.setMessageList(key, [old], replace: true, needResetNewMessageCount: false);
    model.markLocalInitialHistoryVisible(key);
    model.markInitialHistoryMayHaveOlder(key, mayHaveOlder: false);
    final latest = V2TimMessage.fromJson({
      'message_msg_id': 'bootstrap_20', 'message_server_time': 20,
      'message_status': 2, 'message_risk_type_identified': 0,
    })..elemType = 1;
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'bootstrap_fresh_preview',
      lastMessage: latest,
      type: 1,
    );
    addTearDown(() {
      coordinator.invalidate();
      ChatViewportCollection.instance.resetForTest();
      model.dispose();
    });
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: SessionIdentityService.instance.capture(),
    );
    sdk.localRelease.complete();
    sdk.cloudRelease.complete();
    final outcome = await coordinator.verifyAfterFirstFrame(
      conversation: conversation,
      delay: Duration.zero,
      boundOpenGeneration: collection.openGeneration,
    );
    expect(outcome, isNot(ConversationHistorySyncOutcome.stale));
    expect(sdk.cloudCalls, greaterThanOrEqualTo(1));
    expect(model.rawMessageList(key)!.any((row) => row.msgID == 'bootstrap_20'), isTrue);
  });
}
