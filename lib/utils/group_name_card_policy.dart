import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';

/// 群名片按可见字符计数，同时遵守 IM 的 50 字节 UTF-8 上限。
class GroupNameCardPolicy {
  GroupNameCardPolicy._();

  static const int minLength = 2;
  static const int maxLength = 20;
  static const int maxUtf8Bytes = 50;

  static bool isLengthValid(String text) {
    final trimmed = text.trim();
    final length = trimmed.characters.length;
    return length >= minLength &&
        length <= maxLength &&
        utf8.encode(trimmed).length <= maxUtf8Bytes;
  }

  static String? validationMessage(String text) {
    final trimmed = text.trim();
    final length = trimmed.characters.length;
    if (length < minLength || length > maxLength) {
      return AppI18n.current.t(
        zhHans: '请输入2-20个字的昵称',
        zhHant: '請輸入2-20個字的暱稱',
        en: 'Enter a nickname of 2–20 characters',
        ja: '2〜20文字のニックネームを入力してください',
        ko: '2~20자 닉네임을 입력하세요',
      );
    }
    if (utf8.encode(trimmed).length > maxUtf8Bytes) {
      return AppI18n.current.t(
        zhHans: '群昵称过长，请减少文字或表情后重试',
        zhHant: '群暱稱過長，請減少文字或表情後重試',
        en: 'Group nickname is too long. Use fewer characters or emoji.',
        ja: 'グループ内ニックネームが長すぎます。文字や絵文字を減らしてください。',
        ko: '그룹 닉네임이 너무 깁니다. 문자나 이모지를 줄여주세요.',
      );
    }
    return null;
  }
}
