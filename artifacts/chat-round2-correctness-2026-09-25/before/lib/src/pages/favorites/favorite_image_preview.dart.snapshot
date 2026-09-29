import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/favorite_message_models.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/gallery_save_to_photos.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_payload.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';

Future<void> openFavoriteImagePreview(
  BuildContext context,
  FavoriteMessageItem item,
) {
  final raw = item.displayMediaPathOrUrl?.trim() ?? '';
  if (raw.isEmpty) {
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '暂无图片',
      zhHant: '暫無圖片',
      en: 'No image',
      ja: '画像がありません',
      ko: '이미지 없음',
    ));
    return Future<void>.value();
  }
  final provider = _favoriteImageProvider(raw);
  if (provider == null) {
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '暂无图片',
      zhHant: '暫無圖片',
      en: 'No image',
      ja: '画像がありません',
      ko: '이미지 없음',
    ));
    return Future<void>.value();
  }
  if (PlatformUtils().isWinMacDesktop) {
    final isHttp = raw.startsWith('http://') || raw.startsWith('https://');
    return DesktopMediaPreviewHook.tryOpen(
      DesktopMediaPreviewPayload.image(
        source: 'favorite',
        url: isHttp ? raw : null,
        localPath: isHttp ? null : raw,
        downloadOnly: true,
      ),
    ).then((opened) async {
      if (opened) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await pushMediaPreview(
        context: context,
        enableGestureBack: false,
        child: ImageScreen(
          imageProvider: provider,
          heroTag: '',
          enableHero: false,
          downloadOnly: true,
          downloadFn: () => saveFavoriteImageToGallery(context, item),
        ),
      );
    });
  }
  return pushMediaPreview(
    context: context,
    enableGestureBack: false,
    child: ImageScreen(
      imageProvider: provider,
      heroTag: '',
      enableHero: false,
      downloadOnly: true,
      downloadFn: () => saveFavoriteImageToGallery(context, item),
    ),
  );
}

Future<void> saveFavoriteImageToGallery(
  BuildContext context,
  FavoriteMessageItem item,
) async {
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
    if (context.mounted) {
      MediaPreviewSaveNotice.show(context, success: false);
    }
    throw StateError('permission_denied');
  }

  final raw = item.displayMediaPathOrUrl?.trim() ?? '';
  final name = 'favorite_${DateTime.now().millisecondsSinceEpoch}';
  var saved = false;
  if (raw.isNotEmpty && !raw.startsWith('http') && File(raw).existsSync()) {
    saved = await GallerySaveToPhotos.saveFile(File(raw), name: name);
  } else {
    final bytes = await _favoriteImageBytes(raw);
    if (bytes != null && bytes.isNotEmpty) {
      saved = await GallerySaveToPhotos.saveBytes(bytes, name: name);
    }
  }

  if (context.mounted) {
    MediaPreviewSaveNotice.show(context, success: saved);
  }
  if (saved) {
    return;
  }
  throw StateError('save_failed');
}

ImageProvider? _favoriteImageProvider(String raw) {
  if (raw.isEmpty) {
    return null;
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    final url = MediaUrlResolver.resolve(raw) ?? raw;
    return CachedNetworkImageProvider(
      url,
      headers: MediaUrlResolver.authHeadersFor(url),
    );
  }
  return FileImage(File(raw));
}

Future<Uint8List?> _favoriteImageBytes(String raw) async {
  final path = raw.trim();
  if (path.isEmpty || kIsWeb) {
    return null;
  }
  try {
    final resolved = MediaUrlResolver.resolve(path) ?? path;
    if (resolved.startsWith('http')) {
      final response = await Dio().get<List<int>>(
        resolved,
        options: Options(
          responseType: ResponseType.bytes,
          headers: MediaUrlResolver.authHeadersFor(resolved),
        ),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    }
    final file = File(resolved);
    if (!file.existsSync()) {
      return null;
    }
    return Uint8List.fromList(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}
