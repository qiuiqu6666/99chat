const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const r=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,100));s=s.replace(a,b);}; fn(r,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
edit('lib/src/services/conversation_local/conversation_draft_service.dart',(r)=>{
 r("import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';",`import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/outgoing_identity_contract.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform_stub.dart'
    if (dart.library.js_interop) 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform_web.dart' as platform;
`);
 r('  const ConversationDraftEdit._(this.identity, this.conversationID,\n      this.editorIdentity, this.revision, this.text);','  ConversationDraftEdit._(this.identity, this.conversationID,\n      this.editorIdentity, this.revision, this.text, [String? persistedId])\n      : draftId = persistedId ?? newOutgoingClientCorrelationId();\n  final String draftId;');
 r('      required this.commitForTest});','      required this.commitForTest, this.draftStoreForTest, this.draftCipherForTest});');
 r('  String Function()? ownerForTest;',`  ImIngressStore? draftStoreForTest;
  OutboxPayloadCipher? draftCipherForTest;
  late final ImIngressStore _draftStore = draftStoreForTest ?? platform.createPlatformImIngressStore();
  bool get _durableDrafts => ownerForTest == null || draftStoreForTest != null;
  OutboxPayloadCipher get _draftCipher => draftCipherForTest ?? OutboxPayloadCipher.instance;
  String Function()? ownerForTest;`);
 r('ConversationDraftEdit._(identity, id, Object(), 0, pendingText);', 'ConversationDraftEdit._(identity, id, Object(), 0, pendingText, pendingText == null ? null : previous?.draftId);');
 r('  bool mirrorRepairPending(ConversationDraftEdit edit) =>',`  Future<ImDraftAcceptance> _protectEdit(ConversationDraftEdit edit, String text) async {
    final protected = await _draftCipher.protect(ownerUserId: edit.identity.ownerUserId, plaintext: text);
    if (protected == null) throw StateError('durable draft encryption unavailable');
    return ImDraftAcceptance(ownerUserId: edit.identity.ownerUserId,
      conversationId: edit.conversationID, draftId: edit.draftId, protectedText: protected.value);
  }

  ImDraftSubmissionContext submissionContext(ConversationDraftEdit edit) => ImDraftSubmissionContext(
    isCurrent: () => isCurrentEdit(edit),
    prepare: () async {
      final draft = await _protectEdit(edit, edit.text ?? '');
      if (isCurrentEdit(edit)) await _draftStore.transaction((tx) => (tx as ImDraftTransaction).saveDraftHead(draft));
      return draft;
    });

  bool mirrorRepairPending(ConversationDraftEdit edit) =>`);
 r('      final int code;\n      if (writeForTest != null)',`      if (_durableDrafts) {
        final edit = expectedEdit ?? ConversationDraftEdit._(identity, id, Object(), 0, text);
        final draft = await _protectEdit(edit, text ?? '');
        if (!current()) return;
        await _draftStore.transaction((tx) => (tx as ImDraftTransaction).saveDraftHead(draft));
        if (!current()) return;
      }
      final int code;
      if (writeForTest != null)`);
 r('    final String? text;\n    if (readForTest != null)',`    if (_durableDrafts) {
      final head = await _draftStore.transaction((tx) => (tx as ImDraftTransaction).findDraftHead(identity.ownerUserId, id));
      if (head != null) {
        if ((expectedEdit != null && !isCurrentEdit(expectedEdit)) ||
            !SessionIdentityService.instance.isCurrent(identity, currentOwnerUserId: _owner)) return null;
        if (head['accepted_operation_id'] != null) return null;
        final saved = await _draftCipher.reveal(ownerUserId: identity.ownerUserId, value: head['protected_text'] as String);
        if (saved == null) throw StateError('durable draft cannot be decrypted');
        return saved.isEmpty ? null : saved;
      }
    }
    final String? text;
    if (readForTest != null)`);
});
edit('lib/src/chat_page/chat_draft_controller.dart',(r)=>{
 r("import 'dart:async';","import 'dart:async';\nimport 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';");
 r('class ChatDraftSubmission {','class ChatDraftSubmission implements ImDurableTextSubmission {\n  @override\n  ImDraftSubmissionContext? durableContext;');
});
edit('lib/src/chat.dart',(r)=>{
 r('    return _draft.captureSubmission(text, persistenceToken: edit);','    return _draft.captureSubmission(text, persistenceToken: edit)\n      ..durableContext = service.submissionContext(edit);');
});
edit('lib/src/services/im/outgoing_send_coordinator.dart',(r)=>{
 r("import 'dart:convert';","import 'dart:convert';\nimport 'outbox_draft_submission.dart';");
 r('    if (persistOutbox) {\n      final main = ImOutboxRecord(',`    final draftContext = recoverPreparedOutbox ? null : ImDraftSubmissionContext.current;
    final draftAcceptance = persistOutbox && draftContext != null ? await draftContext.prepare() : null;
    if (persistOutbox) {
      final main = ImOutboxRecord(`);
 r('            recoveryCopy: recovery,','            recoveryCopy: recovery,\n            draftAcceptance: draftAcceptance,');
 r('      final dispatch = await persistence.recordDispatchIntent(',`      // The two Outbox records and draft ownership are committed together.
      // A UI failure cannot undo durable acceptance or trigger another send.
      if (draftContext != null) {
        try { draftContext.accepted(identity.operationId); } catch (error) {
          debugPrint('draft acceptance projection failed: ' + error.runtimeType.toString());
        }
      }
      final dispatch = await persistence.recordDispatchIntent(`);
});
edit('third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart',(r)=>{
 r("import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';","import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';\nimport 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';");
 r('    repliedMessage = null;\n    final V2TimMsgCreateInfoResult? textMessageInfo =',`    final submissionBoundary = ImDraftSubmissionContext.current;
    if (submissionBoundary == null) {
      repliedMessage = null;
    } else {
      submissionBoundary.onAccepted(() {
        if (identical(_composerUi.repliedMessage, replyTarget)) repliedMessage = null;
      });
    }
    final V2TimMsgCreateInfoResult? textMessageInfo =`);
});
edit('third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart',(r,get,set)=>{
 r("import 'dart:async';","import 'dart:async';\nimport 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';");
 r('  _onEmojiSubmitted() {','  _onEmojiSubmitted() {\n    if (_textAcceptancePending) return;');
 r('  onSubmitted() async {','  onSubmitted() async {\n    if (_textAcceptancePending) return;');
 // Turn eager send Futures into closures so the boundary follows their entire async chain.
 set(get().replace(/(submission,\n\s+)(widget\.model\.send(?:Reply|TextAt|Text)Message\()/g,'$1() => $2'));
 const start=get().indexOf('  Future<V2TimValueCallback<V2TimMessage>?> _observeTextSubmission('),end=get().indexOf('  void _notifySubmissionClear',start);
 set(get().slice(0,start)+`  bool _textAcceptancePending = false;
  Future<V2TimValueCallback<V2TimMessage>?> _observeTextSubmission(
      Object? submission, Future<V2TimValueCallback<V2TimMessage>?> Function() send) {
    final completed = widget.model.lifeCycle?.textDidSubmit;
    final clear = widget.model.lifeCycle?.textDidClearAfterSubmit;
    final boundary = submission is ImDurableTextSubmission ? submission.durableContext : null;
    _textAcceptancePending = true;
    void accepted() {
      _textAcceptancePending = false;
      if (boundary != null && !boundary.isCurrent()) return;
      if (mounted) {
        textEditingController.clear();
        _clearMentionState();
        currentCursor = null;
        lastText = '';
        conversationModel.clearWebDraft(conversationID: widget.conversationID);
      }
      if (clear != null) { clear(submission); }
      else if (mounted) { widget.onChanged?.call(''); }
    }
    final pending = boundary == null ? send() : boundary.run(send, accepted);
    if (boundary == null) accepted();
    return pending.then((result) {
      if (result != null) completed?.call(submission, result);
      return result;
    }).whenComplete(() => _textAcceptancePending = false);
  }

`+get().slice(end));
 r(`      textEditingController.clear();
      // Controller mutations do not invoke TextField.onChanged. Notify the
      // host explicitly so its local draft is cleared at send intent instead
      // of waiting for the asynchronous messageDidSend callback.
      _notifySubmissionClear(submission);`, '      // The captured input is cleared only by the prepared acceptance callback.');
 r(`      textEditingController.clear();
      _notifySubmissionClear(submission);
      currentCursor = null;
      lastText = "";
      _clearMentionState();`, '      // Keep the complete composer until the durable acceptance boundary.');
 // Web clear also belongs to acceptance, not button press.
 set(get().replaceAll('    conversationModel.clearWebDraft(conversationID: widget.conversationID);\n    lastText = "";','    lastText = "";'));
 // Emoji path has the clear after convType instead of before lastText.
 r('    final convType = widget.conversationType;\n    conversationModel.clearWebDraft(conversationID: widget.conversationID);','    final convType = widget.conversationType;');
});
