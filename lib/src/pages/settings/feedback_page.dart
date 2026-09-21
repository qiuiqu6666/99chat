import 'feedback_form_view.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'feedback_success_view.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/api/feedback_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/system_media_picker.dart';

class FeedbackPage extends StatefulWidget {
  /// 外层已有标题栏（如桌面弹窗）时隐藏自身 AppBar。
  final bool embedded;

  const FeedbackPage({super.key, this.embedded = false});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const int _maxScreenshots = 5;

  final TextEditingController _contentController = TextEditingController();

  FeedbackType _selectedType = FeedbackType.suggestion;
  final List<_FeedbackAttachment> _attachments = <_FeedbackAttachment>[];
  bool _submitting = false;
  bool _submitted = false;

  String _feedbackTypeLabel(FeedbackType type, AppI18n i18n) {
    switch (type) {
      case FeedbackType.suggestion:
        return i18n.t(
          zhHans: '建议',
          zhHant: '建議',
          en: 'Suggestion',
          ja: '提案',
          ko: '제안',
        );
      case FeedbackType.bug:
        return i18n.t(
          zhHans: '错误',
          zhHant: '錯誤',
          en: 'Bug',
          ja: '不具合',
          ko: '오류',
        );
      case FeedbackType.other:
        return i18n.t(
          zhHans: '其他',
          zhHant: '其他',
          en: 'Other',
          ja: 'その他',
          ko: '기타',
        );
    }
  }

