const fs=require('fs');
const path=require('path');
const root='artifacts/chat-evidence-ab-2026-09-25';
const readJson=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const cfg=readJson(root+'/source-selection.json');
const ix=readJson(root+'/symbol-index.json');
function select(p,names){const e=cfg.find(x=>x.path===p); const matches=ix.filter(x=>x.path===p && names.some(n=>x.selector===n || x.selector.endsWith('.'+n))); e.selectors=[...new Set(matches.map(x=>x.selector))];for(const n of names)if(!matches.some(x=>x.selector===n||x.selector.endsWith('.'+n)))throw Error('selector missing '+p+' '+n);}
select('lib/src/chat.dart',['_draft','_draftWrites','_loadChatLocalDraft','_persistChatLocalDraftText','_onChatDraftTextChanged','_persistChatLocalDraft','_clearChatLocalDraftAfterSend','_beginChatOpenGeneration','_isChatOpenGenerationCurrent','_scheduleReconnectHistoryRecovery','_seedCachedHistoryOnOpen','_isOpenHistoryWarm','_conversationLooksEmptyForOpen','_ensureEmptyConversationReadyForOpen','_startOpenHistoryGate','_runOpenHistoryGateWithTipsMerge','_waitOpenHistoryLayoutReady','_prepareOpenHistoryGate','_ensureGroupLocalTipsMergedOnOpen','_wrapChatWithOpenHistoryGate','_reloadChatHistoryIfEmpty','_markChatOpenHistoryReady','_scheduleDeferredHistoryVerification','_runDeferredHistoryVerification','_performDeferredHistoryVerification','_schedulePostOpenTasks','initState','deactivate','dispose','didUpdateWidget']);
select('lib/src/conversation.dart',['_handleOnConvItemTaped','_warmConversationOnPress','_scheduleViewportWarmAfterSettle','_runViewportWarmNow']);
select('third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart',['ensureOpenHydrate','awaitOpenHydrateInFlight','hasOpenHydrateInFlight','openHydrateResultFor','publishOpenHydrateResult','_findOpenHydrateInFlight','clearOpenHydrateResult','applyOutgoingSendResult','updateMessage','markOutgoingSendFailedByIdentity','_sendMessage','bindOutgoingSyncMsgId','messageStatusInConversation','markOutgoingGuardDropped','abandonOutcomeUnknownMessage','_findMessageIndexForUpdate']);
select('third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart',['initForEachConversation','loadChatRecord','_sendMessage','sendTextMessage','sendTextAtMessage','reSendFailMessage','_performFailedMessageResend','_currentResendMessage','_prependOptimisticTextPlaceholder','_adoptOptimisticOutgoingTextMessage','_markOutgoingMediaSendFailed']);
select('lib/src/services/conversation_local/conversation_local_store.dart',['_createConversationTable','_createCoordinatorStateTable','commitCoordinatorPlan','updateLocalDraft','clearLocalDraft','localDraftTextFor']);
select('lib/src/services/conversation_local/conversation_mutation_shadow_bridge.dart',['prepareLocalIntentCommit','prepareFieldPatchCommit','restoreDurableConversationState']);
select('lib/src/services/im/im_ingress_store.dart',['ConversationLocalImIngressStore','_SqliteImIngressTransaction.findOutbox','_SqliteImIngressTransaction.findOutboxRecovery','_SqliteImIngressTransaction.updateOutboxIfCurrent','_SqliteImIngressTransaction.updateOutboxRecoveryIfCurrent']);
select('third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart',['_onEmojiSubmitted','onSubmitted','handleSetDraftText','_setProgrammaticText','controllerHandler']);
select('third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart',['_scheduleMessagesFirstVisibleAfterReveal','_HeadMessageLayoutReporter','_HeadMessageLayoutReporterState']);
cfg.find(x=>x.path.endsWith('chat_open_lifecycle.dart')).selectors=['@file'];
cfg.find(x=>x.path.endsWith('conversation_history_sync_coordinator.dart')).selectors=['@file'];
const additions=[
['A','lib/src/services/conversation_peek_service.dart',['@file']],
['A','lib/src/services/perf_timeline.dart',['@file']],
['A','lib/src/services/conversation_unread_clear_service.dart',['ConversationUnreadClearService.clearLocalForOpenFast','ConversationUnreadClearService._persistOpenReadIntentAndDispatch']],
['A','lib/utils/chat_image_message_prefetch.dart',['ChatImageMessagePrefetch.prepareFirstWindowMedia','ChatImageMessagePrefetch.warmWithBudget','ChatImageMessagePrefetch._selectInitialMediaMessages','ChatImageMessagePrefetch.initialMediaBudget','ChatImageMessagePrefetch.initialLocalMediaBudget','ChatImageMessagePrefetch.initialMediaUrlBudget']],
['A','third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart',[]],
['B','lib/src/services/im/message_core_store.dart',['@file']],
['B','lib/src/utils/c2c_blocked_outgoing_message_sync.dart',['@file']],
['B','lib/src/services/conversation_local/conversation_sync_service.dart',['ConversationSyncService._adoptProviderOutgoingMessage','ConversationSyncService._handleMessageIngress','ConversationSyncService._handleSdkRealtimeMessage']],
['B','lib/src/services/im/outgoing_outbox_recovery_service.dart',['@file']],
];
for(const [group,p,selectors] of additions)if(!cfg.some(x=>x.path===p))cfg.push({group,path:p,selectors});
// Keep the provider and UIKit entry methods added during the final evidence pass.
for(const [p,names] of [
 ['third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart',['TUIChatGlobalModel.applyAppRealtimeMessage','TUIChatGlobalModel._onReceiveNewMsg','TUIChatGlobalModel.completeHistoryReconciliation']],
 ['third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart',['_TUIChatState.initState','_TUIChatState.didUpdateWidget','TIMUIKitChatProviderScope._loadData']],
 ['lib/src/services/conversation_local/conversation_sync_service.dart',['ConversationSyncService._providerOutgoingIdentity']],
]) {
 const entry=cfg.find(x=>x.path===p);
 for(const name of names)if(!ix.some(x=>x.path===p&&x.selector===name))throw Error('selector missing '+p+' '+name);
 entry.selectors=[...new Set([...entry.selectors,...names])];
}
fs.writeFileSync(root+'/source-selection.json',JSON.stringify(cfg,null,2));
