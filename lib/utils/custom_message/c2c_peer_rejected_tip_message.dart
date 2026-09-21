import 'dart:convert';

import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';

const String kC2cPeerRejectedBusinessID = 'c2c_peer_rejected';

String c2cPeerRejectedTipLocalId(String clientId) =>
    'peer-rejected:${clientId.trim()}';

Map<String, dynamic>? _peerRejectedPayload(V2TimCustomElem? customElem) {
  final raw = customElem?.data;
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['businessID']?.toString() != kC2cPeerRejectedBusinessID) {
      return null;
    }
    return map;
  } catch (_) {
    return null;
  }
}

String getC2cPeerRejectedTipDisplayText(V2TimCustomElem? customElem) {
  final payload = _peerRejectedPayload(customElem);
  if (payload == null) {
    return '';
  }
  final text = payload['text']?.toString().trim() ?? '';
  if (text.isNotEmpty) {
    return text;
  }
  return ErrorMessageConverter.getErrorMessage(20007);
}

bool isC2cPeerRejectedTipMessage(V2TimMessage message) {
  if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_CUSTOM) {
    return false;
  }
  return _peerRejectedPayload(message.customElem) != null;
}

V2TimMessage buildC2cPeerRejectedTipMessage({String? clientId}) {
  final trimmedClientId = clientId?.trim() ?? '';
  final localId = trimmedClientId.isNotEmpty
      ? c2cPeerRejectedTipLocalId(trimmedClientId)
      : 'peer-rejected:${DateTime.now().microsecondsSinceEpoch}';
  return V2TimMessage(
    id: localId,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
    customElem: V2TimCustomElem(
      data: jsonEncode(<String, dynamic>{
        'businessID': kC2cPeerRejectedBusinessID,
        'text': ErrorMessageConverter.getErrorMessage(20007),
      }),
    ),
    isSelf: true,
  )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
}
