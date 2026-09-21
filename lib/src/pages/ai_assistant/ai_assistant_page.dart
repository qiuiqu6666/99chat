import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_upload_mime.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_capability.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_draft.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_file_kind.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_history_map.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_markdown.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_markdown.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_search.dart';
import 'package:tencent_cloud_chat_demo/src/pages/contact_card_user_picker_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/ai_assistant_welcome_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/system_media_picker.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/utils/immersive_app_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/platform/clipboard_guard.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_share_picker_page.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/forward_pick_pages.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_mention_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/group_display_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_payload.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/gallery_save_to_photos.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';

class _AiPalette {
  const _AiPalette._();

  static const Color header = Color(0xFFF8FAFF);
  static const Color canvas = Color(0xFFF1F5FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color userBubble = Color(0xFF2688F5);
  static const Color input = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF182230);
  static const Color subText = Color(0xFF7C899D);
  static const Color border = Color(0xFFE3E9F2);
  static const Color accent = Color(0xFF4B7BFF);

  static Color headerBg(bool dark) =>
      dark ? AppColors.card(dark: true) : header;
  static Color canvasBg(bool dark) =>
      dark ? AppColors.background(dark: true) : canvas;
  static Color cardBg(bool dark) => dark ? AppColors.card(dark: true) : card;
  static Color inputBg(bool dark) =>
      dark ? AppColors.surfaceAlt(dark: true) : input;
  static Color primary(bool dark) => dark ? AppColors.text(dark: true) : text;
  static Color secondary(bool dark) =>
      dark ? AppColors.subText(dark: true) : subText;
  static Color line(bool dark) => dark ? AppColors.line(dark: true) : border;
  static Color brand(bool dark) => dark ? AppTokens.accent : accent;
  static Color bubble(bool dark) => dark ? AppTokens.accent : userBubble;
}

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _listController = ScrollController();
  final List<AiAssistantDraftItem> _drafts = <AiAssistantDraftItem>[];
  final List<GlobalKey> _messageKeys = <GlobalKey>[];
  late final String _userId;
  List<AiAssistantMessage> _messages = <AiAssistantMessage>[];
  List<int> _matchIndexes = <int>[];
  bool _messagesReady = false;
  bool _welcomeVisible = false;
  bool _guideVisible = false;
  bool _searching = false;
  int _activeMatch = 0;
  String? _selectedTool;
  bool _replying = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  bool _hasMore = false;
  String? _nextCursor;
  CancelToken? _streamCancel;
  final Map<String, Uint8List> _fileCache = <String, Uint8List>{};
  bool _fileOpening = false;
  String _selfAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _userId = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    _listController.addListener(_onHistoryScroll);
    _loadWelcome();
    unawaited(_loadSelfAvatar());
  }

  String _selfProfileOwnerId() {
    final jwt = ContactSocialCacheStore.safeLoginUserId();
    if (jwt.isNotEmpty) {
      return jwt;
    }
    return SessionManager.instance.state.userId?.trim() ?? '';
  }

  bool _shouldApplySelfMeResult({
    required String capturedOwner,
    required String currentOwner,
    required String meUserId,
  }) {
    final me = meUserId.trim();
    if (me.isEmpty) {
      return false;
    }
    final current = currentOwner.trim();
    if (current.isNotEmpty && current != me) {
      return false;
    }
    return true;
  }

  Future<void> _loadSelfAvatar() async {
    final keys = <String>{
      _selfProfileOwnerId().trim(),
      _userId.trim(),
    }..removeWhere((id) => id.isEmpty);
    try {
      for (final id in keys) {
        final cached = UserProfileLocalService.instance.readCached(id);
        final record = cached ?? await UserProfileLocalService.instance.read(id);
        if (!mounted) {
          return;
        }
        final url = UserAvatarHelper.usableAvatarOrEmpty(record?.avatarUrl);
        if (url.isNotEmpty) {
          setState(() {
            _selfAvatarUrl = url;
          });
          return;
        }
      }
      final identity = SessionIdentityService.instance.capture();
      final me = await AuthApi.instance.fetchMe();
      if (!mounted) {
        return;
      }
      final currentOwner = _selfProfileOwnerId();
      if (!_shouldApplySelfMeResult(
        capturedOwner: identity.ownerUserId,
        currentOwner: currentOwner,
        meUserId: me.userId.trim(),
      )) {
        return;
      }
      await UserProfileLocalService.instance.saveMeResult(me);
      if (!mounted) {
        return;
      }
      final url = UserAvatarHelper.usableAvatarOrEmpty(me.avatarUrl);
      if (url.isEmpty) {
        return;
      }
      setState(() {
        _selfAvatarUrl = url;
      });
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messagesReady) {
      return;
    }
    _messagesReady = true;
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _streamCancel?.cancel('dispose');
    _listController.removeListener(_onHistoryScroll);
    _inputController.dispose();
    _inputFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _loadWelcome() async {
    final dismissed = await AiAssistantWelcomeStore.isDismissed(_userId);
    final guideDismissed =
        await AiAssistantWelcomeStore.isGuideDismissed(_userId);
    if (!mounted) return;
    setState(() {
      _welcomeVisible = !dismissed;
      _guideVisible = !guideDismissed;
    });
    _scrollToEnd();
  }

  void _onHistoryScroll() {
    if (!_hasMore || _historyLoading || !_listController.hasClients) {
      return;
    }
    final position = _listController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    if (position.pixels < position.maxScrollExtent - 64) {
      return;
    }
    unawaited(_loadOlderHistory());
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
    });
    try {
      final page = await AiAssistantApi.instance.history(limit: 100);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = page.items.map(AiAssistantHistoryMap.toMessage).toList();
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _historyLoading = false;
        _historyLoaded = true;
        if (_hasStreamingHistory(_messages)) {
          _replying = true;
        }
        _syncKeys();
        if (_searching) {
          _applyMatches();
        }
      });
      _scrollToEnd();
      _prefetchHistoryImages();
      unawaited(_hydrateHistoryCards());
    } on AiAssistantException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <AiAssistantMessage>[];
        _historyLoading = false;
        _historyLoaded = true;
        _syncKeys();
      });
      _toastApiError(error);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <AiAssistantMessage>[];
        _historyLoading = false;
        _historyLoaded = true;
        _syncKeys();
      });
      _toastApiError(
        const AiAssistantException('MAIN_UNAVAILABLE', ''),
      );
    }
  }

  Future<void> _loadOlderHistory() async {
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty || _historyLoading) {
      return;
    }
    setState(() {
      _historyLoading = true;
    });
    try {
      final page = await AiAssistantApi.instance.history(
        limit: 50,
        cursor: cursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <AiAssistantMessage>[
          ...page.items.map(AiAssistantHistoryMap.toMessage),
          ..._messages,
        ];
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _historyLoading = false;
        _syncKeys();
        if (_searching) {
          _applyMatches();
        }
      });
      _prefetchHistoryImages();
      unawaited(_hydrateHistoryCards());
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _historyLoading = false;
      });
    }
  }

  bool _hasStreamingHistory([List<AiAssistantMessage>? source]) {
    final items = source ?? _messages;
    return items.any((item) => item.status == 'streaming');
  }

  void _toastApiError(AiAssistantException error) {
    if (error.cancelled) {
      return;
    }
    ToastUtils.toast(
      AiAssistantErrorText.localize(
        AppI18n.of(context),
        code: error.code,
        fallback: error.message,
      ),
    );
  }

  Future<void> _ensureFileBytes(String fileId, {bool silent = false}) async {
    final id = fileId.trim();
    if (id.isEmpty || _fileCache.containsKey(id)) {
      return;
    }
    try {
      final bytes = await AiAssistantApi.instance.downloadFile(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _fileCache[id] = bytes;
        _hydrateHistoryFiles(id, bytes);
      });
    } on AiAssistantException catch (error) {
      if (!silent) {
        _toastApiError(error);
      }
    } catch (_) {
      if (!silent) {
        _toastApiError(const AiAssistantException('FILE_UNAVAILABLE', ''));
      }
    }
  }

  void _hydrateHistoryFiles(String fileId, Uint8List bytes) {
    final mime = AiAssistantUploadMime.sniffMime(bytes);
    if (mime == null) {
      return;
    }
    final kind = AiAssistantUploadMime.allowedImageMimes.contains(mime)
        ? AiAssistantFileKind.image
        : mime == 'application/pdf'
            ? AiAssistantFileKind.pdf
            : null;
    if (kind == null) {
      return;
    }
    final name = AiAssistantUploadMime.ensureFileName(
      kind == AiAssistantFileKind.image ? 'image' : 'file',
      mime,
    );
    _messages = _messages.map((message) {
      var touched = false;
      final files = message.files.map((file) {
        if ((file.fileId ?? '').trim() != fileId) {
          return file;
        }
        touched = true;
        return AiAssistantFileRef(
          name: file.name == '附件' || file.name.isEmpty ? name : file.name,
          sizeLabel: file.sizeLabel.isEmpty
              ? AiAssistantDraftFormats.bytes(bytes.length)
              : file.sizeLabel,
          kind: kind,
          localPath: file.localPath,
          fileId: file.fileId,
          bytes: bytes,
          mimeType: mime,
          sizeBytes: bytes.length,
        );
      }).toList(growable: false);
      if (!touched) {
        return message;
      }
      return AiAssistantMessage(
        role: message.role,
        time: message.time,
        text: message.text,
        files: files,
        cards: message.cards,
        outputKind: message.outputKind,
        summary: message.summary,
        analysis: message.analysis,
        code: message.code,
        serverId: message.serverId,
        capability: message.capability,
        status: message.status,
        imageUrl: message.imageUrl,
        failed: message.failed,
      );
    }).toList();
  }

  void _prefetchHistoryImages() {
    final ids = <String>{};
    for (final message in _messages) {
      final fromUrl = AiAssistantApi.fileIdFromUrl(message.imageUrl);
      if (fromUrl != null) {
        ids.add(fromUrl);
      }
      for (final file in message.files) {
        final id = (file.fileId ?? '').trim();
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    for (final id in ids) {
      unawaited(_ensureFileBytes(id, silent: true));
    }
  }

  Future<void> _hydrateHistoryCards() async {
    final pending = <String, AiAssistantCardRef>{};
    for (final message in _messages) {
      for (final card in message.cards) {
        final key = '${card.kind.name}:${card.id}';
        pending.putIfAbsent(key, () => card);
      }
    }
    if (pending.isEmpty) {
      return;
    }
    final resolved = <String, AiAssistantCardRef>{};
    for (final entry in pending.entries) {
      resolved[entry.key] = await _resolveCardDisplay(entry.value);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = _messages.map((message) {
        if (message.cards.isEmpty) {
          return message;
        }
        var touched = false;
        final cards = message.cards.map((card) {
          final hit = resolved['${card.kind.name}:${card.id}'];
          if (hit == null ||
              (hit.name == card.name && hit.faceUrl == card.faceUrl)) {
            return card;
          }
          touched = true;
          return hit;
        }).toList(growable: false);
        if (!touched) {
          return message;
        }
        return AiAssistantMessage(
          role: message.role,
          time: message.time,
          text: message.text,
          files: message.files,
          cards: cards,
          outputKind: message.outputKind,
          summary: message.summary,
          analysis: message.analysis,
          code: message.code,
          serverId: message.serverId,
          capability: message.capability,
          status: message.status,
          imageUrl: message.imageUrl,
          failed: message.failed,
        );
      }).toList();
      if (_searching) {
        _applyMatches();
      }
    });
  }

  Future<AiAssistantCardRef> _resolveCardDisplay(AiAssistantCardRef card) async {
    if (card.kind == AiAssistantCardKind.friend) {
      return _resolveFriendCard(card);
    }
    return _resolveGroupCard(card);
  }

  Future<AiAssistantCardRef> _resolveFriendCard(AiAssistantCardRef card) async {
    final userId = card.id.trim();
    if (userId.isEmpty) {
      return card;
    }
    await UserProfileLocalService.instance.read(userId);
    final conversation = await _lookupConversation(
      userId: userId,
      groupId: '',
    );
    final name = UserDisplayProfile.name(
      userId: userId,
      conversationShowName: conversation?.showName,
    ).trim();
    final face = UserDisplayProfile.avatar(
      userId: userId,
      fallbackIm: (conversation?.faceUrl ?? '').trim().isNotEmpty
          ? conversation!.faceUrl
          : card.faceUrl,
    ).trim();
    final fallback = card.name.trim();
    return AiAssistantCardRef(
      kind: AiAssistantCardKind.friend,
      id: userId,
      name: name.isNotEmpty
          ? name
          : (fallback.isNotEmpty ? fallback : userId),
      faceUrl: face.isNotEmpty ? face : card.faceUrl,
    );
  }

  Future<AiAssistantCardRef> _resolveGroupCard(AiAssistantCardRef card) async {
    final groupId = card.id.trim();
    if (groupId.isEmpty) {
      return card;
    }
    final conversation = await _lookupConversation(
      userId: '',
      groupId: groupId,
    );
    final record = await GroupLocalStore.instance.read(groupId: groupId);
    var name = '';
    var face = '';
    if (conversation != null) {
      name = GroupDisplayResolver.resolveShowName(
        conversation: conversation,
        localGroupName: record?.groupName,
        allowAliasFallback: false,
      ).trim();
      face = GroupDisplayResolver.resolveFaceUrl(
        conversation: conversation,
      ).trim();
    }
    if (name.isEmpty) {
      final groupName = (record?.groupName ?? '').trim();
      if (groupName.isNotEmpty &&
          !GroupDisplayResolver.looksLikeGroupIdLabel(
            groupName,
            groupId: groupId,
          )) {
        name = groupName;
      }
    }
    if (face.isEmpty) {
      face = (record?.avatarUrl ?? '').trim();
    }
    if (name.isEmpty) {
      final existing = card.name.trim();
      if (existing.isNotEmpty &&
          !GroupDisplayResolver.looksLikeGroupIdLabel(
            existing,
            groupId: groupId,
          )) {
        name = existing;
      }
    }
    if (name.isEmpty) {
      name = ChatIdFormat.displayGroupAlias(
        card.name,
        groupIdFallback: groupId,
      );
    }
    if (name.isEmpty) {
      name = card.name.trim().isNotEmpty ? card.name.trim() : groupId;
    }
    return AiAssistantCardRef(
      kind: AiAssistantCardKind.group,
      id: groupId,
      name: name,
      faceUrl: face.isNotEmpty ? face : card.faceUrl,
    );
  }

  Future<void> _onUserFileTap(AiAssistantFileRef file) async {
    if (_canShowUserImage(file, _fileCache) ||
        file.kind == AiAssistantFileKind.image) {
      await _previewAiImage(
        bytes: file.bytes ?? _fileCache[(file.fileId ?? '').trim()],
        fileId: file.fileId,
        localPath: file.localPath,
      );
      return;
    }
    if (kIsWeb) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '当前暂不支持用系统打开文件',
        zhHant: '目前暫不支援用系統開啟檔案',
        en: 'Opening files with the system is not supported here.',
        ja: 'ここではシステムでファイルを開けません。',
        ko: '여기서는 시스템으로 파일을 열 수 없습니다.',
      ));
      return;
    }
    var path = (file.localPath ?? '').trim();
    if (path.isEmpty || !File(path).existsSync()) {
      path = '';
      var data = file.bytes;
      final id = (file.fileId ?? '').trim();
      if ((data == null || data.isEmpty) && id.isNotEmpty) {
        data = _fileCache[id];
      }
      if ((data == null || data.isEmpty) && id.isNotEmpty) {
        await _ensureFileBytes(id);
        data = _fileCache[id];
      }
      final local = (file.localPath ?? '').trim();
      if ((data == null || data.isEmpty) && local.isNotEmpty) {
        try {
          data = await File(local).readAsBytes();
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      if (data == null || data.isEmpty) {
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '文件无法打开',
          zhHant: '檔案無法打開',
          en: 'Unable to open the file.',
          ja: 'ファイルを開けません。',
          ko: '파일을 열 수 없습니다.',
        ));
        return;
      }
      try {
        final dir = await getTemporaryDirectory();
        final mime = file.mimeType ?? AiAssistantUploadMime.sniffMime(data);
        final name = AiAssistantUploadMime.ensureFileName(file.name, mime);
        final out = File('${dir.path}/$name');
        await out.writeAsBytes(data, flush: true);
        path = out.path;
      } catch (_) {
        path = '';
      }
    }
    if (!mounted) {
      return;
    }
    if (path.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '文件无法打开',
        zhHant: '檔案無法打開',
        en: 'Unable to open the file.',
        ja: 'ファイルを開けません。',
        ko: '파일을 열 수 없습니다.',
      ));
      return;
    }
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done && mounted) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '无法打开此类型文件',
        zhHant: '無法打開此類型文件',
        en: 'Unable to open this file type.',
        ja: 'この種類のファイルを開けません。',
        ko: '이 유형의 파일을 열 수 없습니다.',
      ));
    }
  }

  Future<void> _previewAiImage({
    Uint8List? bytes,
    String? fileId,
    String? localPath,
    String? imageUrl,
  }) async {
    var data = bytes;
    final id = (fileId ?? '').trim().isNotEmpty
        ? fileId!.trim()
        : (AiAssistantApi.fileIdFromUrl(imageUrl ?? '') ?? '');
    if ((data == null || data.isEmpty) && id.isNotEmpty) {
      await _ensureFileBytes(id, silent: true);
      data = _fileCache[id];
    }
    final path = (localPath ?? '').trim();
    if ((data == null || data.isEmpty) && !kIsWeb && path.isNotEmpty) {
      try {
        data = await File(path).readAsBytes();
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    if (data == null || data.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '图片加载失败',
        zhHant: '圖片載入失敗',
        en: 'Failed to load image.',
        ja: '画像の読み込みに失敗しました。',
        ko: '이미지를 불러오지 못했습니다.',
      ));
      return;
    }
    await _openAiImagePreview(data, localPath: path);
  }

  Future<void> _openAiImagePreview(
    Uint8List bytes, {
    String localPath = '',
  }) async {
    Future<void> save() => _saveAiImage(bytes);
    if (!kIsWeb && PlatformUtils().isWinMacDesktop) {
      var path = localPath;
      if (path.isEmpty || !File(path).existsSync()) {
        try {
          final dir = await getTemporaryDirectory();
          final mime = AiAssistantUploadMime.sniffMime(bytes) ?? 'image/png';
          final name = AiAssistantUploadMime.ensureFileName(
            'ai_assistant_${DateTime.now().millisecondsSinceEpoch}',
            mime,
          );
          final file = File('${dir.path}/$name');
          await file.writeAsBytes(bytes, flush: true);
          path = file.path;
        } catch (_) {
          path = '';
        }
      }
      if (path.isNotEmpty) {
        final opened = await DesktopMediaPreviewHook.tryOpen(
          DesktopMediaPreviewPayload.image(
            source: 'ai_assistant',
            localPath: path,
            downloadOnly: true,
          ),
        );
        if (opened) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
    }
    await pushMediaPreview(
      context: context,
      enableGestureBack: false,
      child: ImageScreen(
        imageProvider: MemoryImage(bytes),
        heroTag: '',
        enableHero: false,
        downloadOnly: true,
        downloadFn: save,
        fitTallImagesToScreenWidth: false,
      ),
    );
  }

  Future<void> _saveAiImage(Uint8List bytes) async {
    if (kIsWeb) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '当前暂不支持保存图片',
        zhHant: '目前暫不支援儲存圖片',
        en: 'Saving images is not supported here.',
        ja: 'ここでは画像を保存できません。',
        ko: '여기서는 이미지를 저장할 수 없습니다.',
      ));
      throw StateError('unsupported');
    }
    final granted = await PermissionGuard.photosForSave(context);
    if (!granted) {
      if (mounted) {
        MediaPreviewSaveNotice.show(context, success: false);
      }
      throw StateError('permission_denied');
    }
    final saved = await GallerySaveToPhotos.saveBytes(
      bytes,
      name: 'ai_assistant_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (mounted) {
      MediaPreviewSaveNotice.show(context, success: saved);
    }
    if (!saved) {
      throw StateError('save_failed');
    }
  }

  Future<void> _dismissWelcome() async {
    setState(() {
      _welcomeVisible = false;
    });
    if (_userId.isEmpty) {
      return;
    }
    await AiAssistantWelcomeStore.dismiss(_userId);
  }

  Future<void> _dismissGuide() async {
    if (!_guideVisible) {
      return;
    }
    setState(() {
      _guideVisible = false;
    });
    if (_userId.isEmpty) {
      return;
    }
    await AiAssistantWelcomeStore.dismissGuide(_userId);
  }

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  void _showComingSoon(String title) {
    final i18n = AppI18n.of(context);
    ToastUtils.toast(i18n.format(
      zhHans: '{title}即将推出',
      zhHant: '{title}即將推出',
      en: '{title} is coming soon.',
      ja: '{title}は近日公開です。',
      ko: '{title}은 곧 제공됩니다.',
      vars: {'title': title},
    ));
  }

  void _toastAlreadyAdded() {
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '已添加',
      zhHant: '已新增',
      en: 'Already added.',
      ja: 'すでに追加されています。',
      ko: '이미 추가되었습니다.',
    ));
  }

  void _toastDraftLimit() {
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '最多添加 9 项',
      zhHant: '最多新增 9 項',
      en: 'You can add up to 9 items.',
      ja: '追加は9件までです。',
      ko: '최대 9개까지 추가할 수 있습니다.',
    ));
  }

  bool _canAcceptDrafts(int extra) {
    if (_drafts.length + extra <= 9) {
      return true;
    }
    _toastDraftLimit();
    return false;
  }

  void _focusInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocus.requestFocus();
      }
    });
  }

  void _addCardDraft(AiAssistantCardRef card) {
    final exists = _drafts.any(
      (item) =>
          item.card != null &&
          item.card!.kind == card.kind &&
          item.card!.id == card.id,
    );
    if (exists) {
      _toastAlreadyAdded();
      return;
    }
    if (!_canAcceptDrafts(1)) {
      return;
    }
    setState(() {
      _drafts.add(AiAssistantDraftItem.card(card));
    });
    _focusInput();
  }

  void _addFileDrafts(List<AiAssistantFileRef> files) {
    if (files.isEmpty) {
      return;
    }
    final room = 9 - _drafts.length;
    if (room <= 0) {
      _toastDraftLimit();
      return;
    }
    final accepted = files.take(room).toList();
    setState(() {
      _drafts.addAll(accepted.map(AiAssistantDraftItem.file));
    });
    if (accepted.length < files.length) {
      _toastDraftLimit();
    }
    _focusInput();
  }

  Future<void> _openMoreSheet() async {
    final i18n = AppI18n.of(context);
    final action = await AppDialog.actionSheet<String>(
      title: '',
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
      actions: [
        AppActionSheetItem(
          text: i18n.t(
            zhHans: '好友名片',
            zhHant: '好友名片',
            en: 'Friend card',
            ja: '友だちの名刺',
            ko: '친구 명함',
          ),
          value: 'friend',
        ),
        AppActionSheetItem(
          text: i18n.t(
            zhHans: '群聊',
            zhHant: '群聊',
            en: 'Group',
            ja: 'グループ',
            ko: '그룹',
          ),
          value: 'group',
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'friend') {
      await _pickFriendCard();
      return;
    }
    if (action == 'group') {
      await _pickGroupCard();
    }
  }

  Future<void> _openOverflowSheet() async {
    final i18n = AppI18n.of(context);
    final action = await AppDialog.actionSheet<String>(
      title: '',
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
      actions: [
        AppActionSheetItem(
          text: i18n.t(
            zhHans: '清空记录',
            zhHant: '清空紀錄',
            en: 'Clear history',
            ja: '履歴を消去',
            ko: '기록 지우기',
          ),
          value: 'clear',
          destructive: true,
        ),
      ],
    );
    if (!mounted || action != 'clear') {
      return;
    }
    unawaited(_clearRecords());
  }

  Future<void> _copyMessage(AiAssistantMessage message) async {
    final text = AiAssistantSearch.copyText(message);
    if (text.isEmpty) {
      return;
    }
    final i18n = AppI18n.of(context);
    final action = await AppDialog.actionSheet<String>(
      title: '',
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
      actions: [
        AppActionSheetItem(
          text: i18n.t(
            zhHans: '复制',
            zhHant: '複製',
            en: 'Copy',
            ja: 'コピー',
            ko: '복사',
          ),
          value: 'copy',
        ),
      ],
    );
    if (!mounted || action != 'copy') {
      return;
    }
    await ClipboardGuard.copy(text);
    ToastUtils.toast(i18n.t(
      zhHans: '已复制',
      zhHant: '已複製',
      en: 'Copied',
      ja: 'コピーしました',
      ko: '복사했습니다',
    ));
  }

  Future<void> _clearRecords() async {
    _streamCancel?.cancel('clear');
    _streamCancel = null;
    try {
      await AiAssistantApi.instance.deleteHistory();
    } on AiAssistantException catch (error) {
      if (!mounted) {
        return;
      }
      _toastApiError(error);
      return;
    } catch (_) {
      if (!mounted) {
        return;
      }
      _toastApiError(const AiAssistantException('MAIN_UNAVAILABLE', ''));
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = <AiAssistantMessage>[];
      _replying = false;
      _hasMore = false;
      _nextCursor = null;
      _fileCache.clear();
      _syncKeys();
      if (_searching) {
        _applyMatches();
      }
    });
  }

  void _syncKeys() {
    while (_messageKeys.length < _messages.length) {
      _messageKeys.add(GlobalKey());
    }
    if (_messageKeys.length > _messages.length) {
      _messageKeys.removeRange(_messages.length, _messageKeys.length);
    }
  }

  void _applyMatches() {
    final query = AiAssistantSearch.normalize(_searchController.text);
    _matchIndexes = AiAssistantSearch.matchIndexes(_messages, query);
    if (_activeMatch >= _matchIndexes.length) {
      _activeMatch = 0;
    }
  }

  void _rebuildMatches() {
    setState(_applyMatches);
  }

  void _jumpToActive({int attempt = 0}) {
    if (_matchIndexes.isEmpty) {
      return;
    }
    if (_activeMatch < 0 || _activeMatch >= _matchIndexes.length) {
      return;
    }
    final index = _matchIndexes[_activeMatch];
    if (index < 0 || index >= _messageKeys.length) {
      return;
    }
    final target = _messageKeys[index].currentContext;
    if (target == null) {
      if (attempt < 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _jumpToActive(attempt: attempt + 1);
          }
        });
      }
      return;
    }
    Scrollable.ensureVisible(
      target,
      alignment: 0.2,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _openSearch() {
    setState(() {
      _searching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocus.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _searchController.clear();
      _matchIndexes = <int>[];
      _activeMatch = 0;
    });
  }

  void _stepMatch(int delta) {
    final total = _matchIndexes.length;
    if (total == 0) {
      return;
    }
    setState(() {
      _activeMatch = (_activeMatch + delta + total) % total;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _jumpToActive();
      }
    });
  }

  String get _searchQuery => _searching ? _searchController.text : '';

  void _selectTool(String id) {
    if (id == 'summarize') {
      if (_selectedTool == 'summarize') {
        setState(() {
          _selectedTool = null;
        });
        return;
      }
      unawaited(_pickSummarizeConversation());
      return;
    }
    setState(() {
      _selectedTool = _selectedTool == id ? null : id;
    });
    _focusInput();
  }

  Future<void> _pickSummarizeConversation() async {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final target = await ConversationSharePickerPage.open(
      context,
      theme: theme,
    );
    if (!mounted || target == null) {
      return;
    }
    final card = await _cardFromShareTarget(target);
    if (!mounted || card == null) {
      return;
    }
    setState(() {
      _selectedTool = 'summarize';
    });
    _addCardDraft(card);
  }

  Future<AiAssistantCardRef?> _cardFromShareTarget(
    ConversationShareTarget target,
  ) async {
    final userId = target.userID.trim();
    if (userId.isNotEmpty) {
      return _resolveFriendCard(
        AiAssistantCardRef(
          kind: AiAssistantCardKind.friend,
          id: userId,
          name: userId,
        ),
      );
    }
    final groupId = target.groupID.trim();
    if (groupId.isEmpty) {
      return null;
    }
    return _resolveGroupCard(
      AiAssistantCardRef(
        kind: AiAssistantCardKind.group,
        id: groupId,
        name: groupId,
      ),
    );
  }

  Future<V2TimConversation?> _lookupConversation({
    required String userId,
    required String groupId,
  }) async {
    final store = ConversationLocalStore.instance;
    if (userId.isNotEmpty) {
      final raw = ChatIdFormat.rawUserUid(userId);
      final ids = <String>{
        'c2c_$userId',
        userId,
        if (raw.isNotEmpty) 'c2c_$raw',
        if (raw.isNotEmpty) raw,
      };
      for (final id in ids) {
        final hit = await store.conversationById(id);
        if (hit != null) {
          return hit;
        }
      }
      return null;
    }
    if (groupId.isNotEmpty) {
      final normalized = ChatIdFormat.normalizeGroupId(groupId);
      final ids = <String>{
        'group_$groupId',
        groupId,
        if (normalized.isNotEmpty) 'group_$normalized',
        if (normalized.isNotEmpty) normalized,
      };
      for (final id in ids) {
        final hit = await store.conversationById(id);
        if (hit != null) {
          return hit;
        }
      }
    }
    return null;
  }

  String _composerHint(AppI18n i18n) {
    switch (_selectedTool) {
      case 'summarize':
        return i18n.t(
          zhHans: '补充希望在总结中突出的内容…',
          zhHant: '補充希望在總結中突出的內容…',
          en: 'Add what to highlight in the summary...',
          ja: '要約で強調したい点を追加…',
          ko: '요약에서 강조할 내용을 추가하세요…',
        );
      case 'image':
        return i18n.t(
          zhHans: '描述你想生成的图片…',
          zhHant: '描述你想生成的圖片…',
          en: 'Describe the image you want...',
          ja: '作りたい画像を説明してください…',
          ko: '만들고 싶은 이미지를 설명해 주세요…',
        );
      case 'analyze':
        return i18n.t(
          zhHans: '补充希望在文件中查找的内容…',
          zhHant: '補充希望在檔案中查找的內容…',
          en: 'Add what to look for in the file...',
          ja: 'ファイルで探したい内容を追加…',
          ko: '파일에서 찾을 내용을 추가하세요…',
        );
      case 'write':
        return i18n.t(
          zhHans: '主题、语气和用途…',
          zhHant: '主題、語氣和用途…',
          en: 'Topic, tone, and where it will be used...',
          ja: 'テーマ、トーン、使用場面…',
          ko: '주제, 말투, 사용처…',
        );
      default:
        return i18n.t(
          zhHans: '问 99ChatAI …',
          zhHant: '問 99ChatAI …',
          en: 'Ask 99ChatAI ...',
          ja: '99ChatAI に質問…',
          ko: '99ChatAI에게 물어보세요…',
        );
    }
  }

  Future<void> _pickFriendCard() async {
    final userId = await pickContactCardUser(context);
    if (!mounted) {
      return;
    }
    final id = userId?.trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    final card = await _resolveFriendCard(
      AiAssistantCardRef(
        kind: AiAssistantCardKind.friend,
        id: id,
        name: id,
      ),
    );
    if (!mounted) {
      return;
    }
    _addCardDraft(card);
  }

  Future<void> _pickGroupCard() async {
    final group = await Navigator.of(context).push<V2TimGroupInfo>(
      AppMaterialPageRoute(
        builder: (context) => ForwardSelectGroupPage(
          onTapItem: (groupInfo, conversation) {
            Navigator.pop(context, groupInfo);
          },
        ),
      ),
    );
    if (!mounted || group == null) {
      return;
    }
    final id = group.groupID.trim();
    if (id.isEmpty) {
      return;
    }
    final pickedName = group.groupName?.trim() ?? '';
    final card = await _resolveGroupCard(
      AiAssistantCardRef(
        kind: AiAssistantCardKind.group,
        id: id,
        name: pickedName.isNotEmpty ? pickedName : id,
        faceUrl: group.faceUrl ?? '',
      ),
    );
    if (!mounted) {
      return;
    }
    _addCardDraft(card);
  }

  Future<void> _pickImages() async {
    final media = await SystemMediaPicker.pickMultiple(allowVideo: false);
    if (!mounted || media.isEmpty) {
      return;
    }
    _addFileDrafts(
      media.map((item) {
        var name = (item.name ?? '').trim();
        if (name.isEmpty) {
          final path = item.path.trim();
          name = path.isEmpty ? 'image' : path.split(RegExp(r'[\\/]')).last;
        }
        var kind = AiAssistantFileKinds.fromName(name);
        if (item.isVideo && kind == AiAssistantFileKind.unknown) {
          kind = AiAssistantFileKind.video;
        }
        final rawBytes = item.fileBytes;
        final bytes = rawBytes == null || rawBytes.isEmpty
            ? null
            : Uint8List.fromList(rawBytes);
        final mime = (item.mimeType ?? '').trim();
        final resolvedMime =
            mime.isNotEmpty ? mime : AiAssistantUploadMime.fromName(name);
        return AiAssistantFileRef(
          name: AiAssistantUploadMime.ensureFileName(name, resolvedMime),
          sizeLabel: AiAssistantDraftFormats.bytes(bytes?.length),
          kind: kind,
          localPath: item.path.isEmpty ? null : item.path,
          bytes: bytes,
          mimeType: resolvedMime,
          sizeBytes: bytes?.length,
        );
      }).toList(),
    );
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: kIsWeb,
    );
    if (!mounted || result == null) {
      return;
    }
    final files = <AiAssistantFileRef>[];
    for (final file in result.files) {
      var name = file.name.trim();
      final path = file.path?.trim() ?? '';
      final bytes = file.bytes;
      if (name.isEmpty && path.isEmpty && (bytes == null || bytes.isEmpty)) {
        continue;
      }
      if (name.isEmpty) {
        name = path.split(RegExp(r'[\\/]')).last;
      }
      final mime = AiAssistantUploadMime.fromName(name);
      files.add(
        AiAssistantFileRef(
          name: AiAssistantUploadMime.ensureFileName(name, mime),
          sizeLabel: AiAssistantDraftFormats.bytes(file.size),
          kind: AiAssistantFileKinds.fromName(name),
          localPath: path.isEmpty ? null : path,
          bytes: bytes,
          mimeType: mime,
          sizeBytes: file.size > 0 ? file.size : bytes?.length,
        ),
      );
    }
    _addFileDrafts(files);
  }

  String _nowTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _scrollToEnd() {
    void jumpIfReady() {
      if (!_listController.hasClients) {
        return;
      }
      if (_listController.offset > 0) {
        _listController.jumpTo(0);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpIfReady();
    });
  }

  void _replaceLastMessage(AiAssistantMessage message) {
    if (_messages.isEmpty) {
      _messages.add(message);
    } else {
      _messages[_messages.length - 1] = message;
    }
    _syncKeys();
    if (_searching) {
      _applyMatches();
    }
  }

  bool _isActiveToken(CancelToken token) {
    return mounted && identical(_streamCancel, token) && !token.isCancelled;
  }

  void _replaceLastUserFiles(List<AiAssistantFileRef> files) {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role != AiAssistantRole.user) {
        continue;
      }
      final old = _messages[i];
      _messages[i] = AiAssistantMessage(
        role: old.role,
        time: old.time,
        text: old.text,
        files: files,
        cards: old.cards,
        serverId: old.serverId,
        capability: old.capability,
        status: old.status,
      );
      return;
    }
  }

  void _bindServerIds({String? userMessageId, String? assistantMessageId}) {
    final userId = (userMessageId ?? '').trim();
    final assistantId = (assistantMessageId ?? '').trim();
    if (userId.isNotEmpty) {
      for (var i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].role != AiAssistantRole.user) {
          continue;
        }
        final old = _messages[i];
        _messages[i] = AiAssistantMessage(
          role: old.role,
          time: old.time,
          text: old.text,
          files: old.files,
          cards: old.cards,
          serverId: userId,
          capability: old.capability,
          status: old.status,
        );
        break;
      }
    }
    if (assistantId.isEmpty || _messages.isEmpty) {
      return;
    }
    final last = _messages.last;
    if (last.role != AiAssistantRole.assistant) {
      return;
    }
    _messages[_messages.length - 1] = AiAssistantMessage(
      role: last.role,
      time: last.time,
      text: last.text,
      files: last.files,
      cards: last.cards,
      outputKind: last.outputKind,
      summary: last.summary,
      analysis: last.analysis,
      code: last.code,
      serverId: assistantId,
      capability: last.capability,
      status: last.status,
      imageUrl: last.imageUrl,
      failed: last.failed,
    );
  }

  void _rollbackOptimisticTurn() {
    if (_messages.isNotEmpty &&
        _messages.last.role == AiAssistantRole.assistant &&
        _messages.last.outputKind == AiAssistantOutputKind.thinking) {
      _messages.removeLast();
    }
    if (_messages.isNotEmpty &&
        _messages.last.role == AiAssistantRole.user &&
        (_messages.last.serverId == null || _messages.last.serverId!.isEmpty)) {
      _messages.removeLast();
    }
    _syncKeys();
    if (_searching) {
      _applyMatches();
    }
  }

  void _failLastAssistant(AiAssistantException error) {
    final last = _messages.isEmpty ? null : _messages.last;
    final fromAssistant = last?.role == AiAssistantRole.assistant;
    _replaceLastMessage(
      AiAssistantMessage(
        role: AiAssistantRole.assistant,
        time: _nowTime(),
        outputKind: AiAssistantOutputKind.text,
        text: AiAssistantErrorText.localize(
          AppI18n.of(context),
          code: error.code,
          fallback: error.message,
        ),
        serverId: fromAssistant ? last?.serverId : null,
        capability: fromAssistant ? last?.capability : null,
        status: 'failed',
        failed: true,
      ),
    );
  }

  void _finishInterruptedStream() {
    _streamCancel?.cancel('interrupt');
  }

  Future<void> _beginAssistantReply(AiAssistantSendPlan plan) async {
    final token = _streamCancel;
    if (token == null) {
      return;
    }
    final attachFiles = plan.capability == AiAssistantSendPlanner.chat ||
        plan.capability == AiAssistantSendPlanner.file ||
        plan.capability == AiAssistantSendPlanner.image;
    var uploaded = attachFiles ? plan.files : const <AiAssistantFileRef>[];
    try {
      if (attachFiles && plan.files.isNotEmpty) {
        final next = <AiAssistantFileRef>[];
        for (final file in plan.files) {
          if (!_isActiveToken(token)) {
            return;
          }
          final existing = (file.fileId ?? '').trim();
          if (existing.isNotEmpty) {
            next.add(file);
            continue;
          }
          final saved = await AiAssistantApi.instance.uploadFile(
            fileName: file.name,
            path: file.localPath,
            bytes: file.bytes,
            mimeType: file.mimeType,
          );
          next.add(
            AiAssistantFileRef(
              name: saved.fileName.isNotEmpty ? saved.fileName : file.name,
              sizeLabel: file.sizeLabel,
              kind: file.kind,
              localPath: file.localPath,
              fileId: saved.fileId,
              bytes: file.bytes,
              mimeType: saved.contentType.isNotEmpty
                  ? saved.contentType
                  : file.mimeType,
              sizeBytes: saved.sizeBytes > 0 ? saved.sizeBytes : file.sizeBytes,
            ),
          );
        }
        uploaded = next;
        if (!_isActiveToken(token)) {
          return;
        }
        setState(() {
          _replaceLastUserFiles(uploaded);
        });
      }
      final fileIds = attachFiles
          ? uploaded
              .map((file) => (file.fileId ?? '').trim())
              .where((id) => id.isNotEmpty)
              .toList()
          : const <String>[];
      var assembled = '';
      await for (final event in AiAssistantApi.instance.stream(
        capability: plan.capability == AiAssistantSendPlanner.chat
            ? null
            : plan.capability,
        content: plan.content,
        analyze: plan.analyze,
        fileIds: fileIds.isEmpty ? null : fileIds,
        cancelToken: token,
      )) {
        if (!_isActiveToken(token)) {
          return;
        }
        switch (event.kind) {
          case AiAssistantStreamKind.meta:
            setState(() {
              _bindServerIds(
                userMessageId: event.userMessageId,
                assistantMessageId: event.assistantMessageId,
              );
            });
            break;
          case AiAssistantStreamKind.delta:
            assembled += event.text;
            setState(() {
              final last = _messages.isEmpty ? null : _messages.last;
              _replaceLastMessage(
                AiAssistantMessage(
                  role: AiAssistantRole.assistant,
                  time: '',
                  outputKind: AiAssistantOutputKind.text,
                  text: assembled,
                  serverId: last?.serverId,
                  capability: last?.capability ?? plan.capability,
                  status: 'streaming',
                ),
              );
            });
            _scrollToEnd();
            break;
          case AiAssistantStreamKind.done:
            final imageUrl = event.imageUrl.trim();
            setState(() {
              final last = _messages.isEmpty ? null : _messages.last;
              _replying = false;
              _replaceLastMessage(
                AiAssistantMessage(
                  role: AiAssistantRole.assistant,
                  time: _nowTime(),
                  outputKind: imageUrl.isEmpty
                      ? AiAssistantOutputKind.text
                      : AiAssistantOutputKind.image,
                  text: assembled.isEmpty ? last?.text : assembled,
                  serverId: event.assistantMessageId ?? last?.serverId,
                  capability: last?.capability ?? plan.capability,
                  status: 'complete',
                  imageUrl: imageUrl.isEmpty ? last?.imageUrl : imageUrl,
                ),
              );
            });
            _scrollToEnd();
            if (imageUrl.isNotEmpty) {
              final id = AiAssistantApi.fileIdFromUrl(imageUrl);
              if (id != null) {
                unawaited(_ensureFileBytes(id, silent: true));
              }
            }
            break;
          case AiAssistantStreamKind.error:
            final error = AiAssistantException(event.code, event.message);
            setState(() {
              _replying = false;
              _failLastAssistant(error);
            });
            _toastApiError(error);
            _scrollToEnd();
            break;
        }
      }
      if (_isActiveToken(token) && _replying) {
        setState(() {
          _replying = false;
          if (_messages.isNotEmpty &&
              _messages.last.outputKind == AiAssistantOutputKind.thinking) {
            _failLastAssistant(
              const AiAssistantException('MAIN_UNAVAILABLE', ''),
            );
          }
        });
      }
    } on AiAssistantException catch (error) {
      if (!_isActiveToken(token) && error.cancelled) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _replying = false;
        if (error.code == 'CHAT_BUSY') {
          _rollbackOptimisticTurn();
        } else if (!error.cancelled) {
          _failLastAssistant(error);
        }
      });
      _toastApiError(error);
    } catch (_) {
      if (!_isActiveToken(token)) {
        return;
      }
      setState(() {
        _replying = false;
        _failLastAssistant(const AiAssistantException('MAIN_UNAVAILABLE', ''));
      });
      _toastApiError(const AiAssistantException('MAIN_UNAVAILABLE', ''));
    }
  }

  void _stopAssistantReply() {
    _streamCancel?.cancel('stop');
    setState(() {
      _replying = false;
      if (_messages.isEmpty) {
        return;
      }
      final last = _messages.last;
      if (last.outputKind == AiAssistantOutputKind.thinking) {
        _messages.removeLast();
        _syncKeys();
        if (_searching) {
          _applyMatches();
        }
        return;
      }
      if (last.outputKind == AiAssistantOutputKind.text && last.time.isEmpty) {
        _replaceLastMessage(
          AiAssistantMessage(
            role: AiAssistantRole.assistant,
            time: _nowTime(),
            outputKind: AiAssistantOutputKind.text,
            text: last.text,
            serverId: last.serverId,
            capability: last.capability,
            status: last.status,
            imageUrl: last.imageUrl,
          ),
        );
      }
    });
  }

  void _sendComposer() {
    if (_replying || _hasStreamingHistory()) {
      if (_hasStreamingHistory()) {
        _toastApiError(const AiAssistantException('CHAT_BUSY', ''));
      }
      return;
    }
    final text = _inputController.text.trim();
    final cards = _drafts
        .where((item) => item.card != null)
        .map((item) => item.card!)
        .toList();
    final files = _drafts
        .where((item) => item.file != null)
        .map((item) => item.file!)
        .toList();
    final planned = AiAssistantSendPlanner.plan(
      tool: _selectedTool,
      text: text,
      cards: cards,
      files: files,
    );
    if (planned is AiAssistantSendError) {
      ToastUtils.toast(planned.localize(AppI18n.of(context)));
      return;
    }
    final plan = planned as AiAssistantSendPlan;
    _streamCancel?.cancel('replace');
    _streamCancel = CancelToken();
    final userMessage = AiAssistantMessage(
      role: AiAssistantRole.user,
      time: _nowTime(),
      text: plan.displayText.isEmpty ? null : plan.displayText,
      cards: plan.cards,
      files: plan.files,
      capability: plan.capability,
    );
    setState(() {
      if (_messages.isNotEmpty &&
          _messages.last.outputKind == AiAssistantOutputKind.thinking) {
        _messages.insert(_messages.length - 1, userMessage);
      } else {
        _messages.add(userMessage);
      }
      _messages.add(
        AiAssistantMessage(
          role: AiAssistantRole.assistant,
          time: '',
          outputKind: AiAssistantOutputKind.thinking,
          capability: plan.capability,
        ),
      );
      _drafts.clear();
      _inputController.clear();
      _selectedTool = null;
      _replying = true;
      _syncKeys();
      if (_searching) {
        _applyMatches();
      }
    });
    _scrollToEnd();
    unawaited(_beginAssistantReply(plan));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final i18n = AppI18n.of(context);
    final headerBg = _AiPalette.headerBg(dark);
    final bg = _AiPalette.canvasBg(dark);
    final overlay = immersiveOverlayForColors(
      statusBarBackground: headerBg,
      navigationBarBackground: bg,
    );
    final media = MediaQuery.of(context);
    final bottomPad =
        math.max(10.0, media.padding.bottom) + media.viewInsets.bottom;

    _syncKeys();
    return Consumer<LoginUserInfo>(
      builder: (context, login, _) {
        final info = login.loginUserInfo;
        final nick = info.nickName?.trim() ?? '';
        final uid = (info.userID ?? '').trim().isNotEmpty
            ? info.userID!.trim()
            : ChatIdFormat.rawUserUid(
                ContactSocialCacheStore.safeLoginUserId(),
              );
        final showName = nick.isNotEmpty ? nick : (uid.isNotEmpty ? uid : '99');
        final cachedSelf = UserAvatarHelper.usableAvatarOrEmpty(_selfAvatarUrl);
        final faceUrl = cachedSelf.isNotEmpty
            ? _selfAvatarUrl
            : UserDisplayProfile.avatar(
                userId: uid,
                fallbackIm: info.faceUrl,
                isSelf: true,
              );

        final query = _searchQuery;
        final searchNeedle = AiAssistantSearch.normalize(_searchController.text);
        final matchTotal = _matchIndexes.length;
        final matchLabel = matchTotal == 0
            ? '0/0'
            : '${_activeMatch + 1}/$matchTotal';
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: PopScope(
            canPop: !_searching,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _searching) {
                _closeSearch();
              }
            },
            child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleSpacing: 0,
              leadingWidth: 48,
              backgroundColor: headerBg,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: overlay,
              leading: IconButton(
                icon: Icon(
                  _searching
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                ),
                color: _AiPalette.brand(dark),
                onPressed: () {
                  if (_searching) {
                    _closeSearch();
                    return;
                  }
                  Navigator.of(context).pop();
                },
              ),
              title: _searching
                  ? SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        autofocus: true,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        style: TextStyle(
                          color: _AiPalette.primary(dark),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: i18n.t(
                            zhHans: '搜索此对话',
                            zhHant: '搜尋此對話',
                            en: 'Search this chat',
                            ja: 'このチャットを検索',
                            ko: '이 대화 검색',
                          ),
                          hintStyle: TextStyle(
                            color: _AiPalette.secondary(dark),
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: _AiPalette.inputBg(dark),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: _AiPalette.line(dark),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: _AiPalette.line(dark),
                            ),
                          ),
                        ),
                        onChanged: (_) {
                          _rebuildMatches();
                          if (_matchIndexes.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _jumpToActive();
                              }
                            });
                          }
                        },
                      ),
                    )
                  : Row(
                      children: [
                        const _AssistantAvatar(size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '99ChatAI',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _AiPalette.primary(dark),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                i18n.t(
                                  zhHans: '智能助手 · 更聪明的聊天体验',
                                  zhHant: '智慧助手 · 更聰明的聊天體驗',
                                  en: 'Smart assistant · A smarter chat experience',
                                  ja: 'スマートアシスタント · より賢いチャット体験',
                                  ko: '스마트 어시스턴트 · 더 똑똑한 채팅 경험',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _AiPalette.secondary(dark),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
              actions: [
                if (_searching && searchNeedle.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Center(
                      child: Text(
                        matchLabel,
                        style: TextStyle(
                          color: _AiPalette.secondary(dark),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: matchTotal == 0
                          ? _AiPalette.secondary(dark)
                          : _AiPalette.primary(dark),
                    ),
                    onPressed: matchTotal == 0 ? null : () => _stepMatch(-1),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: matchTotal == 0
                          ? _AiPalette.secondary(dark)
                          : _AiPalette.primary(dark),
                    ),
                    onPressed: matchTotal == 0 ? null : () => _stepMatch(1),
                  ),
                ],
                if (!_searching)
                  IconButton(
                    tooltip: i18n.t(
                      zhHans: '搜索',
                      zhHant: '搜尋',
                      en: 'Search',
                      ja: '検索',
                      ko: '검색',
                    ),
                    icon: Icon(
                      Icons.search_rounded,
                      color: _AiPalette.primary(dark),
                    ),
                    onPressed: _openSearch,
                  ),
                IconButton(
                  tooltip: i18n.t(
                    zhHans: '更多',
                    zhHant: '更多',
                    en: 'More',
                    ja: 'その他',
                    ko: '더보기',
                  ),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: _AiPalette.primary(dark),
                  ),
                  onPressed: () => unawaited(_openOverflowSheet()),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(0.6),
                child: Container(
                  height: 0.6,
                  color: _AiPalette.line(dark),
                ),
              ),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: _AiCanvasBackdrop(dark: dark),
                  ),
                ),
                Column(
              children: [
                Expanded(
                  child: _historyLoaded && _messages.isEmpty
                      ? _EmptyChatArt(
                          dark: dark,
                          i18n: i18n,
                          onStart: _focusInput,
                        )
                      : ListView(
                    controller: _listController,
                    reverse: true,
                    cacheExtent: _searching && searchNeedle.isNotEmpty
                        ? double.infinity
                        : null,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      ..._messages.asMap().entries.toList().reversed.map((entry) {
                        final index = entry.key;
                        final message = entry.value;
                        return KeyedSubtree(
                          key: _messageKeys[index],
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: message.role == AiAssistantRole.user
                                ? _UserBubble(
                                    dark: dark,
                                    message: message,
                                    faceUrl: faceUrl,
                                    showName: showName,
                                    ownerId: uid,
                                    fileCache: _fileCache,
                                    onCardTap: (card) => unawaited(
                                      ChatIdMentionNavigator.open(
                                        context,
                                        card.id,
                                      ),
                                    ),
                                    onFileTap: (file) =>
                                        unawaited(_onUserFileTap(file)),
                                    query: query,
                                    onLongPress: () =>
                                        unawaited(_copyMessage(message)),
                                  )
                                : _AssistantBubble(
                                    dark: dark,
                                    i18n: i18n,
                                    message: message,
                                    imageBytes: _fileCache[
                                        AiAssistantApi.fileIdFromUrl(
                                              message.imageUrl,
                                            ) ??
                                            ''],
                                    fileCache: _fileCache,
                                    onNeedFile: (id) => unawaited(
                                      _ensureFileBytes(id, silent: true),
                                    ),
                                    onComingSoon: _showComingSoon,
                                    onImageTap: () => unawaited(
                                      _previewAiImage(
                                        bytes: _fileCache[
                                            AiAssistantApi.fileIdFromUrl(
                                                  message.imageUrl,
                                                ) ??
                                                ''],
                                        imageUrl: message.imageUrl,
                                      ),
                                    ),
                                    onMarkdownImage: (raw) => unawaited(
                                      _previewAiImage(
                                        bytes: _fileCache[
                                            AiAssistantApi.fileIdFromUrl(
                                                  raw,
                                                ) ??
                                                ''],
                                        imageUrl: raw,
                                      ),
                                    ),
                                    query: query,
                                    onLongPress: () =>
                                        unawaited(_copyMessage(message)),
                                  ),
                          ),
                        );
                      }),
                      if (_welcomeVisible) ...[
                        const SizedBox(height: 12),
                        _WelcomeBanner(
                          dark: dark,
                          i18n: i18n,
                          onClose: () => unawaited(_dismissWelcome()),
                        ),
                      ],
                    ],
                  ),
                ),
                _QuickChipBar(
                  dark: dark,
                  i18n: i18n,
                  selectedId: _selectedTool,
                  onSelected: _selectTool,
                ),
                if (_drafts.isNotEmpty)
                  _DraftBar(
                    dark: dark,
                    i18n: i18n,
                    drafts: _drafts,
                    onRemove: (index) {
                      setState(() {
                        _drafts.removeAt(index);
                      });
                    },
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad),
                  child: _InputBar(
                    dark: dark,
                    hint: _composerHint(i18n),
                    controller: _inputController,
                    focusNode: _inputFocus,
                    onAdd: () => unawaited(_openMoreSheet()),
                    onImage: () => unawaited(_pickImages()),
                    onAttach: () => unawaited(_pickAttachments()),
                    onSubmit: _sendComposer,
                    onStop: _stopAssistantReply,
                    replying: _replying,
                  ),
                ),
              ],
            ),
                if (_guideVisible)
                  Positioned.fill(
                    child: _AiFirstGuide(
                      onFinished: () => unawaited(_dismissGuide()),
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

class _AiCanvasBackdrop extends StatelessWidget {
  const _AiCanvasBackdrop({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final top = dark ? const Color(0xFF161A22) : _AiPalette.header;
    final mid = dark ? const Color(0xFF12151C) : _AiPalette.canvas;
    final bottom = dark ? const Color(0xFF101318) : const Color(0xFFE8EEF8);
    final glowA = _AiPalette.accent.withValues(alpha: dark ? 0.16 : 0.14);
    final glowB = _AiPalette.userBubble.withValues(alpha: dark ? 0.12 : 0.10);
    final sparkle = _AiPalette.accent.withValues(alpha: dark ? 0.28 : 0.22);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, mid, bottom],
          stops: const <double>[0, 0.42, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -50,
            child: _AiGlowOrb(size: 220, color: glowA),
          ),
          Positioned(
            top: 180,
            left: -80,
            child: _AiGlowOrb(size: 180, color: glowB),
          ),
          Positioned(
            bottom: 90,
            right: -40,
            child: _AiGlowOrb(size: 160, color: glowA),
          ),
          Positioned(
            top: 72,
            left: 28,
            child: Icon(Icons.auto_awesome, size: 16, color: sparkle),
          ),
          Positioned(
            top: 128,
            right: 36,
            child: Icon(Icons.auto_awesome, size: 12, color: sparkle),
          ),
          Positioned(
            bottom: 168,
            left: 48,
            child: Icon(Icons.circle, size: 6, color: sparkle),
          ),
          Positioned(
            bottom: 220,
            right: 72,
            child: Icon(Icons.circle, size: 5, color: sparkle),
          ),
        ],
      ),
    );
  }
}

