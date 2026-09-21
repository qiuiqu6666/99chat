import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/services/wav_pcm_extractor.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/voice_to_text_result.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/xfyun_audio_utils.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text/xfyun_auth.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/voice_to_text_bridge.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 讯飞 [语音听写流式版](https://www.xfyun.cn/doc/asr/voicedictation/API.html)
class XfyunIatStreamingService {
  XfyunIatStreamingService._();

  static const int _frameSize = 640;
  static const Duration _frameInterval = Duration(milliseconds: 40);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _resultTimeout = Duration(seconds: 30);
  static const Duration _maxAudioDuration = Duration(seconds: 60);

  static Future<VoiceToTextResult> transcribeLocalFile(
    String soundPath, {
    VoiceToTextCancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? VoiceToTextCancellationToken();
    if (token.isCancelled) {
      return const VoiceToTextResult(isCancelled: true);
    }
    if (!_hasCredentials) {
      return const VoiceToTextResult(errorMessage: '讯飞语音转写未配置');
    }

    final audioInfo = await XfyunAudioUtils.inspectFile(soundPath);
    if (audioInfo == null || audioInfo.dataLength <= 0) {
      return const VoiceToTextResult(errorMessage: '语音文件不可用');
    }
    if (audioInfo.channels != 1 || audioInfo.bitsPerSample != 16) {
      return const VoiceToTextResult(errorMessage: '语音格式不支持转文字');
    }
    if (audioInfo.dataLength >
        audioInfo.bytesPerSecond * _maxAudioDuration.inSeconds) {
      return const VoiceToTextResult(errorMessage: '录音超过60秒，请发送原语音');
    }
    Uint8List? convertedPcm;
    if (!audioInfo.isXfyunPcm) {
      final sourcePcm = await XfyunAudioUtils.readPcmBytes(soundPath);
      if (sourcePcm == null || sourcePcm.isEmpty) {
        return const VoiceToTextResult(errorMessage: '语音文件不可用');
      }
      convertedPcm = WavPcmExtractor.resampleLinear16Mono(
        sourcePcm,
        audioInfo.sampleRate,
        XfyunAudioUtils.defaultSampleRate,
      );
    }
    if (token.isCancelled) {
      return const VoiceToTextResult(isCancelled: true);
    }

    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    final completer = Completer<VoiceToTextResult>();
    final segments = <int, String>{};
    var latestText = '';
    var sawError = false;

    try {
      final url = XfyunAuth.buildIatWebSocketUrl(
        apiKey: IMDemoConfig.xfyunApiKey,
        apiSecret: IMDemoConfig.xfyunApiSecret,
      );
      channel = WebSocketChannel.connect(Uri.parse(url));
      await Future.any<void>([
        channel.ready.timeout(_connectTimeout),
        token.whenCancelled,
      ]);
      if (token.isCancelled) {
        return const VoiceToTextResult(isCancelled: true);
      }
      unawaited(
        token.whenCancelled.then((_) async {
          try {
            await channel?.sink.close();
          } catch (_) {}
        }),
      );

      subscription = channel.stream.listen(
        (event) {
          if (completer.isCompleted || token.isCancelled) {
            return;
          }
          final text = event?.toString();
          if (text == null || text.isEmpty) {
            return;
          }
          Map<String, dynamic> payload;
          try {
            payload = jsonDecode(text) as Map<String, dynamic>;
          } catch (_) {
            return;
          }

          final code = payload['code'];
          if (code is int && code != 0) {
            sawError = true;
            completer.complete(
              VoiceToTextResult(
                errorMessage: payload['message']?.toString() ?? '讯飞听写失败',
              ),
            );
            return;
          }

          final data = payload['data'];
          if (data is! Map<String, dynamic>) {
            return;
          }

          final result = data['result'];
          if (result is Map<String, dynamic>) {
            latestText = _mergeResult(
              segments: segments,
              result: result,
              fallback: latestText,
            );
          }

          final status = data['status'];
          if (status == 2) {
            completer.complete(
              VoiceToTextResult(
                text: latestText.trim().isEmpty ? null : latestText.trim(),
                errorMessage: latestText.trim().isEmpty ? '未识别到文字' : null,
              ),
            );
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            completer.complete(
              const VoiceToTextResult(errorMessage: '讯飞听写连接失败'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted && !token.isCancelled) {
            completer.complete(
              latestText.trim().isNotEmpty
                  ? VoiceToTextResult(text: latestText.trim())
                  : const VoiceToTextResult(errorMessage: '讯飞听写连接已断开'),
            );
          }
        },
      );

      await _sendAudioFrames(
        channel,
        soundPath,
        audioInfo,
        token,
        convertedPcm: convertedPcm,
      );
      if (token.isCancelled) {
        return const VoiceToTextResult(isCancelled: true);
      }

      final result = await Future.any<VoiceToTextResult>([
        completer.future,
        token.whenCancelled.then(
          (_) => const VoiceToTextResult(isCancelled: true),
        ),
      ]).timeout(
        _resultTimeout,
        onTimeout: () {
          if (latestText.trim().isNotEmpty) {
            return VoiceToTextResult(text: latestText.trim());
          }
          return const VoiceToTextResult(errorMessage: '讯飞听写超时');
        },
      );
      if (!result.isSuccess && !sawError && latestText.trim().isNotEmpty) {
        return VoiceToTextResult(text: latestText.trim());
      }
      return result;
    } catch (_) {
      if (token.isCancelled) {
        return const VoiceToTextResult(isCancelled: true);
      }
      return const VoiceToTextResult(errorMessage: '讯飞听写失败，请重试');
    } finally {
      try {
        await subscription?.cancel();
      } catch (_) {}
      try {
        await channel?.sink.close();
      } catch (_) {}
    }
  }

  static bool get _hasCredentials =>
      IMDemoConfig.xfyunAppId.isNotEmpty &&
      IMDemoConfig.xfyunApiKey.isNotEmpty &&
      IMDemoConfig.xfyunApiSecret.isNotEmpty;

  static Future<void> _sendAudioFrames(
    WebSocketChannel channel,
    String soundPath,
    XfyunAudioFileInfo audioInfo,
    VoiceToTextCancellationToken token, {
    Uint8List? convertedPcm,
  }) async {
    final reader = convertedPcm == null ? await File(soundPath).open() : null;
    if (reader != null) {
      await reader.setPosition(audioInfo.dataOffset);
    }
    var offset = 0;
    var remaining = convertedPcm?.length ?? audioInfo.dataLength;
    final sampleRate = convertedPcm == null
        ? audioInfo.sampleRate
        : XfyunAudioUtils.defaultSampleRate;
    var status = 0;
    var sentAudio = false;
    try {
      while (remaining > 0 && !token.isCancelled) {
        final chunkSize = min(_frameSize, remaining);
        final chunk = convertedPcm == null
            ? await reader!.read(chunkSize)
            : Uint8List.sublistView(convertedPcm, offset, offset + chunkSize);
        if (chunk.isEmpty) {
          break;
        }
        offset += chunk.length;
        remaining -= chunk.length;
        final frame = <String, dynamic>{
          if (status == 0) ...{
            'common': {'app_id': IMDemoConfig.xfyunAppId},
            'business': {
              'language': IMDemoConfig.xfyunIatLanguage,
              'domain': 'iat',
              'accent': IMDemoConfig.xfyunIatAccent,
              'vad_eos': 3000,
              'ptt': 1,
            },
          },
          'data': {
            'status': status,
            'format': 'audio/L16;rate=$sampleRate',
            'encoding': 'raw',
            'audio': base64.encode(chunk),
          },
        };
        channel.sink.add(jsonEncode(frame));
        sentAudio = true;
        status = 1;
        if (remaining > 0) {
          await Future.any<void>([
            Future<void>.delayed(_frameInterval),
            token.whenCancelled,
          ]);
        }
      }
      if (!token.isCancelled && sentAudio) {
        channel.sink.add(
          jsonEncode({
            'data': {'status': 2},
          }),
        );
      }
    } finally {
      await reader?.close();
    }
  }

  static String _mergeResult({
    required Map<int, String> segments,
    required Map<String, dynamic> result,
    required String fallback,
  }) {
    final words = _extractWords(result);
    if (words.isEmpty) {
      return fallback;
    }

    final sn = result['sn'];
    if (sn is! int) {
      return fallback.isEmpty ? words : '$fallback$words';
    }

    final pgs = result['pgs']?.toString();
    if (pgs == 'rpl') {
      final rg = result['rg'];
      if (rg is List && rg.length >= 2) {
        final start = (rg[0] as num).toInt();
        final end = (rg[1] as num).toInt();
        for (var i = start; i <= end; i++) {
          segments.remove(i);
        }
      }
      segments[sn] = words;
    } else {
      segments[sn] = words;
    }

    final buffer = StringBuffer();
    for (final key in segments.keys.toList()..sort()) {
      buffer.write(segments[key]);
    }
    return buffer.toString();
  }

  static String _extractWords(Map<String, dynamic> result) {
    final ws = result['ws'];
    if (ws is! List) {
      return '';
    }
    final buffer = StringBuffer();
    for (final wsItem in ws) {
      if (wsItem is! Map<String, dynamic>) {
        continue;
      }
      final cw = wsItem['cw'];
      if (cw is! List) {
        continue;
      }
      for (final cwItem in cw) {
        if (cwItem is Map<String, dynamic>) {
          final word = cwItem['w'];
          if (word is String) {
            buffer.write(word);
          }
        }
      }
    }
    return buffer.toString();
  }
}
