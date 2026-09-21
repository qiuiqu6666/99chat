import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/services/deepgram_voice_to_text_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/voice_to_text_result.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/xfyun_audio_utils.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/xfyun_iat_streaming_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/voice_to_text_bridge.dart';

/// 统一语音转文字入口（混合提供方）。
/// - 本地录音松手转文字：讯飞流式听写
/// - 已发送语音长按转文字：Deepgram pre-recorded API
class VoiceToTextService {
  VoiceToTextService._();

  static String? lastErrorMessage;

  /// 本地录音只能走不会制造真实会话消息的讯飞链路。
  static bool get usesXfyunForLocalRecording =>
      IMDemoConfig.voiceToTextProvider != 'tencent';

  static Future<VoiceToTextResult> convertMessage({
    required V2TimMessage message,
    String? msgID,
    Future<String?> Function(V2TimMessage message, String msgID)? resolveUrl,
  }) async {
    lastErrorMessage = null;
    if (kIsWeb) {
      return const VoiceToTextResult(errorMessage: '当前平台暂不支持语音转文字');
    }

    final result = await DeepgramVoiceToTextService.convertMessage(
      message: message,
      msgID: msgID,
      resolveUrl: resolveUrl,
    );
    return _finalize(result);
  }

  static Future<VoiceToTextResult> convertLocalFile({
    required String soundPath,
    required int duration,
    required String convID,
    required ConvType convType,
    VoiceToTextCancellationToken? cancellationToken,
  }) async {
    lastErrorMessage = null;
    if (kIsWeb) {
      return const VoiceToTextResult(errorMessage: '当前平台暂不支持语音转文字');
    }

    final path = soundPath.trim();
    if (path.isEmpty) {
      lastErrorMessage = '语音文件不可用';
      return VoiceToTextResult(errorMessage: lastErrorMessage);
    }

    if (!usesXfyunForLocalRecording) {
      lastErrorMessage = '当前配置不支持发送前转文字';
      return VoiceToTextResult(errorMessage: lastErrorMessage);
    }

    if (cancellationToken?.isCancelled ?? false) {
      return const VoiceToTextResult(isCancelled: true);
    }
    final effectiveDuration = duration > 0
        ? duration
        : await XfyunAudioUtils.estimateWavDurationSec(path);
    if (effectiveDuration <= 0) {
      lastErrorMessage = '说话时间太短';
      return VoiceToTextResult(errorMessage: lastErrorMessage);
    }

    final result = await XfyunIatStreamingService.transcribeLocalFile(
      path,
      cancellationToken: cancellationToken,
    );
    return _finalize(result);
  }

  static VoiceToTextResult _finalize(VoiceToTextResult result) {
    if (result.isCancelled) {
      return result;
    }
    if (!result.isSuccess) {
      lastErrorMessage = result.errorMessage ?? '转文字失败，请重试';
    }
    return result;
  }
}
