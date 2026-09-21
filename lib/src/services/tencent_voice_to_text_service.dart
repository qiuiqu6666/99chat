import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class TencentVoiceToTextResult {
  const TencentVoiceToTextResult({
    this.text,
    this.errorMessage,
  });

  final String? text;
  final String? errorMessage;

  bool get isSuccess => text != null && text!.trim().isNotEmpty;
}

/// 腾讯 IM [convertVoiceToText](https://trtc.io/zh/document/60751?product=chat)
/// 实例区域与当前 init 的 sdkAppId（后端 UserSig）绑定，无需额外区域配置。
class TencentVoiceToTextService {
  TencentVoiceToTextService._();

  static String? lastErrorMessage;

  static Future<TencentVoiceToTextResult> convertMessage({
    required V2TimMessage message,
    String? msgID,
    Future<String?> Function(V2TimMessage message, String msgID)? resolveUrl,
  }) async {
    lastErrorMessage = null;
    if (kIsWeb) {
      return const TencentVoiceToTextResult(
        errorMessage: '当前平台暂不支持语音转文字',
      );
    }

    final resolvedMsgID = msgID?.trim();
    String? audioUrl = message.soundElem?.url?.trim();
    if ((audioUrl == null || audioUrl.isEmpty) &&
        resolveUrl != null &&
        resolvedMsgID != null &&
        resolvedMsgID.isNotEmpty) {
      audioUrl = await resolveUrl(message, resolvedMsgID);
    }
    if (audioUrl == null || audioUrl.isEmpty) {
      lastErrorMessage = '语音文件不可用';
      return TencentVoiceToTextResult(errorMessage: lastErrorMessage);
    }
    message.soundElem ??= V2TimSoundElem();
    message.soundElem!.url = audioUrl;

    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .convertVoiceToText(
          message: message,
          msgID: resolvedMsgID,
          language: IMDemoConfig.voiceToTextLanguage,
        );
    return _mapSdkResult(result);
  }

  static TencentVoiceToTextResult _mapSdkResult(
    V2TimValueCallback<String> result,
  ) {
    final text = result.data?.trim();
    if (result.code == 0 && text != null && text.isNotEmpty) {
      return TencentVoiceToTextResult(text: text);
    }

    final desc = result.desc.trim();
    if (desc.isNotEmpty) {
      lastErrorMessage = desc;
      return TencentVoiceToTextResult(errorMessage: desc);
    }
    lastErrorMessage = '转文字失败，请重试';
    return TencentVoiceToTextResult(errorMessage: lastErrorMessage);
  }
}
