import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_tips_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_tips_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/tim_uikit_conversation_last_msg.dart';

V2TimMessage _groupCustom({
  required Map<String, dynamic> payload,
  String groupId = 'g_internal',
  String nickName = '阿伦_(现南风在管理)',
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 1700000000,
    'message_msg_id': 'm1',
    'message_is_from_self': false,
    'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
  message.groupID = groupId;
  message.nickName = nickName;
  message.sender = 'user_a';
  message.nameCard = nickName;
  message.customElem = V2TimCustomElem(data: jsonEncode(payload));
  return message;
}

void main() {
  group('buildGroupConversationPreviewLine', () {
    test('merges sender into a single preview line', () {
      expect(
        buildGroupConversationPreviewLine(
          previewText: '[图片]',
          senderName: '京东六合彩自动机器人',
        ),
        '京东六合彩自动机器人: [图片]',
      );
    });

    test('keeps c2c preview without sender prefix', () {
      expect(
        buildGroupConversationPreviewLine(
          previewText: '发了什么',
          senderName: '',
        ),
        '发了什么',
      );
    });

    test('does not prefix drafts', () {
      expect(
        buildGroupConversationPreviewLine(
          previewText: '未发送完的草稿',
          senderName: '张三',
          isDraft: true,
        ),
        '未发送完的草稿',
      );
    });

    test('falls back to sender when preview is empty', () {
      expect(
        buildGroupConversationPreviewLine(
          previewText: '  ',
          senderName: '张三',
        ),
        '张三',
      );
    });
  });

  group('conversationPreviewSenderName gray custom', () {
    test('group_tip custom omits sender on the preview line', () {
      final message = _groupCustom(payload: <String, dynamic>{
        'businessID': 'group_tip',
        'action': 'group_name_changed',
        'opUserId': 'user_a',
        'opUserName': '阿伦_(现南风在管理)1',
      });
      expect(omitsConversationPreviewSender(message), isTrue);
      expect(conversationPreviewSenderName(message), '');
      expect(
        buildGroupConversationPreviewLine(
          previewText: '阿伦_(现南风在管理)1修改了群名称',
          senderName: conversationPreviewSenderName(message),
        ),
        '阿伦_(现南风在管理)1修改了群名称',
      );
    });

    test('group_create custom omits sender', () {
      final message = _groupCustom(payload: <String, dynamic>{
        'businessID': 'group_create',
        'opUser': '阿伦',
        'content': '创建群组',
      });
      expect(omitsConversationPreviewSender(message), isTrue);
      expect(conversationPreviewSenderName(message), '');
    });

    test('live_tip omits sender, live card does not', () {
      final tip = _groupCustom(payload: <String, dynamic>{
        'businessID': 'live_tip',
        'memo': '主播打赏了10金币',
      });
      final card = _groupCustom(payload: <String, dynamic>{
        'businessID': 'group_live_started',
        'roomName': '内部群直播',
      });
      expect(omitsConversationPreviewSender(tip), isTrue);
      expect(conversationPreviewSenderName(tip), '');
      expect(omitsConversationPreviewSender(card), isFalse);
    });

    test('red packet claim notice omits sender', () {
      final message = _groupCustom(payload: <String, dynamic>{
        'businessID': 'red_packet_claim_notice',
        'claimerUserId': 'user_b',
        'claimerName': '乙',
        'packetId': 'p1',
      });
      expect(omitsConversationPreviewSender(message), isTrue);
      expect(conversationPreviewSenderName(message), '');
    });

    test('friend became friends omits sender', () {
      final message = _groupCustom(payload: <String, dynamic>{
        'businessID': 'friend_became_friends',
        'text': '你们已成为好友，现在可以开始聊天了',
      });
      expect(omitsConversationPreviewSender(message), isTrue);
    });

    test('native group tips omit sender', () {
      final message = V2TimMessage.fromJson(<String, dynamic>{
        'message_server_time': 1700000000,
        'message_msg_id': 'tips1',
        'message_is_from_self': false,
        'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        'message_custom_str': '',
        'message_risk_type_identified': 0,
        'message_sender_group_member_info': <String, dynamic>{},
        'message_group_at_user_array': <String>[],
      });
      message.elemType = MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS;
      message.groupID = 'g_internal';
      message.nickName = '阿伦_(现南风在管理)';
      message.groupTipsElem = V2TimGroupTipsElem(
        groupID: 'g_internal',
        type: 1,
        opMember: V2TimGroupMemberInfo(userID: 'user_a'),
      );
      expect(omitsConversationPreviewSender(message), isTrue);
      expect(conversationPreviewSenderName(message), '');
    });
  });
}
