import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_upload_mime.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';

class AiAssistantSendError {
  const AiAssistantSendError({
    required this.zhHans,
    required this.zhHant,
    required this.en,
    required this.ja,
    required this.ko,
  });

  final String zhHans;
  final String zhHant;
  final String en;
  final String ja;
  final String ko;

  String localize(AppI18n i18n) {
    return i18n.t(
      zhHans: zhHans,
      zhHant: zhHant,
      en: en,
      ja: ja,
      ko: ko,
    );
  }
}

class AiAssistantSendPlan {
  const AiAssistantSendPlan({
    required this.capability,
    required this.content,
    required this.displayText,
    this.analyze,
    this.files = const <AiAssistantFileRef>[],
    this.cards = const <AiAssistantCardRef>[],
  });

  final String capability;
  final String content;
  final String displayText;
  final AiAssistantAnalyze? analyze;
  final List<AiAssistantFileRef> files;
  final List<AiAssistantCardRef> cards;
}

class AiAssistantSendPlanner {
  AiAssistantSendPlanner._();

  static const chat = 'chat';
  static const summarize = 'summarize';
  static const copy = 'copy';
  static const file = 'file';
  static const image = 'image';

  static String fromTool(String? tool) {
    switch (tool) {
      case 'summarize':
        return summarize;
      case 'write':
        return copy;
      case 'analyze':
        return file;
      case 'image':
        return image;
      default:
        return chat;
    }
  }

