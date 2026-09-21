import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/user_api_error_message.dart';

void main() {
  test('maps ADD_FRIEND_VIA_GROUP_DISABLED away from raw backend code', () {
    final text = UserApiErrorMessage.fromAddFriendReasonCode(
      'ADD_FRIEND_VIA_GROUP_DISABLED',
      fallback: 'fallback',
    );
    expect(text, isNot(contains('ADD_FRIEND_VIA_GROUP_DISABLED')));
    expect(text.toLowerCase(), anyOf(contains('group'), contains('群聊')));
  });

  test('maps ADD_FRIEND_VIA_CARD_DISABLED away from raw backend code', () {
    final text = UserApiErrorMessage.fromAddFriendReasonCode(
      'ADD_FRIEND_VIA_CARD_DISABLED',
      fallback: 'fallback',
    );
    expect(text, isNot(contains('ADD_FRIEND_VIA_CARD_DISABLED')));
    expect(text.toLowerCase(), anyOf(contains('card'), contains('名片')));
  });

  test('unknown backend enum uses fallback instead of raw code', () {
    final text = UserApiErrorMessage.fromAddFriendReasonCode(
      'SOME_UNKNOWN_ENUM_CODE',
      fallback: '可读提示',
    );
    expect(text, '可读提示');
  });

  test('fromFriendRequest keeps USER_NOT_FOUND as user-not-found copy', () {
    final text = UserApiErrorMessage.fromFriendRequest(
      _friendRequestError(code: 'USER_NOT_FOUND'),
    );
    expect(text, anyOf(contains('对方不存在'), contains('User not found')));
    expect(text, isNot(contains('违反平台规范')));
  });

  test('fromAddFriendReasonCode keeps USER_NOT_FOUND as fallback', () {
    final text = UserApiErrorMessage.fromAddFriendReasonCode(
      'USER_NOT_FOUND',
      fallback: '可读提示',
    );
    expect(text, '可读提示');
  });

  test('open-profile mapper uses restriction copy for USER_NOT_FOUND', () {
    final reasonText = UserApiErrorMessage.fromAddFriendReasonCodeOnOpenProfile(
      'USER_NOT_FOUND',
      fallback: '可读提示',
    );
    final requestText = UserApiErrorMessage.fromFriendRequestOnOpenProfile(
      _friendRequestError(code: 'USER_NOT_FOUND'),
    );
    expect(reasonText, contains('违反平台规范'));
    expect(reasonText, contains('暂时无法添加好友'));
    expect(requestText, contains('违反平台规范'));
    expect(requestText, contains('暂时无法添加好友'));
  });

  test('open-profile mapper uses restriction copy for ACCOUNT_DISABLED', () {
    final reasonText = UserApiErrorMessage.fromAddFriendReasonCodeOnOpenProfile(
      'ACCOUNT_DISABLED',
      fallback: '可读提示',
    );
    final requestText = UserApiErrorMessage.fromFriendRequestOnOpenProfile(
      _friendRequestError(code: 'ACCOUNT_DISABLED'),
    );
    expect(reasonText, contains('违反平台规范'));
    expect(reasonText, contains('暂时无法添加好友'));
    expect(requestText, contains('违反平台规范'));
    expect(requestText, contains('暂时无法添加好友'));
  });

  test('open-profile mapper keeps USER_BLOCKED as block copy', () {
    final text = UserApiErrorMessage.fromFriendRequestOnOpenProfile(
      _friendRequestError(code: 'USER_BLOCKED'),
    );
    expect(text, anyOf(contains('拉黑'), contains('block')));
    expect(text, isNot(contains('违反平台规范')));
  });

  test('isOpenProfileRestrictedAddFriendCode matches only the two codes', () {
    expect(
      UserApiErrorMessage.isOpenProfileRestrictedAddFriendCode('USER_NOT_FOUND'),
      isTrue,
    );
    expect(
      UserApiErrorMessage.isOpenProfileRestrictedAddFriendCode(
        'ACCOUNT_DISABLED',
      ),
      isTrue,
    );
    expect(
      UserApiErrorMessage.isOpenProfileRestrictedAddFriendCode(
        'FRIEND_NOT_FOUND',
      ),
      isFalse,
    );
    expect(
      UserApiErrorMessage.isOpenProfileRestrictedAddFriendCode(''),
      isFalse,
    );
  });
}

DioError _friendRequestError({required String code}) {
  return DioError(
    requestOptions: RequestOptions(path: '/friend-requests'),
    response: Response(
      requestOptions: RequestOptions(path: '/friend-requests'),
      statusCode: 404,
      data: {'code': code},
    ),
    type: DioErrorType.response,
  );
}

