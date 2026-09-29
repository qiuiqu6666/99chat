import 'package:tencent_cloud_chat_sdk/enum/V2TimSDKListener.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'im_event_bridge.dart';
import 'uikit_bootstrap.dart';

class ImClient {
  bool _initialized = false;
  int? _sdkAppId;
  ImEventBridge? _events;
  V2TimSDKListener? _sdkListener;

  void setEventBridge(ImEventBridge events) => _events = events;

  Future<void> initialize(int sdkAppId) async {
    if (_initialized && _sdkAppId == sdkAppId) return;
    if (_initialized) {
      await dispose();
    }
    await UIKitBootstrap.instance.initialize(
      sdkAppId: sdkAppId,
      events: _events ?? ImEventBridge(),
    );
    // 让业务层 ImEventBridge 真正进入 SDK 的 v2TimSDKListenerList。
    // 之前仅靠 UIKit 包装层 listener 透传，但底层 SDK 只走
    // v2TimSDKListenerList，而 UIKit 自身不会把自己注册进去，导致
    // 业务层永远收不到 onConnectSuccess / onDisconnected，标题 stuck failed。
    final bridge = _events ?? ImEventBridge();
    _sdkListener = bridge.listener();
    TencentImSDKPlugin.v2TIMManager.addIMSDKListener(_sdkListener!);
    _initialized = true;
    _sdkAppId = sdkAppId;
  }

  Future<void> connect(
      {required String userId, required String userSig}) async {
    if (!_initialized) throw StateError('IM SDK 尚未初始化');
    // Socket readiness comes from onConnectSuccess, not the start of login.
    final result = await TencentImSDKPlugin.v2TIMManager.login(
      userID: userId,
      userSig: userSig,
    );
    if (result.code != 0) {
      // 登录失败时回退到「未连接」语义，让标题恢复转圈/可重连。
      ImConnectStatusService.markSocketDisconnected();
      throw ImClientException('IM 登录失败: ${result.code}', code: result.code);
    }
  }

  Future<void> disconnect() async {
    if (!_initialized) return;
    ImConnectStatusService.markSocketDisconnected();
    await TencentImSDKPlugin.v2TIMManager.logout();
  }

  Future<void> dispose() async {
    if (!_initialized) {
      _initialized = false;
      _sdkAppId = null;
      return;
    }
    final listener = _sdkListener;
    if (listener != null) {
      TencentImSDKPlugin.v2TIMManager.removeIMSDKListener(listener);
    }
    _sdkListener = null;
    await UIKitBootstrap.instance.dispose();
    _initialized = false;
    _sdkAppId = null;
  }
}

class ImClientException implements Exception {
  const ImClientException(this.message, {this.code});
  final String message;
  final int? code;

  // UserSig errors from the vendored SDK's TIMErrorCode definitions. Only
  // reject a session after a freshly fetched credential fails these checks.
  bool get isCredentialRejected => const {
        6206,
        70001,
        70002,
        70003,
        70005,
        70009,
        70013,
        70014,
        70016,
      }.contains(code);
  @override
  String toString() => message;
}
