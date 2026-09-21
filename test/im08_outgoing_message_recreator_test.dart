import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_message_recreator.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_face_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_location_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_merger_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

void main() {
  test('recreates every supported outgoing element through an SDK create API',
      () async {
    final service = _RecordingMessageService();
    final cases = <(V2TimMessage, String)>[
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_TEXT)
          ..textElem = V2TimTextElem(text: 'plain'),
        'text',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_TEXT)
          ..textElem = V2TimTextElem(text: '@alice')
          ..groupAtUserList = const <String>['alice'],
        'textAt',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_CUSTOM)
          ..customElem = V2TimCustomElem(data: '{}'),
        'custom',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_FACE)
          ..faceElem = V2TimFaceElem(index: 1, data: 'face'),
        'face',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_IMAGE)
          ..imageElem = V2TimImageElem(path: 'C:/staged/a.jpg'),
        'image',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_VIDEO)
          ..videoElem = V2TimVideoElem(
            videoPath: 'C:/staged/a.mp4',
            snapshotPath: 'C:/staged/a.jpg',
            duration: 3,
          ),
        'video',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_SOUND)
          ..soundElem = V2TimSoundElem(path: 'C:/staged/a.m4a', duration: 2),
        'sound',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_FILE)
          ..fileElem = V2TimFileElem(
            path: 'C:/staged/a.pdf',
            fileName: 'a.pdf',
          ),
        'file',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_LOCATION)
          ..locationElem = V2TimLocationElem(
            desc: 'here',
            longitude: 1,
            latitude: 2,
          ),
        'location',
      ),
      (
        _message(MessageElemType.V2TIM_ELEM_TYPE_MERGER)
          ..mergerElem = V2TimMergerElem(
            title: 'merged',
            abstractList: const <String>['one'],
            compatibleText: 'unsupported',
            messageList: <V2TimMessage>[
              _message(MessageElemType.V2TIM_ELEM_TYPE_TEXT)
                ..msgID = 'server-1',
            ],
          ),
        'merger',
      ),
      (_message(MessageElemType.V2TIM_ELEM_TYPE_NONE), 'forward'),
    ];

    for (final entry in cases) {
      service.lastCall = '';
      final created = await recreateOutgoingMessage(service, entry.$1);
      expect(created?.id, isNotEmpty, reason: entry.$2);
      expect(service.lastCall, entry.$2);
    }
  });

  test('normal staging keeps one SDK local id and only recovery recreates',
      () {
    final coordinator = File(
      'lib/src/services/im/outgoing_send_coordinator.dart',
    ).readAsStringSync();
    final recovery = File(
      'lib/src/services/im/outgoing_outbox_recovery_service.dart',
    ).readAsStringSync();
    expect(coordinator, contains('final sendLocalId = localId'));
    expect(coordinator, contains('_cloneMessageForOutbox(fallbackMessage)'));
    expect(coordinator, contains('message: outboxMessage'));
    expect(coordinator, isNot(contains('recreateOutgoingMessage(')));
    expect(coordinator, contains('sdkLocalId: sendLocalId'));
    expect(recovery, contains('recreateOutgoingMessage('));
    expect(recovery, contains('operationIdOverride: row.operationId'));
    expect(
      recovery,
      contains('clientCorrelationIdOverride: row.clientCorrelationId'),
    );
  });

  test('text-at recreation keeps occurrence cloudCustomData', () async {
    final service = _RecordingMessageService();
    const cloud =
        '{"groupMentionOccurrences":{"v":1,"items":[]},"messageReply":{"messageID":"m1"}}';
    final original = _message(MessageElemType.V2TIM_ELEM_TYPE_TEXT)
      ..textElem = V2TimTextElem(text: '@alice')
      ..groupAtUserList = const <String>['alice']
      ..cloudCustomData = cloud;
    final created = await recreateOutgoingMessage(service, original);
    expect(service.lastCall, 'textAt');
    expect(created?.messageInfo?.cloudCustomData, cloud);
  });
}

class _RecordingMessageService implements MessageService {
  String lastCall = '';
  int _id = 0;

  V2TimMsgCreateInfoResult _created(String call) {
    lastCall = call;
    final id = 'created-${++_id}';
    return V2TimMsgCreateInfoResult(
      id: id,
      messageInfo: _message(MessageElemType.V2TIM_ELEM_TYPE_NONE)..id = id,
    );
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage(
          {required String text}) async =>
      _created('text');

  @override
  Future<V2TimMsgCreateInfoResult?> createTextAtMessage({
    required String text,
    required List<String> atUserList,
  }) async =>
      _created('textAt');

  @override
  Future<V2TimMsgCreateInfoResult?> createCustomMessage(
          {required String data}) async =>
      _created('custom');

  @override
  Future<V2TimMsgCreateInfoResult?> createFaceMessage({
    required int index,
    required String data,
  }) async =>
      _created('face');

  @override
  Future<V2TimMsgCreateInfoResult?> createImageMessage({
    String? imageName,
    String? imagePath,
    dynamic inputElement,
  }) async =>
      _created('image');

  @override
  Future<V2TimMsgCreateInfoResult?> createVideoMessage({
    String? videoPath = '',
    String? type = '',
    int? duration = 0,
    String? snapshotPath = '',
    dynamic inputElement,
  }) async =>
      _created('video');

  @override
  Future<V2TimMsgCreateInfoResult?> createSoundMessage({
    required String soundPath,
    required int duration,
  }) async =>
      _created('sound');

  @override
  Future<V2TimMsgCreateInfoResult?> createFileMessage({
    String? filePath,
    required String fileName,
    dynamic inputElement,
  }) async =>
      _created('file');

  @override
  Future<V2TimMsgCreateInfoResult?> createLocationMessage({
    required String desc,
    required double longitude,
    required double latitude,
  }) async =>
      _created('location');

  @override
  Future<V2TimMsgCreateInfoResult?> createMergerMessage({
    required List<String> msgIDList,
    required String title,
    required List<String> abstractList,
    required String compatibleText,
  }) async =>
      _created('merger');

  @override
  Future<V2TimMsgCreateInfoResult?> createForwardMessage({
    String? msgID,
    V2TimMessage? message,
    String? webMessageInstance,
  }) async =>
      _created('forward');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimMessage _message(int elemType) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 1700000000,
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.elemType = elemType;
  return message;
}
