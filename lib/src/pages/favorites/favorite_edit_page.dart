import 'dart:io';
import 'dart:typed_data';
import 'widgets/favorite_editor_icon.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/api/favorite_message_api.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/models/favorite_message_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/widgets/favorite_media_preview.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/services/system_media_picker.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_edit/editable_asset_picker.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';

/// 新建或编辑收藏（笔记 / 图片 / 短视频）。
class FavoriteEditPage extends StatefulWidget {
  const FavoriteEditPage._({
    this.existing,
    required this.initialType,
  });

  final FavoriteMessageItem? existing;
  final FavoriteMessageType initialType;

  bool get isEditing => existing != null;

  static Future<FavoriteMessageItem?> pushCreate(
    BuildContext context, {
    FavoriteMessageType type = FavoriteMessageType.text,
  }) {
    return Navigator.push<FavoriteMessageItem>(
      context,
      AppMaterialPageRoute(
        builder: (_) => FavoriteEditPage._(initialType: type),
      ),
    );
  }

  static Future<FavoriteMessageItem?> pushEdit(
    BuildContext context,
    FavoriteMessageItem item,
  ) {
    return Navigator.push<FavoriteMessageItem>(
      context,
      AppMaterialPageRoute(
        builder: (_) => FavoriteEditPage._(
          existing: item,
          initialType: item.type,
        ),
      ),
    );
  }

  @override
  State<FavoriteEditPage> createState() => _FavoriteEditPageState();
}

class _FavoriteEditPageState extends State<FavoriteEditPage> {
  static const _maxVideoSec = 60;