  static Object plan({
    required String? tool,
    required String text,
    required List<AiAssistantCardRef> cards,
    required List<AiAssistantFileRef> files,
  }) {
    final trimmed = text.trim();
    if (trimmed.charactersLength > AiAssistantUploadMime.maxContentChars) {
      return const AiAssistantSendError(
        zhHans: '内容最多 8000 字',
        zhHant: '內容最多 8000 字',
        en: 'Message can be at most 8000 characters.',
        ja: '本文は8000文字以内です。',
        ko: '내용은 최대 8000자입니다.',
      );
    }
    final capability = resolveCapability(
      tool: tool,
      hasCards: cards.isNotEmpty,
      files: files,
    );
    switch (capability) {
      case summarize:
        if (files.isNotEmpty) {
          return const AiAssistantSendError(
            zhHans: '总结聊天记录不能附带文件',
            zhHant: '總結聊天記錄不能附帶檔案',
            en: 'Summarize cannot include files.',
            ja: '要約にファイルは付けられません。',
            ko: '요약에는 파일을 첨부할 수 없습니다.',
          );
        }
        if (cards.isEmpty) {
          return const AiAssistantSendError(
            zhHans: '请先选择一个对话或群聊',
            zhHant: '請先選擇一個對話或群聊',
            en: 'Pick a chat or group first.',
            ja: '先に会話またはグループを選んでください。',
            ko: '대화 또는 그룹을 먼저 선택하세요.',
          );
        }
        final card = cards.first;
        final analyze = card.kind == AiAssistantCardKind.group
            ? AiAssistantAnalyze.group(card.id)
            : AiAssistantAnalyze.c2c(card.id);
        return AiAssistantSendPlan(
          capability: summarize,
          content: trimmed,
          displayText: trimmed.isEmpty
              ? AppI18n.current.t(
                  zhHans: '[分析聊天记录]',
                  zhHant: '[分析聊天記錄]',
                  en: '[Analyze chat history]',
                  ja: '[チャット履歴を分析]',
                  ko: '[채팅 기록 분석]',
                )
              : trimmed,
          analyze: analyze,
          cards: <AiAssistantCardRef>[card],
        );
      case file:
        if (cards.isNotEmpty) {
          return const AiAssistantSendError(
            zhHans: '分析文件不能附带名片',
            zhHant: '分析檔案不能附帶名片',
            en: 'File analysis cannot include contact cards.',
            ja: 'ファイル分析に名刺は付けられません。',
            ko: '파일 분석에는 명함을 넣을 수 없습니다.',
          );
        }
        if (files.isEmpty) {
          return const AiAssistantSendError(
            zhHans: '请添加要分析的文件',
            zhHant: '請新增要分析的檔案',
            en: 'Add a file to analyze.',
            ja: '分析するファイルを追加してください。',
            ko: '분석할 파일을 추가하세요.',
          );
        }
        if (files.length > AiAssistantUploadMime.maxFileCount) {
          return const AiAssistantSendError(
            zhHans: '一次最多分析 3 个文件',
            zhHant: '一次最多分析 3 個檔案',
            en: 'You can analyze up to 3 files.',
            ja: '一度に分析できるファイルは3つまでです。',
            ko: '한 번에 최대 3개 파일을 분석할 수 있습니다.',
          );
        }
        final fileError = validateFiles(files);
        if (fileError != null) {
          return fileError;
        }
        final fileDup = validateNoDuplicateFiles(files);
        if (fileDup != null) {
          return fileDup;
        }
        return AiAssistantSendPlan(
          capability: file,
          content: trimmed,
          displayText: trimmed.isEmpty
              ? AppI18n.current.t(
                  zhHans: '[分析文件]',
                  zhHant: '[分析檔案]',
                  en: '[Analyze file]',
                  ja: '[ファイルを分析]',
                  ko: '[파일 분석]',
                )
              : trimmed,
          files: files,
        );
      case image:
        if (cards.isNotEmpty) {
          return const AiAssistantSendError(
            zhHans: '生成图片不能附带名片',
            zhHant: '生成圖片不能附帶名片',
            en: 'Image generation cannot include contact cards.',
            ja: '画像生成に名刺は付けられません。',
            ko: '이미지 생성에는 명함을 넣을 수 없습니다.',
          );
        }
        if (files.length > AiAssistantUploadMime.maxFileCount) {
          return const AiAssistantSendError(
            zhHans: '一次最多 3 张原图',
            zhHant: '一次最多 3 張原圖',
            en: 'You can attach up to 3 original images.',
            ja: '元画像は3枚までです。',
            ko: '원본 이미지는 최대 3장입니다.',
          );
        }
        final imageError = validateImageFiles(files);
        if (imageError != null) {
          return imageError;
        }
        final imageDup = validateNoDuplicateFiles(files);
        if (imageDup != null) {
          return imageDup;
        }
        if (trimmed.isEmpty) {
          return const AiAssistantSendError(
            zhHans: '请描述你想生成的图片',
            zhHant: '請描述你想生成的圖片',
            en: 'Describe the image you want.',
            ja: '作りたい画像を説明してください。',
            ko: '만들고 싶은 이미지를 설명해 주세요.',
          );
        }
        return AiAssistantSendPlan(
          capability: image,
          content: trimmed,
          displayText: trimmed,
          files: files,
        );
      case copy:
        if (files.isNotEmpty || cards.isNotEmpty) {
          return const AiAssistantSendError(
            zhHans: '写文案只需文字',
            zhHant: '寫文案只需文字',
            en: 'Copywriting only needs text.',
            ja: 'コピー作成はテキストだけで行います。',
            ko: '문구 작성은 텍스트만 있으면 됩니다.',
          );
        }
        if (trimmed.isEmpty) {
          return const AiAssistantSendError(
            zhHans: '请输入文案主题或要求',
            zhHant: '請輸入文案主題或要求',
            en: 'Enter the topic or requirements.',
            ja: 'テーマや要件を入力してください。',
            ko: '주제나 요구사항을 입력하세요.',
          );
        }
        return AiAssistantSendPlan(
          capability: copy,
          content: trimmed,
          displayText: trimmed,
        );
      default:
        if (cards.isNotEmpty) {
          return const AiAssistantSendError(
            zhHans: '闲聊只需文字',
            zhHant: '閒聊只需文字',
            en: 'Chat only needs text.',
            ja: '雑談はテキストだけで行います。',
            ko: '일반 대화는 텍스트만 있으면 됩니다.',
          );
        }
        if (files.isNotEmpty) {
          if (files.length > AiAssistantUploadMime.maxFileCount) {
            return const AiAssistantSendError(
              zhHans: '一次最多 3 张原图',
              zhHant: '一次最多 3 張原圖',
              en: 'You can attach up to 3 original images.',
              ja: '元画像は3枚までです。',
              ko: '원본 이미지는 최대 3장입니다.',
            );
          }
          final chatError = validateChatFiles(files);
          if (chatError != null) {
            return chatError;
          }
          final chatDup = validateNoDuplicateFiles(files);
          if (chatDup != null) {
            return chatDup;
          }
        }
        if (trimmed.isEmpty) {
          return const AiAssistantSendError(
            zhHans: '请输入文字或添加附件',
            zhHant: '請輸入文字或新增附件',
            en: 'Type a message or add an attachment.',
            ja: '文字を入力するか添付を追加してください。',
            ko: '글을 입력하거나 첨부파일을 추가하세요.',
          );
        }
        return AiAssistantSendPlan(
          capability: chat,
          content: trimmed,
          displayText: trimmed,
          files: files,
        );
    }
  }

