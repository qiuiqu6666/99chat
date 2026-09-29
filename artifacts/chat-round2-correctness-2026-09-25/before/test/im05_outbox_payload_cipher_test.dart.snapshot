import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';

void main() {
  late String storedKey;
  late OutboxPayloadCipher cipher;

  setUp(() {
    storedKey = '';
    var seed = 0;
    cipher = OutboxPayloadCipher(
      readKey: () async => storedKey.isEmpty ? null : storedKey,
      writeKey: (value) async => storedKey = value,
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => seed++ & 0xff),
      ),
    );
  });

  test('AES-GCM round trip does not persist plaintext', () async {
    const plaintext = '{"message":{"text":"private chat"}}';
    final protected = await cipher.protect(
      ownerUserId: 'alice',
      plaintext: plaintext,
    );
    expect(protected, isNotNull);
    expect(protected!.value, startsWith('im-outbox:v1:'));
    expect(protected.value, isNot(contains('private chat')));
    expect(base64Url.decode(storedKey), hasLength(32));
    expect(
      await cipher.reveal(ownerUserId: 'alice', value: protected.value),
      plaintext,
    );
  });

  test('owner mismatch and ciphertext tampering are rejected', () async {
    final protected = await cipher.protect(
      ownerUserId: 'alice',
      plaintext: 'payload',
    );
    expect(
      await cipher.reveal(ownerUserId: 'bob', value: protected!.value),
      isNull,
    );
    final tampered =
        '${protected.value.substring(0, protected.value.length - 2)}AA';
    expect(
      await cipher.reveal(ownerUserId: 'alice', value: tampered),
      isNull,
    );
  });

  test('legacy plaintext stays readable during migration', () async {
    expect(
      await cipher.reveal(ownerUserId: 'alice', value: 'legacy-json'),
      'legacy-json',
    );
  });

  test('missing or rotated key cannot decrypt a Prepared payload', () async {
    final protected = await cipher.protect(
      ownerUserId: 'alice',
      plaintext: '{"schemaVersion":1}',
    );
    expect(protected, isNotNull);

    storedKey = '';
    expect(
      await cipher.reveal(
        ownerUserId: 'alice',
        value: protected!.value,
      ),
      isNull,
    );

    storedKey = base64UrlEncode(Uint8List.fromList(List<int>.filled(32, 9)));
    expect(
      await cipher.reveal(
        ownerUserId: 'alice',
        value: protected.value,
      ),
      isNull,
    );
  });
}
