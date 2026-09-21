import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:flutter_plugin_record_plus/const/response.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_media_work_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'media-owner');
  });

  test('upload progress does not regress on stale callbacks', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'progress-local'
      ..msgID = 'progress-sdk'
      ..groupID = 'original';
    model.applyAppSendMessageProgress(message, 40);
    model.applyAppSendMessageProgress(message, 20);
    model.applyAppSendMessageProgress(message, 40);
    expect(model.getMessageProgress('progress-local'), 40);
    expect(model.getMessageProgress('progress-sdk'), 40);
    model.applyAppSendMessageProgress(message, 60);
    expect(model.getMessageProgress('progress-local'), 60);
  });
  test('queued sender keeps its target and account after chat disposal',
      () async {
    final page = TUIChatSeparateViewModel()
      ..conversationID = 'group_original'
      ..conversationType = ConvType.group
      ..suppressReadReporting = true;
    final sender = page.captureMediaSender(
        convID: 'group_original', convType: ConvType.group);
    final gate = Completer<void>();
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 1);
    final preparation = queue.run(() => gate.future);
    final send = queue.run(() async => [
          sender.conversationID,
          sender.conversationType,
          sender.canSendCapturedMedia
        ]);
    page.conversationID = 'c2c_other';
    page.dispose();
    gate.complete();
    await preparation;
    expect(await send, ['original', ConvType.group, true]);
    expect(sender.lifeCycle, isNull);
  });

  test('accepted media work survives app background and drains on its queue',
      () async {
    final page = TUIChatSeparateViewModel()
      ..conversationID = 'group_background'
      ..conversationType = ConvType.group
      ..suppressReadReporting = true;
    final sender = page.captureMediaSender(
      convID: 'group_background',
      convType: ConvType.group,
    );
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 1);
    final release = Completer<void>();
    final started = Completer<void>();
    final work = queue.run(() async {
      started.complete();
      await release.future;
      return sender.canSendCapturedMedia;
    });

    await started.future;
    DeviceSyncService.instance.setAppLifecycle(AppLifecycleState.paused);
    page.dispose();
    expect(sender.canSendCapturedMedia, isTrue);
    release.complete();
    expect(await work, isTrue);
    DeviceSyncService.instance.setAppLifecycle(AppLifecycleState.resumed);
  });

  test('explicit cancellation still blocks a detached image and video',
      () async {
    final page = TUIChatSeparateViewModel()..suppressReadReporting = true;
    final sender = page.captureMediaSender(
        convID: 'group_original', convType: ConvType.group);
    serviceLocator<TUIChatGlobalModel>()
        .markOutgoingMediaCancelled('cancelled-media');
    expect(
        await sender.sendImageMessage(
            existingOptimisticId: 'cancelled-media',
            imagePath: 'not-needed.jpg',
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    expect(
        await sender.sendVideoMessage(
            existingOptimisticId: 'cancelled-media',
            videoPath: 'not-needed.mp4',
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    page.dispose();
  });

  test('account boundary rejects all captured media kinds before SDK creation',
      () async {
    final page = TUIChatSeparateViewModel()..suppressReadReporting = true;
    final sender = page.captureMediaSender(
        convID: 'group_original', convType: ConvType.group);
    SessionIdentityService.instance.invalidate();
    expect(sender.canSendCapturedMedia, isFalse);
    expect(
        await sender.sendSoundMessage(
            soundPath: 'not-needed.wav',
            duration: 2,
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    final completion = Completer<RecordResponse>();
    final staleJob = sender.sendFinalizingRecording(
        completion: completion.future,
        convID: 'group_original',
        convType: ConvType.group,
        estimatedDuration: 2);
    completion
        .completeError(StateError('native finalization failed after logout'));
    await staleJob;

    expect(
        await sender.sendImageMessage(
            imagePath: 'not-needed.jpg',
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    expect(
        await sender.sendVideoMessage(
            videoPath: 'not-needed.mp4',
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    expect(
        await sender.sendFileMessage(
            filePath: 'not-needed.pdf',
            convID: 'group_original',
            convType: ConvType.group),
        isNull);
    page.dispose();
  });
}