class _AiGlowOrb extends StatelessWidget {
  const _AiGlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: AiAssistantSearch.highlight(
          text,
          query,
          base: style,
          hit: style.copyWith(
            backgroundColor: const Color(0xFFFFEB3B),
            color: const Color(0xFF182230),
          ),
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

class _AiFirstGuide extends StatefulWidget {
  const _AiFirstGuide({
    required this.onFinished,
  });

  static const assets = <String>[
    'assets/ai/44.webp',
    'assets/ai/33.webp',
    'assets/ai/22.webp',
    'assets/ai/11.webp',
  ];

  final VoidCallback onFinished;

  @override
  State<_AiFirstGuide> createState() => _AiFirstGuideState();
}

class _AiFirstGuideState extends State<_AiFirstGuide> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index >= _AiFirstGuide.assets.length - 1;

  void _goNext() {
    if (_isLast) {
      return;
    }
    unawaited(
      _controller.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _AiFirstGuide.assets.length,
                onPageChanged: (index) {
                  setState(() {
                    _index = index;
                  });
                },
                itemBuilder: (context, index) {
                  final last = index == _AiFirstGuide.assets.length - 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: _goNext,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.asset(
                                    _AiFirstGuide.assets[index],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0;
                                        i < _AiFirstGuide.assets.length;
                                        i++)
                                      Container(
                                        width: i == _index ? 16 : 6,
                                        height: 6,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: i == _index
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.35),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Visibility(
                            visible: last,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: _AiGuideStartButton(
                              onPressed: widget.onFinished,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiGuideStartButton extends StatelessWidget {
  const _AiGuideStartButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFF6EB0FF), Color(0xFF3D7DFF)],
          ),
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                i18n.t(
                  zhHans: '立即体验 →',
                  zhHant: '立即體驗 →',
                  en: 'Get started →',
                  ja: '今すぐ体験 →',
                  ko: '바로 체험 →',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChatArt extends StatelessWidget {
  const _EmptyChatArt({
    required this.dark,
    required this.i18n,
    required this.onStart,
  });

  static const _asset = 'assets/ai/bg.png';

  final bool dark;
  final AppI18n i18n;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final artWidth = (width * 0.62).clamp(180.0, 280.0);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _asset,
              width: artWidth,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            Text(
              i18n.t(
                zhHans: '还没有聊天内容',
                zhHant: '還沒有聊天內容',
                en: 'No chats yet',
                ja: 'まだ会話がありません',
                ko: '아직 대화가 없습니다',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _AiPalette.primary(dark),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              i18n.t(
                zhHans: '现在开始与 99ChatAI 对话\n让 AI 帮你解答问题、生成内容、激发灵感',
                zhHant: '現在開始與 99ChatAI 對話\n讓 AI 幫你解答問題、生成內容、激發靈感',
                en:
                    'Start chatting with 99ChatAI\nto get answers, create content, and find inspiration',
                ja: '99ChatAI と会話を始めて\n質問への回答、コンテンツ作成、アイデア出しを手伝ってもらいましょう',
                ko: '지금 99ChatAI와 대화를 시작해\n질문 해결, 콘텐츠 생성, 영감을 얻어 보세요',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _AiPalette.secondary(dark),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: _AiPalette.brand(dark),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text(
                i18n.t(
                  zhHans: '开始新对话',
                  zhHant: '開始新對話',
                  en: 'Start a new chat',
                  ja: '新しい会話を始める',
                  ko: '새 대화 시작',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({
    required this.dark,
    required this.i18n,
    required this.onClose,
  });

  final bool dark;
  final AppI18n i18n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/ai/welcome.jpg',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: i18n.t(
              zhHans: '关闭',
              zhHant: '關閉',
              en: 'Close',
              ja: '閉じる',
              ko: '닫기',
            ),
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: _AiPalette.secondary(dark),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.dark,
    required this.message,
    required this.faceUrl,
    required this.showName,
    required this.ownerId,
    required this.onCardTap,
    required this.onFileTap,
    required this.fileCache,
    this.query = '',
    this.onLongPress,
  });

  final bool dark;
  final AiAssistantMessage message;
  final String faceUrl;
  final String showName;
  final String ownerId;
  final ValueChanged<AiAssistantCardRef> onCardTap;
  final ValueChanged<AiAssistantFileRef> onFileTap;
  final Map<String, Uint8List> fileCache;
  final String query;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final text = message.text?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (text.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _AiPalette.bubble(dark),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: _HighlightText(
                      text: text,
                      query: query,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              for (final card in message.cards) ...[
                const SizedBox(height: 8),
                _UserCardRow(
                  dark: dark,
                  card: card,
                  onTap: () => onCardTap(card),
                  query: query,
                ),
              ],
              for (final file in message.files) ...[
                const SizedBox(height: 8),
                if (_canShowUserImage(file, fileCache))
                  _UserImageThumb(
                    dark: dark,
                    file: file,
                    bytes: file.bytes ??
                        fileCache[(file.fileId ?? '').trim()],
                    onTap: () => onFileTap(file),
                    query: query,
                  )
                else
                  _UserFileRow(
                    dark: dark,
                    file: file,
                    onTap: () => onFileTap(file),
                    query: query,
                  ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.time,
                    style: TextStyle(
                      color: _AiPalette.secondary(dark),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.done,
                    size: 14,
                    color: _AiPalette.secondary(dark),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
        const SizedBox(width: 8),
        AppUserAvatar(
          faceUrl: faceUrl,
          showName: showName,
          size: 32,
          ownerId: ownerId.isEmpty ? null : ownerId,
        ),
      ],
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.dark,
    required this.i18n,
    required this.message,
    required this.onComingSoon,
    required this.fileCache,
    required this.onNeedFile,
    this.imageBytes,
    this.query = '',
    this.onLongPress,
    this.onImageTap,
    this.onMarkdownImage,
  });

  final bool dark;
  final AppI18n i18n;
  final AiAssistantMessage message;
  final ValueChanged<String> onComingSoon;
  final Map<String, Uint8List> fileCache;
  final ValueChanged<String> onNeedFile;
  final Uint8List? imageBytes;
  final String query;
  final VoidCallback? onLongPress;
  final VoidCallback? onImageTap;
  final ValueChanged<String>? onMarkdownImage;

  @override
  Widget build(BuildContext context) {
    final kind = message.outputKind;
    final Widget child;
    switch (kind) {
      case AiAssistantOutputKind.thinking:
        child = _ThinkingCard(dark: dark, i18n: i18n);
      case AiAssistantOutputKind.summary:
        child = _SummaryCard(dark: dark, data: message.summary, query: query);
      case AiAssistantOutputKind.image:
        child = _PosterCard(
          dark: dark,
          bytes: imageBytes,
          imageUrl: message.imageUrl,
          onTap: onImageTap,
        );
      case AiAssistantOutputKind.fileAnalysis:
        child = _AnalysisCard(
          dark: dark,
          i18n: i18n,
          data: message.analysis,
          query: query,
          onViewOriginal: () => onComingSoon(
            i18n.t(
              zhHans: '查看原文件',
              zhHant: '查看原檔案',
              en: 'View original',
              ja: '元のファイルを見る',
              ko: '원본 보기',
            ),
          ),
        );
      case AiAssistantOutputKind.code:
        child = _CodeCard(dark: dark, data: message.code, query: query);
      case AiAssistantOutputKind.text:
      case null:
        child = _AssistantMarkdown(
          dark: dark,
          text: message.text ?? '',
          fileCache: fileCache,
          onNeedFile: onNeedFile,
          onImageTap: onMarkdownImage,
          query: query,
        );
    }
    return _AssistantTextCard(
      dark: dark,
      time: kind == AiAssistantOutputKind.thinking ? '' : message.time,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

class _MarkdownSearchHighlightBuilder extends MarkdownElementBuilder {
  _MarkdownSearchHighlightBuilder({
    required this.query,
    required this.fallbackStyle,
  });

  final String query;
  final TextStyle fallbackStyle;

  @override
  Widget? visitText(text, TextStyle? preferredStyle) {
    return _HighlightText(
      text: text.text,
      query: query,
      style: preferredStyle ?? fallbackStyle,
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({
    required this.dark,
    required this.text,
    required this.fileCache,
    required this.onNeedFile,
    this.onImageTap,
    this.query = '',
  });

  final bool dark;
  final String text;
  final Map<String, Uint8List> fileCache;
  final ValueChanged<String> onNeedFile;
  final ValueChanged<String>? onImageTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: _AiPalette.primary(dark),
      fontSize: 15,
      height: 1.45,
    );
    final needle = AiAssistantSearch.normalize(query);
    final highlightBuilder = _MarkdownSearchHighlightBuilder(
      query: query,
      fallbackStyle: style,
    );
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      builders: needle.isEmpty
          ? const <String, MarkdownElementBuilder>{}
          : <String, MarkdownElementBuilder>{
              'p': highlightBuilder,
              'h1': highlightBuilder,
              'h2': highlightBuilder,
              'h3': highlightBuilder,
              'h4': highlightBuilder,
              'h5': highlightBuilder,
              'h6': highlightBuilder,
              'li': highlightBuilder,
              'pre': highlightBuilder,
              'blockquote': highlightBuilder,
            },
      styleSheet: MarkdownStyleSheet(
        p: style,
        strong: style.copyWith(fontWeight: FontWeight.w600),
        em: style.copyWith(fontStyle: FontStyle.italic),
        listBullet: style,
        listIndent: 22,
        blockSpacing: 10,
        pPadding: const EdgeInsets.only(bottom: 6),
        h1: style.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        h2: style.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        h3: style.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      imageBuilder: (uri, title, alt) {
        return _buildImage(uri.toString());
      },
    );
  }

  Widget _buildImage(String raw) {
    final id = AiAssistantApi.fileIdFromUrl(raw);
    if (id != null) {
      final bytes = fileCache[id];
      if (bytes == null || bytes.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onNeedFile(id);
        });
        return _placeholder(waiting: true);
      }
      return GestureDetector(
        onTap: () => onImageTap?.call(raw),
        child: _frame(
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
          ),
        ),
      );
    }
    if (raw.contains('/api/v1/chat/files/')) {
      return _placeholder(waiting: true);
    }
    return _placeholder(waiting: false);
  }

  Widget _frame(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }

  Widget _placeholder({required bool waiting}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: ColoredBox(
          color: _AiPalette.inputBg(dark),
          child: Center(
            child: waiting
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _AiPalette.brand(dark),
                    ),
                  )
                : Icon(
                    Icons.image_outlined,
                    color: _AiPalette.secondary(dark),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({this.size = 32});

  static const _asset = 'assets/ai/99chat.webp';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _AssistantTextCard extends StatelessWidget {
  const _AssistantTextCard({
    required this.dark,
    required this.time,
    required this.child,
    this.onLongPress,
  });

  final bool dark;
  final String time;
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AssistantAvatar(),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _AiPalette.cardBg(dark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _AiPalette.line(dark)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: child,
                ),
              ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    color: _AiPalette.secondary(dark),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.dark,
    required this.data,
    this.query = '',
  });

  final bool dark;
  final AiAssistantSummaryData? data;
  final String query;

  @override
  Widget build(BuildContext context) {
    final summary = data;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    const marks = <String>['①', '②', '③', '④'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              color: _AiPalette.brand(dark),
              size: 18,
            ),
            const SizedBox(width: 6),
            _HighlightText(
              text: summary.title,
              query: query,
              style: TextStyle(
                color: _AiPalette.primary(dark),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _HighlightText(
          text: summary.meta,
          query: query,
          style: TextStyle(
            color: _AiPalette.secondary(dark),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < summary.items.length; i++) ...[
          _HighlightText(
            text:
                '${i < marks.length ? marks[i] : '${i + 1}.'} ${summary.items[i]}',
            query: query,
            style: TextStyle(
              color: _AiPalette.primary(dark),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (i < summary.items.length - 1) const SizedBox(height: 4),
        ],
        const SizedBox(height: 8),
        _HighlightText(
          text: summary.footer,
          query: query,
          style: TextStyle(
            color: _AiPalette.primary(dark),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.dark,
    this.bytes,
    this.imageUrl,
    this.onTap,
  });

  final bool dark;
  final Uint8List? bytes;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null && bytes!.isNotEmpty;
    final waiting = !hasImage && (imageUrl ?? '').trim().isNotEmpty;
    return GestureDetector(
      onTap: hasImage ? onTap : null,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: hasImage
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                width: double.infinity,
              )
            : ColoredBox(
                color: _AiPalette.inputBg(dark),
                child: Center(
                  child: waiting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _AiPalette.brand(dark),
                          ),
                        )
                      : Icon(
                          Icons.image_outlined,
                          color: _AiPalette.secondary(dark),
                        ),
                ),
              ),
      ),
      ),
    );
  }
}

class _UserCardRow extends StatelessWidget {
  const _UserCardRow({
    required this.dark,
    required this.card,
    required this.onTap,
    this.query = '',
  });

  final bool dark;
  final AiAssistantCardRef card;
  final VoidCallback onTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final badge = card.kind == AiAssistantCardKind.friend
        ? i18n.t(
            zhHans: '好友',
            zhHant: '好友',
            en: 'Friend',
            ja: '友だち',
            ko: '친구',
          )
        : i18n.t(
            zhHans: '群',
            zhHant: '群',
            en: 'Group',
            ja: 'グループ',
            ko: '그룹',
          );
    return Material(
      color: _AiPalette.cardBg(dark),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _AiPalette.line(dark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppUserAvatar(
                faceUrl: card.faceUrl,
                showName: card.name,
                size: 32,
                type: card.kind == AiAssistantCardKind.group ? 2 : 1,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: card.name,
                    query: query,
                    style: TextStyle(
                      color: _AiPalette.primary(dark),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    badge,
                    style: TextStyle(
                      color: _AiPalette.secondary(dark),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _canShowUserImage(
  AiAssistantFileRef file,
  Map<String, Uint8List> fileCache,
) {
  final bytes = file.bytes ?? fileCache[(file.fileId ?? '').trim()];
  if (bytes != null && bytes.isNotEmpty) {
    return AiAssistantUploadMime.isImageBytes(bytes);
  }
  return file.kind == AiAssistantFileKind.image &&
      (file.localPath ?? '').isNotEmpty;
}

class _UserImageThumb extends StatelessWidget {
  const _UserImageThumb({
    required this.dark,
    required this.file,
    required this.onTap,
    this.bytes,
    this.query = '',
  });

  final bool dark;
  final AiAssistantFileRef file;
  final VoidCallback onTap;
  final Uint8List? bytes;
  final String query;

  @override
  Widget build(BuildContext context) {
    final path = file.localPath ?? '';
    final data = bytes ?? file.bytes;
    final Widget child;
    if (data != null && data.isNotEmpty) {
      child = Image.memory(
        data,
        width: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _UserFileRow(
          dark: dark,
          file: file,
          onTap: onTap,
          query: query,
        ),
      );
    } else if (!kIsWeb && path.isNotEmpty) {
      child = Image.file(
        File(path),
        width: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _UserFileRow(
          dark: dark,
          file: file,
          onTap: onTap,
          query: query,
        ),
      );
    } else {
      child = _UserFileRow(
        dark: dark,
        file: file,
        onTap: onTap,
        query: query,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 96, child: child),
      ),
    );
  }
}

class _DraftBar extends StatelessWidget {
  const _DraftBar({
    required this.dark,
    required this.i18n,
    required this.drafts,
    required this.onRemove,
  });

  final bool dark;
  final AppI18n i18n;
  final List<AiAssistantDraftItem> drafts;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: drafts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = drafts[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _draftBody(item),
              Positioned(
                top: -4,
                right: -4,
                child: InkWell(
                  onTap: () => onRemove(index),
                  customBorder: const CircleBorder(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _AiPalette.cardBg(dark),
                      shape: BoxShape.circle,
                      border: Border.all(color: _AiPalette.line(dark)),
                    ),
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: Icon(Icons.close_rounded, size: 12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _draftBody(AiAssistantDraftItem item) {
    final card = item.card;
    if (card != null) {
      final badge = card.kind == AiAssistantCardKind.friend
          ? i18n.t(
              zhHans: '好友',
              zhHant: '好友',
              en: 'Friend',
              ja: '友だち',
              ko: '친구',
            )
          : i18n.t(
              zhHans: '群',
              zhHant: '群',
              en: 'Group',
              ja: 'グループ',
              ko: '그룹',
            );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _AiPalette.cardBg(dark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _AiPalette.line(dark)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              AppUserAvatar(
                faceUrl: card.faceUrl,
                showName: card.name,
                size: 32,
                type: card.kind == AiAssistantCardKind.group ? 2 : 1,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _AiPalette.primary(dark),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      badge,
                      style: TextStyle(
                        color: _AiPalette.secondary(dark),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final file = item.file;
    if (file == null) {
      return const SizedBox.shrink();
    }
    final path = file.localPath ?? '';
    if (file.kind == AiAssistantFileKind.image && path.isNotEmpty && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _draftFileIcon(file),
        ),
      );
    }
    return _draftFileIcon(file);
  }

  Widget _draftFileIcon(AiAssistantFileRef file) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AiPalette.cardBg(dark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AiPalette.line(dark)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AiAssistantFileKinds.color(file.kind),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  AiAssistantFileKinds.icon(file.kind),
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 88,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _AiPalette.primary(dark),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserFileRow extends StatelessWidget {
  const _UserFileRow({
    required this.dark,
    required this.file,
    required this.onTap,
    this.query = '',
  });

  final bool dark;
  final AiAssistantFileRef file;
  final VoidCallback onTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _AiPalette.cardBg(dark),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _AiPalette.line(dark)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AiAssistantFileKinds.color(file.kind),
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                    ),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        AiAssistantFileKinds.icon(file.kind),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, constraints.maxWidth - 28 - 8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HighlightText(
                          text: file.name,
                          query: query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _AiPalette.primary(dark),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          file.sizeLabel,
                          style: TextStyle(
                            color: _AiPalette.secondary(dark),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.dark,
    required this.i18n,
    required this.data,
    required this.onViewOriginal,
    this.query = '',
  });

  final bool dark;
  final AppI18n i18n;
  final AiAssistantAnalysisData? data;
  final VoidCallback onViewOriginal;
  final String query;

  @override
  Widget build(BuildContext context) {
    final analysis = data;
    if (analysis == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.bar_chart_rounded,
              color: _AiPalette.brand(dark),
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              i18n.t(
                zhHans: '文件分析',
                zhHant: '檔案分析',
                en: 'File analysis',
                ja: 'ファイル分析',
                ko: '파일 분석',
              ),
              style: TextStyle(
                color: _AiPalette.primary(dark),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _HighlightText(
                text: '${analysis.fileName} 路 ${analysis.sizeLabel}',
                query: query,
                style: TextStyle(
                  color: _AiPalette.secondary(dark),
                  fontSize: 12,
                ),
              ),
            ),
            GestureDetector(
              onTap: onViewOriginal,
              child: Text(
                i18n.t(
                  zhHans: '查看原文件',
                  zhHant: '查看原檔案',
                  en: 'View original',
                  ja: '元のファイルを見る',
                  ko: '원본 보기',
                ),
                style: TextStyle(
                  color: _AiPalette.brand(dark),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final line in analysis.bullets) ...[
          _HighlightText(
            text: '• $line',
            query: query,
            style: TextStyle(
              color: _AiPalette.primary(dark),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.dark,
    required this.data,
    this.query = '',
  });

  final bool dark;
  final AiAssistantCodeData? data;
  final String query;

  @override
  Widget build(BuildContext context) {
    final code = data;
    if (code == null) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111827) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HighlightText(
              text: code.language,
              query: query,
              style: TextStyle(
                color: AppColors.subText(dark: true),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _HighlightText(
              text: code.source,
              query: query,
              style: const TextStyle(
                color: Color(0xFFF4F4F4),
                fontSize: 13,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatefulWidget {
  const _ThinkingCard({required this.dark, required this.i18n});

  final bool dark;
  final AppI18n i18n;

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Opacity(
                opacity: 0.3 +
                    0.7 *
                        Curves.easeInOut.transform(
                          (_controller.value + i * 0.2) % 1.0,
                        ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _AiPalette.brand(widget.dark),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 6, height: 6),
                ),
              ),
              if (i < 2) const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            child!,
          ],
        );
      },
      child: Text(
        widget.i18n.t(
          zhHans: '思考中',
          zhHant: '思考中',
          en: 'Thinking',
          ja: '考え中',
          ko: '생각 중',
        ),
        style: TextStyle(
          color: _AiPalette.primary(widget.dark),
          fontSize: 15,
        ),
      ),
    );
  }
}

class _QuickChipBar extends StatelessWidget {
  const _QuickChipBar({
    required this.dark,
    required this.i18n,
    required this.selectedId,
    required this.onSelected,
  });

  final bool dark;
  final AppI18n i18n;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final chips = <({String id, IconData icon, String label})>[
      (
        id: 'summarize',
        icon: Icons.notes_outlined,
        label: i18n.t(
          zhHans: '总结聊天',
          zhHant: '總結聊天',
          en: 'Summarize chat',
          ja: 'チャットを要約',
          ko: '채팅 요약',
        ),
      ),
      (
        id: 'image',
        icon: Icons.image_outlined,
        label: i18n.t(
          zhHans: '生成图片',
          zhHant: '生成圖片',
          en: 'Generate image',
          ja: '画像を生成',
          ko: '이미지 생성',
        ),
      ),
      (
        id: 'analyze',
        icon: Icons.description_outlined,
        label: i18n.t(
          zhHans: '分析文件',
          zhHant: '分析檔案',
          en: 'Analyze file',
          ja: 'ファイルを分析',
          ko: '파일 분석',
        ),
      ),
      (
        id: 'write',
        icon: Icons.edit_outlined,
        label: i18n.t(
          zhHans: '写文案',
          zhHant: '寫文案',
          en: 'Write copy',
          ja: 'コピーを作成',
          ko: '문구 작성',
        ),
      ),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final selected = selectedId == chip.id;
          final fg = selected
              ? _AiPalette.brand(dark)
              : _AiPalette.primary(dark);
          final bg = selected
              ? _AiPalette.brand(dark).withValues(alpha: dark ? 0.18 : 0.12)
              : _AiPalette.cardBg(dark);
          final border = selected
              ? _AiPalette.brand(dark).withValues(alpha: 0.45)
              : _AiPalette.line(dark);
          return Material(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => onSelected(chip.id),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 34,
                padding: EdgeInsets.only(
                  left: 12,
                  right: selected ? 6 : 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(chip.icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      chip.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: () => onSelected(chip.id),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.dark,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onAdd,
    required this.onImage,
    required this.onAttach,
    required this.onSubmit,
    required this.onStop,
    required this.replying,
  });

  final bool dark;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAdd;
  final VoidCallback onImage;
  final VoidCallback onAttach;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  final bool replying;

  @override
  Widget build(BuildContext context) {
    final iconColor = _AiPalette.primary(dark);
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _AiPalette.inputBg(dark),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _AiPalette.line(dark),
              ),
              boxShadow: dark
                  ? const <BoxShadow>[]
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x140B1220),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  _InputIconButton(
                    icon: Icons.add,
                    color: iconColor,
                    onPressed: onAdd,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.send,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onSubmitted: (_) {
                        if (!replying) {
                          onSubmit();
                        }
                      },
                      style: TextStyle(
                        color: _AiPalette.primary(dark),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                          color: _AiPalette.secondary(dark),
                          fontSize: 14,
                        ),
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  _InputIconButton(
                    icon: Icons.image_outlined,
                    color: iconColor,
                    onPressed: onImage,
                  ),
                  _InputIconButton(
                    icon: Icons.description_outlined,
                    color: iconColor,
                    onPressed: onAttach,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: replying ? onStop : onSubmit,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    _AiPalette.accent,
                    _AiPalette.userBubble,
                  ],
                ),
              ),
              child: Icon(
                replying ? Icons.stop_rounded : Icons.send_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InputIconButton extends StatelessWidget {
  const _InputIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, size: 22, color: color),
    );
  }
}
