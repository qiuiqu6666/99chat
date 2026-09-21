/// 宿主可注入：将 IM 返回的相对/原始 URL 解析为可请求的完整地址。
String? Function(String url)? resolveMediaPreviewNetworkUrl;

/// 宿主可注入：为自有域名的媒体 URL 附加鉴权头（如 Bearer token）。
Map<String, String>? Function(String url)? mediaPreviewNetworkUrlHeaders;

String resolveChatMediaNetworkUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return resolveMediaPreviewNetworkUrl?.call(trimmed) ?? trimmed;
}

Map<String, String>? chatMediaNetworkHeaders(String url) {
  return mediaPreviewNetworkUrlHeaders?.call(url.trim());
}
