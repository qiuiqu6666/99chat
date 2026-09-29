import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final failOldWrite in [false, true]) {
    test(
        'shared credential lane drains old ${failOldWrite ? 'failure' : 'save'} before clear and new session',
        () async {
      final values = <String, String>{};
      final calls = <String>[];
      final entered = Completer<void>();
      final release = Completer<void>();
      var first = true;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String;
        calls.add('${call.method}:$key');
        if (call.method == 'write') {
          if (first) {
            first = false;
            entered.complete();
            await release.future;
            if (failOldWrite) throw PlatformException(code: 'storage_failure');
          }
          values[key] = args['value'] as String;
        } else if (call.method == 'delete') {
          values.remove(key);
        } else if (call.method == 'read') {
          return values[key];
        }
        return null;
      });
      final oldStore = SessionStore(storage: const FlutterSecureStorage());
      final nextStore = SessionStore(storage: const FlutterSecureStorage());
      final old = oldStore.saveImCredential(
          sdkAppId: 1, userSig: 'old-sig', expiresIn: 3600);
      final oldOutcome =
          old.then<Object?>((_) => null, onError: (Object error) => error);
      await entered.future;
      final clear = nextStore.clear();
      final business = nextStore.saveBusinessSession(
          token: 'new-token', userId: 'new-owner');
      final credential = nextStore.saveImCredential(
          sdkAppId: 2, userSig: 'new-sig', expiresIn: 3600);
      await Future<void>.delayed(Duration.zero);
      final beforeRelease = List<String>.of(calls);
      release.complete();
      final result = await oldOutcome;
      await Future.wait([clear, business, credential]);
      expect(beforeRelease, ['write:session.sdk_app_id']);
      if (failOldWrite) expect(result, isA<PlatformException>());
      expect(values['session.business_token'], 'new-token');
      expect(values['session.user_id'], 'new-owner');
      expect(values['session.sdk_app_id'], '2');
      expect(values['session.im_user_sig'], 'new-sig');
    });
  }
}
