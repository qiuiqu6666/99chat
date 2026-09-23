import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_attachment_upload_projection.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_message_overlay_projection.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

const _target = ChatAttachmentTarget(isGroup: false, id: 'peer');

class _DisabledApi extends ChatAttachmentApi {
  @override
  Future<ChatAttachmentPolicy> policy({CancelToken? cancelToken}) async =>
      const ChatAttachmentPolicy();
}

ChatAttachmentTask _task(int index) => ChatAttachmentTask(
      taskId: 'large-$index',
      ownerUserId: 'owner',
      target: _target,
      sourcePath: '/tmp/large.jpg',
      name: 'large.jpg',
      kind: 'image',
      nativeMessageKind: 'image',
      mimeType: 'image/jpeg',
      sizeBytes: 30000000,
      createdAt: 1700000000000 + (3 - index) * 1000,
      mediaBatchId: 'selection',
      mediaBatchIndex: index,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('task persistence retains selection index zero and supports older tasks',
      () {
    final restored = ChatAttachmentTask.fromJson(_task(0).toJson());
    expect(restored.mediaBatchId, 'selection');
    expect(restored.mediaBatchIndex, 0);
    final legacy = _task(0).toJson()
      ..remove('mediaBatchId')
      ..remove('mediaBatchIndex');
    expect(ChatAttachmentTask.fromJson(legacy).mediaBatchIndex, isNull);
    expect(
        ChatAttachmentTask.fromJson({...legacy, 'mediaBatchIndex': -1})
            .mediaBatchIndex,
        isNull);
  });

  test('large pending images and completed SDK images share selection order',
      () {
    final small = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'small-1'
      ..msgID = 'server-1'
      ..timestamp = 1700000020
      ..isSelf = true
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
    applyChatMediaBatchToMessage(small, batchId: 'selection', batchIndex: 1);
    final overlays = [
      attachmentUploadOverlay(_task(2)),
      attachmentUploadOverlay(_task(0))
    ];
    expect(attachmentUploadTaskId(overlays.last, 'owner'), 'large-0');
    for (final smallFirst in [true, false]) {
      final rows = projectChatMessageOverlays(
          formalMessages: [small],
          overlays: smallFirst ? overlays : overlays.reversed.toList(),
          olderHistoryExhausted: true,
          includesLatestEdge: true);
      expect(
          rows
              .where((m) => m.elemType != 11)
              .toList()
              .reversed
              .map(readChatMediaBatchIndex),
          [0, 1, 2]);
    }
  });

  test('attachment start and reload preserve batch when policy rejects upload',
      () async {
    final dir = await Directory.systemTemp.createTemp('media-batch-order-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/image.jpg').writeAsBytes([1, 2, 3]);
    final store = ChatAttachmentStore(rootProvider: () async => dir);
    ChatAttachmentService service() => ChatAttachmentService(
        api: _DisabledApi(),
        store: store,
        ownerProvider: () => 'owner',
        generationProvider: () => 1,
        platformSupported: () => true);
    final first = service();
    var notified = false;
    var handedOff = false;
    first.addListener(() => notified = true);
    await first.start(
        path: file.path,
        target: _target,
        nativeMessageKind: 'image',
        mediaBatchId: 'selection',
        mediaBatchIndex: 0,
        onQueued: () {
          expect(notified, isTrue);
          expect(first.tasksFor(_target), hasLength(1));
          expect(dir.listSync(recursive: true).whereType<File>()
              .any((f) => f.path.endsWith('task.json')), isTrue);
          handedOff = true;
        });
    expect(handedOff, isTrue);
    expect(first.tasksFor(_target).single.state, 'failed');
    first.dispose();
    final reopened = service();
    addTearDown(reopened.dispose);
    await reopened.load();
    final restored = reopened.tasksFor(_target).single;
    expect(restored.mediaBatchId, 'selection');
    expect(restored.mediaBatchIndex, 0);
    expect(readChatMediaBatchIndex(attachmentUploadOverlay(restored)), 0);
  });
}
