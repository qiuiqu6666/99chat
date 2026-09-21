import 'package:tencent_cloud_chat_sdk/enum/V2TimSDKListener.dart';

/// SDK 生命周期事件的唯一入口。业务层通过回调订阅，不直接注册 SDK listener。
class ImEventBridge {
  ImEventBridge({
    this.onConnecting,
    this.onConnected,
    this.onDisconnected,
    this.onUserSigExpired,
    this.onKickedOffline,
  });

  final void Function()? onConnecting;
  final void Function()? onConnected;
  final void Function(int code, String message)? onDisconnected;
  final void Function()? onUserSigExpired;
  final void Function()? onKickedOffline;

  V2TimSDKListener listener() => V2TimSDKListener(
        onConnecting: onConnecting,
        onConnectSuccess: onConnected,
        onConnectFailed: onDisconnected,
        onUserSigExpired: onUserSigExpired,
        onKickedOffline: onKickedOffline,
      );
}
