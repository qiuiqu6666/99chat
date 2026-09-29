const fs=require('fs');const p='third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart';let s=fs.readFileSync(p,'utf8');
let a=s.indexOf('  Future<V2TimValueCallback<V2TimMessage>> _sendMessage('),b=s.indexOf('\n  ',a+5); // scope by following coordinator call below
let prefix=s.slice(0,a),tail=s.slice(a);
tail=tail.replace('    bool preserveTargetGroupID = false,','    bool preserveTargetGroupID = false,\n    String? retryOfSdkLocalId,\n    VoidCallback? onDispatchGranted,');
tail=tail.replace('    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(', '    var retryDispatched = false;\n    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(');
tail=tail.replace('      messageService: _messageService,','      messageService: _messageService,\n      retryOfSdkLocalId: retryOfSdkLocalId,\n      onDispatchGranted: () { retryDispatched = true; onDispatchGranted?.call(); },');
tail=tail.replace('    var sendMsgRes = coordinatedSend.sdkResult;','    var sendMsgRes = coordinatedSend.sdkResult;\n    if (retryOfSdkLocalId != null && !retryDispatched) return sendMsgRes;');
s=prefix+tail;
a=s.indexOf('  Future<V2TimValueCallback<V2TimMessage>?> _performFailedMessageResend('); b=s.indexOf('\n  Future<',a+1);let c=s.slice(a,b);
const begin=c.indexOf('    _removeOutgoingMessage('),end=c.indexOf('    return _sendMessage(',begin);
c=c.slice(0,begin)+`    final outgoing = tools.setUserInfoForMessage(recreatedMessage, recreatedId);
    applyOutgoingStableIdToMessage(outgoing, recreatedId);
`+c.slice(end);
c=c.replace('      id: recreatedId,',`      id: recreatedId,
      retryOfSdkLocalId: clientId,
      onDispatchGranted: () {
        _removeOutgoingMessage(convID: convID, clientId: clientId.isEmpty ? null : clientId,
          msgID: msgID.isEmpty ? null : msgID);
        outgoing.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        addSendingMessageID(recreatedId);
        _prependOutgoingMessageForConversation(convID, outgoing, skipEnterAnimation: true);
        if (msgID.isNotEmpty) unawaited(_messageService.deleteMessageFromLocalStorage(
          msgID: msgID, webMessageInstance: message.messageFromWeb).catchError((Object _) => null));
      },`);
s=s.slice(0,a)+c+s.slice(b);fs.writeFileSync(p,s);
