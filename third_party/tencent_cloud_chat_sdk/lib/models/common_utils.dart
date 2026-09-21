import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CommonUtils {
  static Directory? _appFileDir;
  static Directory? _appCacheDir;
  static Directory? _externalCacheDir;

  static int? Function()? _getSDKAppID;
  static String Function()? _getLoginUser;

  static Future<bool> init({
    int? Function()? getSDKAppID,
    String Function()? getLoginUser
  }) async {
    _appFileDir ??= Platform.isAndroid ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory();
    _appCacheDir = await getApplicationCacheDirectory();
    _externalCacheDir ??= Platform.isAndroid ? await getExternalStorageDirectory() : null;
    _getSDKAppID ??= getSDKAppID;
    _getLoginUser ??= getLoginUser;
    return true;
  }

  static Directory get appFileDir {
    if (_appFileDir == null) {
      throw Exception('app file directory not initialized. Call init() first.');
    }

    return _appFileDir!;
  }

  static Directory get appCacheDir {
    if (_appCacheDir == null) {
      throw Exception('app cache directory not initialized. Call init() first.');
    }

    return _appCacheDir!;
  }

  static Directory? get externalCacheDir {
    return _externalCacheDir;
  }

  static int? getSDKAppID() {
    return _getSDKAppID?.call();
  }
  
  static String getLoginUser() {
    return _getLoginUser?.call() ?? "";
  }

  /// 主 isolate 状态快照，供后台 isolate（`compute`）解码消息前灌入。
  /// 未 [init] 时返回 null。
  static CommonUtilsIsolateSeed? exportIsolateSeed() {
    if (_appFileDir == null) {
      return null;
    }
    return CommonUtilsIsolateSeed(
      appFileDirPath: _appFileDir!.path,
      appCacheDirPath: _appCacheDir?.path,
      externalCacheDirPath: _externalCacheDir?.path,
      sdkAppID: _getSDKAppID?.call(),
      loginUser: _getLoginUser?.call() ?? "",
    );
  }

  /// 在后台 isolate 内灌入 [exportIsolateSeed] 的快照。全部 `??=`，主 isolate 误调不覆盖。
  static void applyIsolateSeed(CommonUtilsIsolateSeed seed) {
    final appFileDirPath = seed.appFileDirPath;
    final appCacheDirPath = seed.appCacheDirPath;
    final externalCacheDirPath = seed.externalCacheDirPath;
    _appFileDir ??= appFileDirPath == null ? null : Directory(appFileDirPath);
    _appCacheDir ??= appCacheDirPath == null ? null : Directory(appCacheDirPath);
    _externalCacheDir ??=
        externalCacheDirPath == null ? null : Directory(externalCacheDirPath);
    _getSDKAppID ??= () => seed.sdkAppID;
    _getLoginUser ??= () => seed.loginUser;
  }
}

/// [CommonUtils] 的纯数据快照，可跨 isolate 传递。
class CommonUtilsIsolateSeed {
  const CommonUtilsIsolateSeed({
    required this.appFileDirPath,
    required this.appCacheDirPath,
    required this.externalCacheDirPath,
    required this.sdkAppID,
    required this.loginUser,
  });

  final String? appFileDirPath;
  final String? appCacheDirPath;
  final String? externalCacheDirPath;
  final int? sdkAppID;
  final String loginUser;
}