  bool get _canSubmit =>
      !_submitting && _contentController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_refresh);
  }

  @override
  void dispose() {
    _contentController.removeListener(_refresh);
    _contentController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImages() async {
    final remain = _maxScreenshots - _attachments.length;
    if (remain <= 0) {
      _showMessage(AppI18n.current.format(
        zhHans: '最多上传 {count} 张截图',
        zhHant: '最多上傳 {count} 張截圖',
        en: 'You can upload up to {count} screenshots.',
        ja: 'アップロードできるスクリーンショットは最大 {count} 枚です。',
        ko: '스크린샷은 최대 {count}장까지 업로드할 수 있습니다.',
        vars: {'count': _maxScreenshots.toString()},
      ));
      return;
    }

    final allowed = await PermissionGuard.photosForPick(context);
    if (!allowed || !mounted) return;

    final pickedAssets = await SystemMediaPicker.pickImages(maxAssets: remain);
    if (pickedAssets.isEmpty) return;

    final next = <_FeedbackAttachment>[];
    for (final asset in pickedAssets.take(remain)) {
      final file = File(asset.path);
      final bytes = await file.readAsBytes();
      next.add(
        _FeedbackAttachment(
          filename: asset.name?.trim().isNotEmpty == true
              ? asset.name!.trim()
              : 'screenshot.jpg',
          bytes: bytes,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _attachments.addAll(next);
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    // Let the loading feedback register even when the API responds instantly.
    final minimumFeedback =
        Future<void>.delayed(const Duration(milliseconds: 650));
    try {
      await FeedbackApi.instance.submit(
        type: _selectedType,
        content: _contentController.text.trim(),
        screenshots: _attachments
            .map(
              (e) => FeedbackScreenshot(
                filename: e.filename,
                bytes: e.bytes,
              ),
            )
            .toList(),
      );
      await minimumFeedback;
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _submitted = true);
    } on DioError catch (e) {
      if (!mounted) return;
      _showMessage(_feedbackError(e));
    } catch (_) {
      if (!mounted) return;
      _showMessage(AppI18n.current.t(
        zhHans: '提交失败，请稍后重试',
        zhHant: '提交失敗，請稍後再試',
        en: 'Submission failed. Please try again later.',
        ja: '送信に失敗しました。しばらくしてからもう一度お試しください。',
        ko: '제출에 실패했습니다. 잠시 후 다시 시도해 주세요.',
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _feedbackError(DioError e) {
    final data = e.response?.data;
    if (data is Map) {
      final code = data['code']?.toString() ?? '';
      switch (code) {
        case 'INVALID_INPUT':
          return AppI18n.current.t(
            zhHans: '请输入反馈内容',
            zhHant: '請輸入回饋內容',
            en: 'Please enter your feedback.',
            ja: 'フィードバック内容を入力してください。',
            ko: '의견 내용을 입력해 주세요.',
          );
        case 'INVALID_FEEDBACK_TYPE':
          return AppI18n.current.t(
            zhHans: '反馈类型无效',
            zhHant: '回饋類型無效',
            en: 'Invalid feedback type.',
            ja: 'フィードバック種別が無効です。',
            ko: '의견 유형이 올바르지 않습니다.',
          );
        case 'CONTENT_TOO_LONG':
          return AppI18n.current.t(
            zhHans: '反馈内容过长',
            zhHant: '回饋內容過長',
            en: 'Your feedback is too long.',
            ja: 'フィードバック内容が長すぎます。',
            ko: '의견 내용이 너무 깁니다.',
          );
        case 'TOO_MANY_SCREENSHOTS':
          return AppI18n.current.t(
            zhHans: '截图最多上传 5 张',
            zhHant: '截圖最多上傳 5 張',
            en: 'You can upload up to 5 screenshots.',
            ja: 'アップロードできるスクリーンショットは最大5枚です。',
            ko: '스크린샷은 최대 5장까지 업로드할 수 있습니다.',
          );
        case 'INVALID_IMAGE':
          return AppI18n.current.t(
            zhHans: '截图文件无效',
            zhHant: '截圖檔案無效',
            en: 'The screenshot file is invalid.',
            ja: 'スクリーンショットファイルが無効です。',
            ko: '스크린샷 파일이 올바르지 않습니다.',
          );
        case 'UNSUPPORTED_TYPE':
          return AppI18n.current.t(
            zhHans: '仅支持 JPG、PNG、WEBP 图片',
            zhHant: '僅支援 JPG、PNG、WEBP 圖片',
            en: 'Only JPG, PNG, and WEBP images are supported.',
            ja: 'JPG、PNG、WEBP 形式の画像のみ対応しています。',
            ko: 'JPG, PNG, WEBP 이미지 형식만 지원됩니다.',
          );
        case 'FILE_TOO_LARGE':
          return AppI18n.current.t(
            zhHans: '单张截图不能超过 10MB',
            zhHant: '單張截圖不能超過 10MB',
            en: 'Each screenshot must be smaller than 10 MB.',
            ja: 'スクリーンショット1枚あたり10MB未満である必要があります。',
            ko: '스크린샷 한 장의 크기는 10MB를 초과할 수 없습니다.',
          );
        case 'OSS_NOT_CONFIGURED':
          return AppI18n.current.t(
            zhHans: '截图服务暂不可用，请稍后再试',
            zhHant: '截圖服務暫不可用，請稍後再試',
            en: 'Screenshot upload is temporarily unavailable. Please try again later.',
            ja: 'スクリーンショットのアップロードは現在利用できません。しばらくしてからもう一度お試しください。',
            ko: '스크린샷 업로드를 현재 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.',
          );
      }
      final message = data['message']?.toString() ?? '';
      if (message.isNotEmpty) {
        return DioErrorMessage.sanitizeUserText(
          message,
          fallback: AppI18n.current.t(
            zhHans: '提交失败，请稍后重试',
            zhHant: '提交失敗，請稍後重試',
            en: 'Submission failed. Please try again later.',
            ja: '送信に失敗しました。しばらくしてからもう一度お試しください。',
            ko: '제출에 실패했습니다. 잠시 후 다시 시도해 주세요.',
          ),
        );
      }
    }
    return AppI18n.current.t(
      zhHans: '提交失败，请稍后重试',
      zhHant: '提交失敗，請稍後再試',
      en: 'Submission failed. Please try again later.',
      ja: '送信に失敗しました。しばらくしてからもう一度お試しください。',
      ko: '제출에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    );
  }

  void _showMessage(String text) {
    ToastUtils.toast(text);
  }

  @override
  Widget build(BuildContext context) {
    final form = FeedbackFormView(
      controller: _contentController,
      attachments: _attachments.map((item) => item.bytes).toList(),
      maxScreenshots: _maxScreenshots,
      submitting: _submitting,
      canSubmit: _canSubmit,
      embedded: widget.embedded,
      selectedType: _selectedType,
      typeLabel: (type) => _feedbackTypeLabel(type, AppI18n.of(context)),
      onTypeChanged: (type) => setState(() => _selectedType = type),
      onSubmit: _submit,
      onAddImage: _pickImages,
      onRemoveImage: (index) => setState(() => _attachments.removeAt(index)),
    );
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: reduceMotion ? Offset.zero : const Offset(0, .025),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _submitted
          ? const FeedbackSuccessView(key: ValueKey('feedback-success'))
          : IgnorePointer(
              key: const ValueKey('feedback-form'),
              ignoring: _submitting,
              child: form,
            ),
    );
  }
}

class _FeedbackAttachment {
  const _FeedbackAttachment({
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final Uint8List bytes;
}

