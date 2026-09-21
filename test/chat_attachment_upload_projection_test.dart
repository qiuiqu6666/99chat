import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_attachment_upload_projection.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_message_overlay_projection.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_file_card.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

const target = ChatAttachmentTarget(isGroup: false, id: 'bob');
ChatAttachmentTask task(String id,
        {String owner = 'alice', ChatAttachmentTarget to = target}) =>
    ChatAttachmentTask(
        taskId: id,
        ownerUserId: owner,
        target: to,
        sourcePath: '/private/local-source.bin',
        name: 'sample.bin',
        kind: 'file',
        nativeMessageKind: 'file',
        mimeType: 'application/octet-stream',
        sizeBytes: 200000000,
        createdAt: 200000);

V2TimMessage formal(
        {String reference = 'ref',
        String owner = 'alice',
        int timestamp = 201}) =>
    V2TimMessage.fromJson({
      'message_msg_id': 'sdk-$owner-$reference',
      'message_server_time': timestamp,
      'message_risk_type_identified': 0
    })
      ..sender = owner
      ..isSelf = owner == 'alice'
      ..elemType = 2
      ..customElem = V2TimCustomElem(
          data: jsonEncode(ChatAttachment(
                  attachmentId: 'att',
                  referenceId: reference,
                  kind: 'file',
                  name: 'sample.bin',
                  sizeBytes: 200000000,
                  mimeType: 'application/octet-stream')
              .toJson()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(setupServiceLocator);
  final store = LocalMessageOverlayStore.instance;
  setUp(() {
    store.invalidateScope();
    store.configureScope(ownerUserId: 'alice', domainGeneration: 1);
  });
  tearDown(store.invalidateScope);

  test('preparing upload appears in empty chat before any cloud ID exists', () {
    final pending = task('one');
    syncAttachmentUploadOverlays(
        store: store, owner: 'alice', target: target, tasks: [pending]);
    final overlays = store.messagesFor('c2c_bob');
    expect(overlays, hasLength(1));
    expect(attachmentUploadTaskId(overlays.single, 'alice'), 'one');
    expect(overlays.single.isExcludedFromUnreadCount, isTrue);
    expect(overlays.single.isExcludedFromLastMessage, isTrue);
    expect(overlays.single.customElem, isNull);
    expect(overlays.single.localCustomData, isNot(contains('/private/')));
    final rows = projectChatMessageOverlays(
        formalMessages: [],
        overlays: overlays,
        olderHistoryExhausted: false,
        includesLatestEdge: true);
    expect(rows.where((m) => m.elemType != 11), hasLength(1));
  });

  test(
      'progress updates do not rebuild the message list; resume preserves row ID',
      () {
    final pending = task('one');
    void sync() => syncAttachmentUploadOverlays(
        store: store, owner: 'alice', target: target, tasks: [pending]);
    var changes = 0;
    void changed() => changes++;
    store.addListener(changed);
    addTearDown(() => store.removeListener(changed));
    sync();
    final id = store.messagesFor('c2c_bob').single.msgID;
    pending.state = 'uploading';
    pending.progress = .05;
    sync();
    pending.progress = .75;
    sync();
    pending.state = 'paused';
    sync();
    pending.state = 'uploading';
    sync();
    expect(changes, 1);
    expect(store.messagesFor('c2c_bob').single.msgID, id);
    pending.attachmentId = 'att';
    pending.referenceId = 'ref';
    sync();
    expect(changes, 2);
    expect(store.messagesFor('c2c_bob').single.msgID, id);
  });

  test(
      'formal sending or failed bubble suppresses only its exact pending reference',
      () {
    final first = task('one')
      ..attachmentId = 'att'
      ..referenceId = 'ref'
      ..state = 'dispatching';
    final second = task('two')
      ..attachmentId = 'att'
      ..referenceId = 'different';
    final overlays = [
      attachmentUploadOverlay(first),
      attachmentUploadOverlay(second)
    ];
    for (final status in [1, 2, 3]) {
      final message = formal()..status = status;
      final visible = hideRepresentedAttachmentUploads(
          overlays: overlays, formalMessages: [message], owner: 'alice');
      expect(visible, hasLength(1));
      expect(attachmentUploadTaskId(visible.single, 'alice'), 'two');
    }
    expect(
        hideRepresentedAttachmentUploads(
            overlays: overlays,
            formalMessages: [formal(owner: 'other')],
            owner: 'alice'),
        hasLength(2));
  });

  test(
      'cancel/sent/handoff remove uploads while failed and unknown survive reopen',
      () {
    final pending = task('one');
    final unrelated = formal(reference: 'unrelated');
    store.upsert('c2c_bob', unrelated);
    for (final state in ['failed', 'paused', 'outcomeUnknown', 'dispatching']) {
      pending.state = state;
      final restored = ChatAttachmentTask.fromJson(pending.toJson());
      syncAttachmentUploadOverlays(
          store: store, owner: 'alice', target: target, tasks: [restored]);
      expect(store.messagesFor('c2c_bob'), hasLength(2));
    }
    for (final state in ['sent', 'cancelled', 'handedOff']) {
      pending.state = 'uploading';
      syncAttachmentUploadOverlays(
          store: store, owner: 'alice', target: target, tasks: [pending]);
      pending.state = state;
      syncAttachmentUploadOverlays(
          store: store, owner: 'alice', target: target, tasks: [pending]);
      expect(store.messagesFor('c2c_bob').single.msgID, unrelated.msgID);
    }
  });

  test(
      'scope and conversation filter prevent another account or chat seeing the task',
      () {
    final mine = task('one');
    syncAttachmentUploadOverlays(
        store: store,
        owner: 'alice',
        target: target,
        tasks: [
          mine,
          task('other-account', owner: 'other'),
          task('other-chat',
              to: const ChatAttachmentTarget(isGroup: true, id: 'group'))
        ]);
    expect(store.messagesFor('c2c_bob'), hasLength(1));
    expect(attachmentUploadTaskId(store.messagesFor('c2c_bob').single, 'other'),
        isNull);
    expect(
        hideRepresentedAttachmentUploads(
            overlays: store.messagesFor('c2c_bob'),
            formalMessages: [],
            owner: 'other'),
        isEmpty);
    store.configureScope(ownerUserId: 'other', domainGeneration: 2);
    expect(store.messagesFor('c2c_bob'), isEmpty);
  });

  test(
      'multiple pending tasks join history without modifying SDK list or unrelated rows',
      () {
    final first = task('one');
    final second = task('two');
    final sdk = [formal(timestamp: 199)];
    final result = projectChatMessageOverlays(
        formalMessages: sdk,
        overlays: [
          attachmentUploadOverlay(first),
          attachmentUploadOverlay(second)
        ],
        olderHistoryExhausted: false,
        includesLatestEdge: true);
    expect(sdk, hasLength(1));
    expect(result.where((m) => m.elemType != 11), hasLength(3));
    expect(result.where((m) => attachmentUploadTaskId(m, 'alice') != null),
        hasLength(2));
  });

  test('native SDK echo adopts the exact pending upload by cloud metadata', () {
    final pending = task('native')
      ..attachmentId = 'att'
      ..referenceId = 'ref';
    final native = formal()
      ..elemType = 5
      ..customElem = null
      ..cloudCustomData = jsonEncode({
        'type': 'chat.native-video',
        'version': 1,
        'clientOperationId': 'native',
        'attachmentId': 'att',
        'referenceId': 'ref'
      });
    expect(
        hideRepresentedAttachmentUploads(
            overlays: [attachmentUploadOverlay(pending)],
            formalMessages: [native],
            owner: 'alice',
            pendingTasks: [pending]),
        isEmpty);
    native.cloudCustomData = jsonEncode({
      'type': 'chat.native-video',
      'version': 1,
      'attachmentId': 'att',
      'referenceId': 'different'
    });
    expect(
        hideRepresentedAttachmentUploads(
            overlays: [attachmentUploadOverlay(pending)],
            formalMessages: [native],
            owner: 'alice',
            pendingTasks: [pending]),
        hasLength(1));
  });

  testWidgets(
      'upload percentage and pause/cancel controls are inside the file card',
      (tester) async {
    var pauses = 0, cancellations = 0;
    final card = ChatAttachmentFileCard(
      name: 'sample.apk',
      sizeBytes: 200000000,
      isSelf: true,
      isLocal: false,
      busy: true,
      progress: .35,
      error: '',
      uploadStatus: '上传 35%',
      onOpen: () {},
      onPause: () => pauses++,
      onCancel: () => cancellations++,
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) =>
          card.tuiBuild(context, TUIKitBuildValue(theme: TUITheme())),
    ))));
    expect(find.text('上传 35%'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .35);
    expect(tester.getSize(find.byType(LinearProgressIndicator)).width,
        lessThanOrEqualTo(240));
    await tester.tap(find.byTooltip('暂停上传'));
    await tester.tap(find.byTooltip('取消发送'));
    expect(pauses, 1);
    expect(cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  test(
      'formal adoption before overlay refresh never shows a duplicate or cancelled row',
      () {
    final pending = task('race');
    final oldOverlay = attachmentUploadOverlay(pending);
    pending.attachmentId = 'att';
    pending.referenceId = 'ref';
    pending.state = 'dispatching';
    expect(
        hideRepresentedAttachmentUploads(
            overlays: [oldOverlay],
            formalMessages: [formal()],
            owner: 'alice',
            pendingTasks: [pending]),
        isEmpty);
    pending.state = 'cancelled';
    expect(
        hideRepresentedAttachmentUploads(
            overlays: [oldOverlay],
            formalMessages: [],
            owner: 'alice',
            pendingTasks: [pending]),
        isEmpty);
  });
}