  static String resolveCapability({
    required String? tool,
    required bool hasCards,
    required List<AiAssistantFileRef> files,
  }) {
    final hasPdf = files.any(
      (file) => AiAssistantUploadMime.isPdf(file.name, file.mimeType),
    );
    final hasImages = files.any(
      (file) => AiAssistantUploadMime.isAllowedImage(file.name, file.mimeType),
    );
    if (tool == 'write') {
      return copy;
    }
    if (tool == 'summarize' ||
        (hasCards &&
            tool != 'image' &&
            tool != 'analyze')) {
      return summarize;
    }
    if (tool == 'image') {
      return image;
    }
    if (tool == 'analyze' || hasPdf) {
      return file;
    }
    if (hasImages) {
      return chat;
    }
    return fromTool(tool);
  }

  static AiAssistantSendError? validateImageFiles(
    List<AiAssistantFileRef> files,
  ) {
    for (final file in files) {
      if (!AiAssistantUploadMime.isAllowedImage(file.name, file.mimeType)) {
        return const AiAssistantSendError(
          zhHans: '改图仅支持 JPG / PNG / WEBP / GIF',
          zhHant: '改圖僅支援 JPG / PNG / WEBP / GIF',
          en: 'Image edits only allow JPG, PNG, WEBP, or GIF.',
          ja: '画像編集は JPG / PNG / WEBP / GIF のみです。',
          ko: '이미지 수정은 JPG / PNG / WEBP / GIF만 지원합니다.',
        );
      }
      final size = file.sizeBytes;
      if (size != null && size > AiAssistantUploadMime.maxBytes) {
        return const AiAssistantSendError(
          zhHans: '文件不能超过 20MB',
          zhHant: '檔案不能超過 20MB',
          en: 'Each file must be 20MB or smaller.',
          ja: 'ファイルは20MB以内です。',
          ko: '파일은 20MB 이하여야 합니다.',
        );
      }
    }
    return null;
  }

  static AiAssistantSendError? validateChatFiles(List<AiAssistantFileRef> files) {
    for (final file in files) {
      if (!AiAssistantUploadMime.isChatAttachment(file.name, file.mimeType)) {
        return const AiAssistantSendError(
          zhHans: '闲聊仅支持图片、表格或视频',
          zhHant: '閒聊僅支援圖片、表格或影片',
          en: 'Chat attachments must be images, spreadsheets, or videos.',
          ja: '雑談の添付は画像・表・動画のみです。',
          ko: '일반 대화 첨부는 이미지, 표, 영상만 가능합니다.',
        );
      }
      final size = file.sizeBytes;
      if (size != null && size > AiAssistantUploadMime.maxBytes) {
        return const AiAssistantSendError(
          zhHans: '文件不能超过 20MB',
          zhHant: '檔案不能超過 20MB',
          en: 'Each file must be 20MB or smaller.',
          ja: 'ファイルは20MB以内です。',
          ko: '파일은 20MB 이하여야 합니다.',
        );
      }
    }
    return null;
  }

  static AiAssistantSendError? validateFiles(List<AiAssistantFileRef> files) {
    for (final file in files) {
      if (!AiAssistantUploadMime.matchesMime(file.name, file.mimeType) ||
          !AiAssistantUploadMime.allowedMimes.contains(
            AiAssistantUploadMime.fromName(file.name),
          )) {
        return const AiAssistantSendError(
          zhHans: '仅支持图片、表格、视频或 PDF',
          zhHant: '僅支援圖片、表格、影片或 PDF',
          en: 'Only images, spreadsheets, videos, or PDF are allowed.',
          ja: '画像・表・動画・PDF のみ対応です。',
          ko: '이미지, 표, 영상, PDF만 지원합니다.',
        );
      }
      final size = file.sizeBytes;
      if (size != null && size > AiAssistantUploadMime.maxBytes) {
        return const AiAssistantSendError(
          zhHans: '文件不能超过 20MB',
          zhHant: '檔案不能超過 20MB',
          en: 'Each file must be 20MB or smaller.',
          ja: 'ファイルは20MB以内です。',
          ko: '파일은 20MB 이하여야 합니다.',
        );
      }
    }
    return null;
  }

