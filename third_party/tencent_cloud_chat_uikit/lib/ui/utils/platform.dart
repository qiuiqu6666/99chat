import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformUtils {
  PlatformUtils._internal();
  static late bool _isAndroid;
  static late bool _isIos;
  static late bool _isMobile;
  static late bool _isWeb;
  static late bool _isWindows;
  static late bool _isMacOS;
  static late bool _isLinux;
  static late bool _isDesktop;
  static bool _isInstantiation = false;

  factory PlatformUtils() {
    if (!_isInstantiation) {
      _isAndroid = !kIsWeb && Platform.isAndroid;
      _isIos = !kIsWeb && Platform.isIOS;
      _isMobile = _isAndroid || _isIos;
      _isWindows = !kIsWeb && Platform.isWindows;
      _isMacOS = !kIsWeb && Platform.isMacOS;
      _isLinux = !kIsWeb && Platform.isLinux;
      _isDesktop = _isMacOS || _isWindows || _isLinux;
      _isWeb = kIsWeb;
      _isInstantiation = true;
    }

    return _instance;
  }

  static late final PlatformUtils _instance = PlatformUtils._internal();

  get isAndroid {
    return _isAndroid;
  }

  get isWeb {
    return _isWeb;
  }

  get isIOS {
    return _isIos;
  }

  get isWindows {
    return _isWindows;
  }

  get isMacOS {
    return _isMacOS;
  }

  get isMobile {
    return _isMobile;
  }

  bool get isDesktop => _isDesktop;

  /// Input / mouse / keyboard capability. Windows, macOS, and Linux only.
  /// Not layout: do not use width, [TUIKitScreenUtils.getFormFactor], or
  /// `isDesktopScreen` as a substitute.
  bool get isNativeDesktop => _isDesktop;

  bool get isLinux => _isLinux;

  bool get isWinMacDesktop => _isWindows || _isMacOS;
}
