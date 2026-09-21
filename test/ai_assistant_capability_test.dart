import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_upload_mime.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_capability.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';

void main() {
  test('image without files succeeds', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '一只猫',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.image);
    expect(plan.files, isEmpty);
  });

  test('image with one png is image plus fileIds', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '改成橘色',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'cat.png',
          sizeLabel: '',
          kind: AiAssistantFileKind.image,
          mimeType: 'image/png',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.image);
    expect(plan.files, hasLength(1));
  });

  test('plain chat with png is chat', () {
    final result = AiAssistantSendPlanner.plan(
      tool: null,
      text: '图里有什么',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'cat.png',
          sizeLabel: '',
          kind: AiAssistantFileKind.image,
          mimeType: 'image/png',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.chat);
    expect(plan.files, hasLength(1));
  });

  test('plain chat with pdf is file capability', () {
    final result = AiAssistantSendPlanner.plan(
      tool: null,
      text: '总结一下',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'doc.pdf',
          sizeLabel: '',
          kind: AiAssistantFileKind.pdf,
          mimeType: 'application/pdf',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.file);
    expect(plan.files, hasLength(1));
  });

  test('image with pdf fails', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '改成橘色',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'doc.pdf',
          sizeLabel: '',
          kind: AiAssistantFileKind.pdf,
          mimeType: 'application/pdf',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendError>());
  });

  test('image with contact card fails', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '一只猫',
      cards: const <AiAssistantCardRef>[
        AiAssistantCardRef(
          kind: AiAssistantCardKind.friend,
          id: 'u1',
          name: 'Ada',
        ),
      ],
      files: const <AiAssistantFileRef>[],
    );
    expect(result, isA<AiAssistantSendError>());
  });

  test('image with empty prompt fails', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '   ',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[],
    );
    expect(result, isA<AiAssistantSendError>());
  });

  test('analyze with pdf is file capability', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'analyze',
      text: '',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'doc.pdf',
          sizeLabel: '',
          kind: AiAssistantFileKind.pdf,
          mimeType: 'application/pdf',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.file);
  });

  test('plain text without tool is chat', () {
    final result = AiAssistantSendPlanner.plan(
      tool: null,
      text: '你好',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.chat);
  });

  test('copy and summarize plans have no files', () {
    final copy = AiAssistantSendPlanner.plan(
      tool: 'write',
      text: '写一句口号',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[],
    ) as AiAssistantSendPlan;
    expect(copy.capability, AiAssistantSendPlanner.copy);
    expect(copy.files, isEmpty);

    final summarize = AiAssistantSendPlanner.plan(
      tool: 'summarize',
      text: '重点',
      cards: const <AiAssistantCardRef>[
        AiAssistantCardRef(
          kind: AiAssistantCardKind.friend,
          id: 'u1',
          name: 'Ada',
        ),
      ],
      files: const <AiAssistantFileRef>[],
    ) as AiAssistantSendPlan;
    expect(summarize.capability, AiAssistantSendPlanner.summarize);
    expect(summarize.files, isEmpty);
    expect(summarize.analyze, isNotNull);
  });

  test('ensureFileName adds image extension from mime', () {
    expect(
      AiAssistantUploadMime.ensureFileName('photo', 'image/jpeg'),
      'photo.jpg',
    );
    expect(
      AiAssistantUploadMime.ensureFileName('cat.png', 'image/png'),
      'cat.png',
    );
  });

  test('plain chat with xlsx is chat', () {
    final result = AiAssistantSendPlanner.plan(
      tool: null,
      text: '看看这张表',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'data.xlsx',
          sizeLabel: '',
          kind: AiAssistantFileKind.excel,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.chat);
    expect(plan.files, hasLength(1));
  });

  test('plain chat with mp4 is chat', () {
    final result = AiAssistantSendPlanner.plan(
      tool: null,
      text: '视频里说了什么',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'clip.mp4',
          sizeLabel: '',
          kind: AiAssistantFileKind.video,
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendPlan>());
    final plan = result as AiAssistantSendPlan;
    expect(plan.capability, AiAssistantSendPlanner.chat);
    expect(plan.files, hasLength(1));
  });

  test('image with xlsx fails', () {
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '改成海报',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'data.xlsx',
          sizeLabel: '',
          kind: AiAssistantFileKind.excel,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    );
    expect(result, isA<AiAssistantSendError>());
  });

  test('duplicate fileId fails', () {
    const file = AiAssistantFileRef(
      name: 'cat.png',
      sizeLabel: '',
      kind: AiAssistantFileKind.image,
      mimeType: 'image/png',
      fileId: 'id-1',
    );
    final result = AiAssistantSendPlanner.plan(
      tool: 'image',
      text: '两张一样的',
      cards: const <AiAssistantCardRef>[],
      files: const <AiAssistantFileRef>[file, file],
    );
    expect(result, isA<AiAssistantSendError>());
  });
}
