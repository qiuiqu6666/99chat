import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Shared by avatar rendering and warming so both resolve the same cache entry.
ImageProvider<Object> avatarImageProvider({
  required String url,
  required int cacheSize,
  String? cacheKey,
  Map<String, String>? headers,
}) {
  return ResizeImage(
    CachedNetworkImageProvider(
      url,
      cacheKey: cacheKey,
      maxWidth: cacheSize,
      maxHeight: cacheSize,
      headers: headers,
    ),
    width: cacheSize,
    height: cacheSize,
  );
}