  late FavoriteMessageType _type;
  late final TextEditingController _textController;
  late final TextEditingController _remarkController;
  String? _localImagePath;
  String? _localVideoPath;
  Uint8List? _localVideoThumbBytes;
  String? _networkThumbUrl;
  String? _networkMediaUrl;
  int? _durationSec;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _type = item?.type ?? widget.initialType;
    _textController = TextEditingController(text: item?.text ?? '');
    _remarkController = TextEditingController(
      text: item?.sourceConvLabel?.trim() ?? '',
    );
    _localImagePath = item?.type == FavoriteMessageType.image
        ? item?.localMediaPath ?? item?.localThumbPath
        : null;
    _localVideoPath =
        item?.type == FavoriteMessageType.video ? item?.localMediaPath : null;
    _networkThumbUrl = item?.thumbUrl;
    _networkMediaUrl = item?.mediaUrl;
    _durationSec = item?.durationSec;
    if (_localImagePath == null &&
        item?.type == FavoriteMessageType.image &&
        item?.displayMediaPathOrUrl?.startsWith('http') != true) {
      _localImagePath = item?.displayMediaPathOrUrl;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final allowed = await PermissionGuard.photosForPick(context);
    if (!allowed || !mounted) return;
    final picked = await SystemMediaPicker.pickImages(maxAssets: 1);
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() => _localImagePath = picked.first.path);
  }

  Future<void> _pickVideo() async {
    final allowed = await PermissionGuard.photosForPick(context);
    if (!allowed || !mounted) return;
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final picked = await EditableAssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 1,
        requestType: RequestType.video,
        themeColor: theme.primaryColor ?? const Color(0xFF1E90FF),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    final asset = picked.first;
    if (asset.type != AssetType.video) return;

    final durationSec = asset.videoDuration.inSeconds;
    if (durationSec > _maxVideoSec) {
      ToastUtils.toast(TIM_t('请选择60秒以内的视频'));
      return;
    }

    final file = await EditableAssetPicker.resolveFile(asset);
    if (file == null) {
      ToastUtils.toast(TIM_t('无法读取视频文件'));
      return;
    }

    final thumbBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(800, 800),
    );

    if (!mounted) return;
    setState(() {
      _localVideoPath = file.path;
      _localVideoThumbBytes = thumbBytes;
      _localImagePath = null;
      _durationSec = durationSec;
      _networkThumbUrl = null;
      _networkMediaUrl = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final remark = _remarkController.text.trim();

    if (_type == FavoriteMessageType.text &&
        _textController.text.trim().isEmpty) {
      ToastUtils.toast(TIM_t('请输入内容'));
      return;
    }
    if (_type == FavoriteMessageType.image &&
        _localImagePath == null &&
        (_networkMediaUrl?.trim().isEmpty ?? true) &&
        (_networkThumbUrl?.trim().isEmpty ?? true)) {
      ToastUtils.toast(TIM_t('请选择图片'));
      return;
    }
    if (_type == FavoriteMessageType.video &&
        _localVideoPath == null &&
        (_networkMediaUrl?.trim().isEmpty ?? true)) {
      ToastUtils.toast(TIM_t('请选择视频'));
      return;
    }

    setState(() => _saving = true);
    try {
      final api = FavoriteMessageApi.instance;
      final existing = widget.existing;
      late FavoriteMessageItem item;

      if (widget.isEditing && existing != null) {
        final pickedNewMedia =
            (_type == FavoriteMessageType.image && _localImagePath != null) ||
                (_type == FavoriteMessageType.video && _localVideoPath != null);
        if (pickedNewMedia) {
          await api.delete(existing.id);
          if (_type == FavoriteMessageType.image) {
            item = await api.upload(
              file: File(_localImagePath!),
              type: FavoriteMessageType.image,
              sourceConvLabel: remark.isEmpty ? null : remark,
              sourceSenderName: existing.sourceSenderName ?? TIM_t('我'),
            );
          } else {
            item = await api.upload(
              file: File(_localVideoPath!),
              type: FavoriteMessageType.video,
              durationSec: _durationSec,
              sourceConvLabel: remark.isEmpty ? null : remark,
              sourceSenderName: existing.sourceSenderName ?? TIM_t('我'),
            );
          }
        } else {
          item = await api.update(
            id: existing.id,
            text: _type == FavoriteMessageType.text
                ? _textController.text.trim()
                : null,
            sourceConvLabel: remark,
          );
        }
      } else {
        switch (_type) {
          case FavoriteMessageType.text:
            item = await api.create(
              CreateFavoriteRequest(
                type: FavoriteMessageType.text,
                text: _textController.text.trim(),
                sourceConvLabel: remark.isEmpty ? null : remark,
                sourceSenderName: TIM_t('我'),
                remark: remark.isEmpty ? null : remark,
              ),
            );
            break;
          case FavoriteMessageType.image:
            item = await api.upload(
              file: File(_localImagePath!),
              type: FavoriteMessageType.image,
              sourceConvLabel: remark.isEmpty ? null : remark,
              sourceSenderName: TIM_t('我'),
            );
            break;
          case FavoriteMessageType.video:
            item = await api.upload(
              file: File(_localVideoPath!),
              type: FavoriteMessageType.video,
              durationSec: _durationSec,
              sourceConvLabel: remark.isEmpty ? null : remark,
              sourceSenderName: TIM_t('我'),
            );
            break;
        }
      }

      if (!mounted) return;
      Navigator.pop(context, item);
    } on DioError catch (e) {
      ToastUtils.toast(FavoriteMessageApi.errorMessage(e));
    } catch (e) {
      ToastUtils.toast(DioErrorMessage.forApp(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = AppColors.card(dark: dark);
    final text = AppColors.text(dark: dark);
    final secondary = AppColors.subText(dark: dark);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.line(dark: dark)),
    );
    return Scaffold(
      backgroundColor:
          dark ? AppColors.background(dark: true) : const Color(0xFFF5F8FF),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
          color: secondary,
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        title: Text(widget.isEditing ? TIM_t('编辑收藏') : TIM_t('新建收藏'),
            style: TextStyle(
                color: text, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 9, 12, 9),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  padding: const EdgeInsets.symmetric(horizontal: 15)),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(TIM_t('保存'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          )
        ],
      ),
      body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: AbsorbPointer(
                  absorbing: _saving,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                    children: [
                      if (!widget.isEditing) ...[
                        _TypeSelector(
                            type: _type,
                            dark: dark,
                            onChanged: (t) => setState(() => _type = t)),
                        const SizedBox(height: 16),
                      ],
                      ..._buildTypeFields(dark),
                      const SizedBox(height: 20),
                      Row(children: [
                        Text(TIM_t('备注'),
                            style: TextStyle(
                                fontSize: 15,
                                color: text,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        Text(TIM_t('选填'),
                            style: TextStyle(fontSize: 12, color: secondary)),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('favorite-remark'),
                        controller: _remarkController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: TIM_t('添加备注，便于在列表中识别…'),
                          hintStyle: TextStyle(fontSize: 14, color: secondary),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 17),
                          filled: true,
                          fillColor: card,
                          border: border,
                          enabledBorder: border,
                          focusedBorder: border.copyWith(
                              borderSide: const BorderSide(
                                  color: AppColors.primaryBlue)),
                        ),
                        style: TextStyle(fontSize: 14, color: text),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: AppColors.primaryBlue
                                .withValues(alpha: dark ? .12 : .045),
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FavoriteEditorIcon('tip',
                                  size: 28, color: AppColors.primaryBlue),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(TIM_t('小提示'),
                                        style: const TextStyle(
                                            color: AppColors.primaryBlue,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text(
                                        TIM_t('记录笔记，或选择图片、视频进行收藏。添加备注，方便以后查找。'),
                                        style: TextStyle(
                                            color: secondary,
                                            fontSize: 12,
                                            height: 1.5)),
                                  ])),
                            ]),
                      ),
                      const SizedBox(height: 28),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF50BCFF), Color(0xFF348CFF)]),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: .15),
                                blurRadius: 18,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const StadiumBorder()),
                          child: Text(_saving ? TIM_t('保存中…') : TIM_t('保存收藏'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  )),
            ),
          )),
    );
  }

  List<Widget> _buildTypeFields(bool dark) {
    switch (_type) {
      case FavoriteMessageType.text:
        return [
          Container(
            decoration: BoxDecoration(
                color: AppColors.card(dark: dark),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line(dark: dark))),
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              TextField(
                key: const ValueKey('favorite-note'),
                controller: _textController,
                minLines: 8,
                maxLines: 14,
                decoration: InputDecoration(
                  hintText: TIM_t('请输入笔记内容…'),
                  hintStyle: TextStyle(
                      fontSize: 16, color: AppColors.subText(dark: dark)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: AppColors.text(dark: dark)),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _textController,
                builder: (_, value, __) => Text(
                    '${value.text.characters.length}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.subText(dark: dark))),
              ),
            ]),
          ),
        ];
      case FavoriteMessageType.image:
        final preview = _localImagePath ?? _networkMediaUrl ?? _networkThumbUrl;
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).shortestSide * .42)
                  .clamp(120.0, 180.0),
              child: FavoriteMediaPreview(
                pathOrUrl: preview,
                dark: dark,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MediaPickButton(
            label: TIM_t('从相册选择图片'),
            onTap: _pickImage,
          ),
        ];
      case FavoriteMessageType.video:
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).shortestSide * .42)
                  .clamp(120.0, 180.0),
              child: _buildVideoPreview(dark),
            ),
          ),
          if (_durationSec != null) ...[
            const SizedBox(height: 8),
            Text(
              '${TIM_t("时长")} ${_formatDuration(_durationSec!)}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.subText(dark: dark),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _MediaPickButton(
            label: TIM_t('从相册选择视频（60秒内）'),
            onTap: _pickVideo,
          ),
        ];
    }
  }

  Widget _buildVideoPreview(bool dark) {
    final hasLocalVideo = _localVideoPath != null;
    final hasRemote = (_networkThumbUrl?.trim().isNotEmpty ?? false) ||
        (_networkMediaUrl?.trim().isNotEmpty ?? false);

    Widget media;
    if (_localVideoThumbBytes != null) {
      media = Image.memory(
        _localVideoThumbBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (hasRemote) {
      media = FavoriteMediaPreview(
        pathOrUrl: _networkThumbUrl ?? _networkMediaUrl,
        dark: dark,
        fit: BoxFit.cover,
      );
    } else if (hasLocalVideo) {
      media = ColoredBox(
        color: AppColors.line(dark: dark),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            size: 48,
            color: AppColors.primaryBlue,
          ),
        ),
      );
    } else {
      media = FavoriteMediaPreview(
        pathOrUrl: null,
        dark: dark,
        fit: BoxFit.cover,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        media,
        if (hasLocalVideo || hasRemote)
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.28),
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
      ],
    );
  }

  static String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.type,
    required this.dark,
    required this.onChanged,
  });

  final FavoriteMessageType type;
  final bool dark;
  final ValueChanged<FavoriteMessageType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(FavoriteMessageType.text, TIM_t('笔记'), Icons.notes_outlined),
        const SizedBox(width: 8),
        _chip(FavoriteMessageType.image, TIM_t('图片'), Icons.image_outlined),
        const SizedBox(width: 8),
        _chip(
          FavoriteMessageType.video,
          TIM_t('视频'),
          Icons.videocam_outlined,
        ),
      ],
    );
  }

  Widget _chip(FavoriteMessageType value, String label, IconData icon) {
    final selected = type == value;
    final subtitle = switch (value) {
      FavoriteMessageType.text => TIM_t('记录文字内容'),
      FavoriteMessageType.image => TIM_t('保存图片内容'),
      FavoriteMessageType.video => TIM_t('保存视频内容'),
    };
    return Expanded(
        child: Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? (dark ? const Color(0xFF1E3552) : const Color(0xFFE9F3FF))
            : AppColors.card(dark: dark),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color:
                    selected ? const Color(0xFFB9DAFF) : Colors.transparent)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(value),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 5),
              child: SizedBox(
                  width: double.infinity,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FavoriteEditorIcon('type_${value.name}', size: 32),
                    const SizedBox(height: 8),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text(dark: dark))),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: AppColors.subText(dark: dark))),
                  ])),
            ),
            if (selected)
              const Positioned(
                  top: 7,
                  right: 7,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: AppColors.primaryBlue, shape: BoxShape.circle),
                      child: Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.check_rounded,
                              size: 11, color: Colors.white)))),
          ]),
        ),
      ),
    ));
  }
}

class _MediaPickButton extends StatelessWidget {
  const _MediaPickButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
