import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';

/// Shared decode key for warming and displaying a cover; never loads video.
ImageProvider? chatVideoCoverProvider(V2TimVideoElem video) {
  final local = kIsWeb ? null :
      existingLocalMediaPath(video.snapshotPath) ??
      existingLocalMediaPath(video.localSnapshotUrl);
  final url = video.snapshotUrl?.trim() ?? '';
  final ImageProvider base;
  if (local != null) {
    base = FileImage(File(local));
  } else if (url.isNotEmpty) {
    if (kIsWeb) {
      base = NetworkImage(url);
    } else {
      base = CachedNetworkImageProvider(url);
    }
  } else {
    return null;
  }
  return ResizeImage(base, width: 384);
}
