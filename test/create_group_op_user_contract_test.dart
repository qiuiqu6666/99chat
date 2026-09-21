import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';

void main() {
  group('resolveCreateGroupOpUser', () {
    test('prefers UIKit nickName', () {
      final result = resolveCreateGroupOpUser(
        coreUser: V2TimUserFullInfo(userID: 'u1', nickName: ' 秋 '),
        providerUser: V2TimUserFullInfo(userID: 'p1', nickName: 'provider'),
        fallbackUserId: 'fallback',
      );
      expect(result, '秋');
    });

    test('falls back to UIKit userID when nickName is blank', () {
      final result = resolveCreateGroupOpUser(
        coreUser: V2TimUserFullInfo(userID: 'u1', nickName: '  '),
        providerUser: null,
        fallbackUserId: 'fallback',
      );
      expect(result, 'u1');
    });

    test('uses business LoginUserInfo when UIKit login info is null', () {
      final result = resolveCreateGroupOpUser(
        coreUser: null,
        providerUser: V2TimUserFullInfo(userID: 'p1', nickName: 'provider'),
        fallbackUserId: 'fallback',
      );
      expect(result, 'provider');
    });

    test('uses fallbackUserId when both user infos are null', () {
      final result = resolveCreateGroupOpUser(
        coreUser: null,
        providerUser: null,
        fallbackUserId: ' fallback ',
      );
      expect(result, 'fallback');
    });

    test('returns empty string instead of throwing when everything is empty',
        () {
      final result = resolveCreateGroupOpUser(
        coreUser: V2TimUserFullInfo(),
        providerUser: V2TimUserFullInfo(),
        fallbackUserId: '',
      );
      expect(result, '');
    });
  });

  group('create group flow never depends on non-null UIKit loginUserInfo', () {
    final source = File('lib/src/create_group.dart').readAsStringSync();

    test('no null assertion on loginUserInfo', () {
      expect(source, isNot(contains('loginUserInfo!')));
    });

    test('opUser goes through the null-safe resolver', () {
      expect(source, contains('"opUser": _resolveCreateGroupOpUser()'));
    });

    test('created group id is tracked for the outer catch feedback', () {
      expect(source, contains('createdGroupId = record.groupId.trim();'));
      expect(source, contains('群已创建，请在群聊列表中打开'));
    });
  });

  test('primeUIKitSession primes didLoginSuccess when the Dart login hangs',
      () {
    final source =
        File('lib/src/services/auth_bootstrap_service.dart').readAsStringSync();
    final start = source.indexOf('Future<void> primeUIKitSession(');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('bool isCoreServicesUserReady()', start);
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('on TimeoutException'));
    expect(body, contains('isNativeLoggedIn(sig)'));
    expect(body, contains('TIMUIKitCore.getInstance().didLoginSuccess()'));

    // The prime must sit inside its own try/catch within the timeout clause:
    // sibling `catch (e)` does not cover `on TimeoutException`, so an escape
    // here would abort every caller that bare-awaits primeUIKitSession.
    final timeoutIdx = body.indexOf('on TimeoutException');
    expect(timeoutIdx, greaterThanOrEqualTo(0));
    final nativeIdx = body.indexOf('isNativeLoggedIn(sig)', timeoutIdx);
    expect(nativeIdx, greaterThan(timeoutIdx));
    final innerTryIdx = body.indexOf('try {', timeoutIdx);
    expect(innerTryIdx, greaterThan(timeoutIdx));
    expect(innerTryIdx, lessThan(nativeIdx));
    final primeIdx = body.indexOf('didLoginSuccess()', innerTryIdx);
    expect(primeIdx, greaterThan(innerTryIdx));
    final innerCatchIdx = body.indexOf('} catch (e) {', primeIdx);
    expect(innerCatchIdx, greaterThan(primeIdx));
    expect(body, contains('primeUIKitSession didLoginSuccess prime error'));
  });
}