  static AiAssistantSendError? validateNoDuplicateFiles(
    List<AiAssistantFileRef> files,
  ) {
    final seen = <String>{};
    for (final file in files) {
      final id = (file.fileId ?? '').trim();
      final path = (file.localPath ?? '').trim();
      final key = id.isNotEmpty
          ? 'id:$id'
          : (path.isNotEmpty
              ? 'path:$path'
              : 'name:${file.name}|${file.sizeBytes ?? ''}');
      if (!seen.add(key)) {
        return const AiAssistantSendError(
          zhHans: '不能添加重复文件',
          zhHant: '不能新增重複檔案',
          en: 'Duplicate files are not allowed.',
          ja: '同じファイルは重複できません。',
          ko: '중복 파일은 추가할 수 없습니다.',
        );
      }
    }
    return null;
  }
}

extension on String {
  int get charactersLength => runes.length;
}

class AiAssistantErrorText {
  AiAssistantErrorText._();

  static String localize(
    AppI18n i18n, {
    required String code,
    String fallback = '',
  }) {
    switch (code) {
      case 'UNAUTHORIZED':
        return i18n.t(
          zhHans: '登录已失效，请重新登录',
          zhHant: '登入已失效，請重新登入',
          en: 'Session expired. Please sign in again.',
          ja: 'ログインの期限が切れました。',
          ko: '로그인이 만료되었습니다.',
        );
      case 'INVALID_INPUT':
        return fallback.isNotEmpty
            ? fallback
            : i18n.t(
                zhHans: '请求无效',
                zhHant: '請求無效',
                en: 'Invalid request.',
                ja: 'リクエストが無効です。',
                ko: '요청이 올바르지 않습니다.',
              );
      case 'FILE_TOO_LARGE':
        return i18n.t(
          zhHans: '文件不能超过 20MB',
          zhHant: '檔案不能超過 20MB',
          en: 'File is larger than 20MB.',
          ja: 'ファイルが20MBを超えています。',
          ko: '파일이 20MB를 초과합니다.',
        );
      case 'CHAT_BUSY':
        return i18n.t(
          zhHans: '上一条回复还在生成中',
          zhHant: '上一則回覆還在生成中',
          en: 'A reply is still generating.',
          ja: '前の返信を生成中です。',
          ko: '이전 답변이 아직 생성 중입니다.',
        );
      case 'FILE_UNAVAILABLE':
        return i18n.t(
          zhHans: '文件不可用',
          zhHant: '檔案不可用',
          en: 'File is unavailable.',
          ja: 'ファイルを利用できません。',
          ko: '파일을 사용할 수 없습니다.',
        );
      case 'NOT_FRIEND':
        return i18n.t(
          zhHans: '对方还不是好友，无法总结该对话',
          zhHant: '對方還不是好友，無法總結該對話',
          en: 'You can only summarize a mutual friend chat.',
          ja: '相互の友だちではないため要約できません。',
          ko: '서로 친구가 아니라 이 대화를 요약할 수 없습니다.',
        );
      case 'NOT_GROUP_MEMBER':
        return i18n.t(
          zhHans: '你不在该群，无法总结',
          zhHant: '你不在該群，無法總結',
          en: 'You are not in that group.',
          ja: 'そのグループに参加していないため要約できません。',
          ko: '해당 그룹에 없어 요약할 수 없습니다.',
        );
      case 'ARCHIVE_RATE_LIMITED':
        return i18n.t(
          zhHans: '请求过于频繁，请稍后再试',
          zhHant: '請求過於頻繁，請稍後再試',
          en: 'Too many requests. Try again later.',
          ja: 'リクエストが多すぎます。しばらくしてから再試行してください。',
          ko: '요청이 너무 많습니다. 잠시 후 다시 시도하세요.',
        );
      case 'LLM_NOT_CONFIGURED':
      case 'LLM_UPSTREAM':
      case 'MAIN_UNAVAILABLE':
        return i18n.t(
          zhHans: '助手暂时不可用，请稍后重试',
          zhHant: '助手暫時不可用，請稍後重試',
          en: 'The assistant is unavailable. Try again later.',
          ja: 'アシスタントを利用できません。しばらくしてから再試行してください。',
          ko: '도우미를 사용할 수 없습니다. 잠시 후 다시 시도하세요.',
        );
      default:
        return fallback.isNotEmpty
            ? fallback
            : i18n.t(
                zhHans: '发送失败',
                zhHant: '發送失敗',
                en: 'Failed to send.',
                ja: '送信に失敗しました。',
                ko: '전송에 실패했습니다.',
              );
    }
  }
}
