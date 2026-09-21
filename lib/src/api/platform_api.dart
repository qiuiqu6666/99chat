import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

import 'api_client.dart';

class PlatformApi {
  PlatformApi._();

  static final PlatformApi instance = PlatformApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<PlatformContactInfo> fetchContact({
    Map<String, String>? extraHeaders,
  }) async {
    final res = await _dio.get(
      '/api/v1/platform/contact',
      options: extraHeaders == null
          ? null
          : Options(headers: extraHeaders),
    );
    final raw = unwrapApiPayload(res.data);
    final map = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return PlatformContactInfo.fromJson(map);
  }

  /// 获取在线客服 H5 页面地址（公开接口，无需 Token）。
  Future<String> fetchCustomerServiceUrl() async {
    final res = await _dio.get('/api/v1/platform/customer-service');
    final raw = unwrapApiPayload(res.data);
    final map = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return map['url']?.toString().trim() ?? '';
  }

  /// 冷启动图配置（公开接口，无需 Token）。
  Future<PlatformSplashConfig> fetchSplash({
    required String platform,
    required String appVersion,
    String channel = 'official',
  }) async {
    final res = await _dio.get(
      '/api/v1/platform/splash',
      queryParameters: <String, dynamic>{
        'platform': platform,
        'appVersion': appVersion,
        'channel': channel,
      },
    );
    final raw = unwrapApiPayload(res.data);
    final map = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return PlatformSplashConfig.fromJson(map);
  }
}

/// 服务端 `updateType` 字段归一化策略
enum UpdatePolicy {
  /// 不更新。即使发现新版本也不弹窗
  none,
  /// 可选更新。弹"发现新版本"，单按钮"立即更新"+ 右上角 X 可关闭
  optional,
  /// 强制更新。弹"需要更新"，单按钮"立即更新"，无 X，拦截系统返回
  force,
  /// 灰度更新。只对部分用户下发，弹"发现新版本"，单按钮"立即更新"，无 X
  gray,
}

extension UpdatePolicyX on UpdatePolicy {
  /// 是否需要展示升级弹窗
  bool get shouldPrompt => this != UpdatePolicy.none;

  /// 是否强制升级（不可关闭）
  bool get isMandatory =>
      this == UpdatePolicy.force || this == UpdatePolicy.gray;

  /// 是否显示关闭 X
  bool get showCloseButton => this == UpdatePolicy.optional;
}

class PlatformContactInfo {
  const PlatformContactInfo({
    required this.website,
    required this.email,
    required this.version,
    required this.build,
    required this.downloadUrl,
    this.platform = '',
    this.updateType = 'OPTIONAL',
    this.minVersion,
    this.minVersionCode,
    this.changelog,
    this.grayPercent,
    this.inGray,
    this.splash,
  });

  final String website;
  final String email;
  final String version;
  final String build;
  final String downloadUrl;
  final String platform;
  /// 'FORCE' | 'OPTIONAL'，大小写不敏感
  final String updateType;
  final String? minVersion;
  final int? minVersionCode;
  final String? changelog;
  final int? grayPercent;
  final bool? inGray;
  final PlatformSplashConfig? splash;

  /// 服务端 updateType 归一化策略
  UpdatePolicy get updatePolicy {
    final v = updateType.toUpperCase();
    switch (v) {
      case 'FORCE':
        return UpdatePolicy.force;
      case 'NONE':
        return UpdatePolicy.none;
      case 'GRAY':
        return UpdatePolicy.gray;
      case 'OPTIONAL':
      default:
        return UpdatePolicy.optional;
    }
  }

  /// 是否需要展示升级弹窗（force/optional/gray 都弹，none 不弹）
  bool get shouldPromptUpdate =>
      updatePolicy != UpdatePolicy.none;

  /// 是否强制升级（用户必须升级才能继续使用，不可关闭）
  bool get isMandatoryUpdate {
    final p = updatePolicy;
    return p == UpdatePolicy.force || p == UpdatePolicy.gray;
  }

  factory PlatformContactInfo.fromJson(Map<String, dynamic> json) {
    final updateTypeRaw = (json['updateType']?.toString() ?? 'OPTIONAL')
        .trim()
        .toUpperCase();
    final splashRaw = json['splash'];
    PlatformSplashConfig? splash;
    if (splashRaw is Map) {
      splash = PlatformSplashConfig.fromJson(
          Map<String, dynamic>.from(splashRaw));
    } else if (splashRaw == null) {
      splash = null;
    } else {
      splash = null;
    }

    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    return PlatformContactInfo(
      website: json['website']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      build: json['build']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      updateType: updateTypeRaw.isEmpty ? 'OPTIONAL' : updateTypeRaw,
      minVersion: _nullableTrim(json['minVersion']),
      minVersionCode: asInt(json['minVersionCode']),
      changelog: _nullableTrim(json['changelog']),
      grayPercent: asInt(json['grayPercent']),
      inGray: json['inGray'] is bool ? json['inGray'] as bool : null,
      splash: splash,
    );
  }
}

String? _nullableTrim(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

class PlatformSplashConfig {
  const PlatformSplashConfig({
    required this.enabled,
    required this.version,
    this.imageUrl,
    this.imageMd5,
    this.contentType,
    this.width,
    this.height,
    this.bytes,
    this.fit = 'cover',
    this.startAt,
    this.endAt,
    this.minAppVersion,
    this.updatedAt,
  });

  static const PlatformSplashConfig disabled = PlatformSplashConfig(
    enabled: false,
    version: 'default',
    imageUrl: null,
  );

  final bool enabled;
  final String version;
  final String? imageUrl;
  final String? imageMd5;
  final String? contentType;
  final int? width;
  final int? height;
  final int? bytes;
  final String fit;
  final String? startAt;
  final String? endAt;
  final String? minAppVersion;
  final String? updatedAt;

  bool get hasDownloadableImage {
    final url = imageUrl?.trim() ?? '';
    return enabled && url.isNotEmpty && version.trim().isNotEmpty;
  }

  factory PlatformSplashConfig.fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['enabled'];
    final enabled = enabledRaw is bool
        ? enabledRaw
        : enabledRaw?.toString().toLowerCase() == 'true';
    final imageUrl = json['imageUrl']?.toString().trim();
    return PlatformSplashConfig(
      enabled: enabled,
      version: json['version']?.toString().trim().isNotEmpty == true
          ? json['version'].toString().trim()
          : 'default',
      imageUrl: (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
      imageMd5: _nullableTrim(json['imageMd5'] ?? json['image_md5']),
      contentType: _nullableTrim(json['contentType'] ?? json['content_type']),
      width: _asPositiveInt(json['width']),
      height: _asPositiveInt(json['height']),
      bytes: _asPositiveInt(json['bytes']),
      fit: _nullableTrim(json['fit']) ?? 'cover',
      startAt: _nullableTrim(json['startAt'] ?? json['start_at']),
      endAt: _nullableTrim(json['endAt'] ?? json['end_at']),
      minAppVersion:
          _nullableTrim(json['minAppVersion'] ?? json['min_app_version']),
      updatedAt: _nullableTrim(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'version': version,
      'imageUrl': imageUrl,
      'imageMd5': imageMd5,
      'contentType': contentType,
      'width': width,
      'height': height,
      'bytes': bytes,
      'fit': fit,
      'startAt': startAt,
      'endAt': endAt,
      'minAppVersion': minAppVersion,
      'updatedAt': updatedAt,
    };
  }

  static String? _nullableTrim(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static int? _asPositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      final n = value.toInt();
      return n > 0 ? n : null;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}
