import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';

/// Carries a safe, actionable message through the editor's bool callback.
class GroupNameCardSaveFailure implements Exception {
  const GroupNameCardSaveFailure(this.message, {this.code = 'SAVE_FAILED'});

  final String code;
  final String message;

  factory GroupNameCardSaveFailure.fromResponse({
    Object? code,
    String? description,
  }) {
    final reason = (description ?? '').trim();
    final key = reason.toUpperCase();
    final i18n = AppI18n.current;
    String message;
    if (key == 'SAVE_TIMEOUT' || key == 'TIMEOUT') {
      message = i18n.t(
        zhHans: '保存结果暂未确认，请检查网络后重试',
        zhHant: '儲存結果暫未確認，請檢查網路後重試',
        en: 'Save could not be confirmed. Check your connection and retry.',
      );
    } else if (key == 'AUTH_NOT_READY' ||
        key == 'NOT_SELF' ||
        key == 'SESSION_CHANGED' ||
        code == 401) {
      message = i18n.t(
        zhHans: '登录状态正在恢复，请稍后重新进入群聊再试',
        zhHant: '登入狀態正在恢復，請稍後重新進入群聊再試',
        en: 'Login state has changed. Reopen the group and try again.',
      );
    } else if (key == 'GROUP_NOT_FOUND' || key == 'NOT_GROUP_MEMBER') {
      message = i18n.t(
        zhHans: '群聊不存在或你已不在群中，请重新进入群聊确认',
        zhHant: '群聊不存在或你已不在群中，請重新進入群聊確認',
        en: 'The group is unavailable or you are no longer a member.',
      );
    } else if (code == 429 || key == 'RATE_LIMITED') {
      message = i18n.t(
        zhHans: '操作过于频繁，请稍后再试',
        zhHant: '操作過於頻繁，請稍後再試',
        en: 'Too many requests. Please try again shortly.',
      );
    } else if (key == 'IM_REST_ERROR' ||
        key == 'IM_NOT_CONFIGURED' ||
        key == 'BRIDGE_DISABLED' ||
        (code is int && code >= 500 && code < 600)) {
      message = i18n.t(
        zhHans: '群昵称服务暂不可用，请稍后重试',
        zhHant: '群暱稱服務暫不可用，請稍後重試',
        en: 'Group nickname service is unavailable. Please try again later.',
      );
    } else {
      message = DioErrorMessage.sanitizeUserText(reason,
          fallback: i18n.t(
            zhHans: '群昵称未能保存，请稍后重试',
            zhHant: '群暱稱未能儲存，請稍後重試',
            en: 'Could not save the group nickname. Please try again.',
          ));
    }
    return GroupNameCardSaveFailure(message,
        code: code?.toString() ?? (reason.isEmpty ? 'SAVE_FAILED' : reason));
  }

  factory GroupNameCardSaveFailure.fromError(Object error) {
    if (error is GroupNameCardSaveFailure) return error;
    if (error is TimeoutException ||
        (error is DioError &&
            (error.type == DioErrorType.connectTimeout ||
                error.type == DioErrorType.sendTimeout ||
                error.type == DioErrorType.receiveTimeout))) {
      return GroupNameCardSaveFailure.fromResponse(description: 'SAVE_TIMEOUT');
    }
    if (error is DioError) {
      final data = error.response?.data;
      final map = data is Map ? data : const {};
      final businessCode = map['code']?.toString();
      final rawMessage = map['message']?.toString() ?? map['error']?.toString();
      // Generic/numeric API codes must not hide a useful server message.
      final mappedCode = const {
        'SAVE_TIMEOUT',
        'TIMEOUT',
        'AUTH_NOT_READY',
        'NOT_SELF',
        'SESSION_CHANGED',
        'GROUP_NOT_FOUND',
        'NOT_GROUP_MEMBER',
        'RATE_LIMITED',
        'IM_REST_ERROR',
        'IM_NOT_CONFIGURED',
        'BRIDGE_DISABLED',
      }.contains(businessCode);
      final failure = GroupNameCardSaveFailure.fromResponse(
        code: error.response?.statusCode,
        description: mappedCode ? businessCode : (rawMessage ?? businessCode),
      );
      return GroupNameCardSaveFailure(
        error.response == null
            ? DioErrorMessage.forApp(error)
            : failure.message,
        code: businessCode ??
            error.response?.statusCode?.toString() ??
            error.type.name,
      );
    }
    return GroupNameCardSaveFailure.fromResponse();
  }

  @override
  String toString() => message;
}
