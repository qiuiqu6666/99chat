import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

typedef OutboxKeyReader = Future<String?> Function();
typedef OutboxKeyWriter = Future<void> Function(String value);
typedef OutboxRandomBytes = Uint8List Function(int length);

class ProtectedOutboxPayload {
  const ProtectedOutboxPayload({
    required this.value,
    required this.keyId,
    required this.nonce,
  });

  final String value;
  final String keyId;
  final String nonce;

  static const int encryptionVersion = 1;
  static const String cipherAlgorithm = 'AES-256-GCM';
}

class OutboxPayloadCipher {
  OutboxPayloadCipher({
    OutboxKeyReader? readKey,
    OutboxKeyWriter? writeKey,
    OutboxRandomBytes? randomBytes,
  })  : _readKey = readKey ?? _readSecureKey,
        _writeKey = writeKey ?? _writeSecureKey,
        _randomBytes = randomBytes ?? _secureRandomBytes;

  static final OutboxPayloadCipher instance = OutboxPayloadCipher();

  static const String _prefix = 'im-outbox:v1:';
  static const String _storageKey = 'im_outbox_payload_key_v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  final OutboxKeyReader _readKey;
  final OutboxKeyWriter _writeKey;
  final OutboxRandomBytes _randomBytes;

  Future<ProtectedOutboxPayload?> protect({
    required String ownerUserId,
    required String plaintext,
  }) async {
    try {
      final key = await _loadOrCreateKey();
      final nonce = _randomBytes(12);
      final keyId = sha256.convert(key).toString().substring(0, 16);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List.fromList(utf8.encode(ownerUserId.trim())),
          ),
        );
      final encrypted = cipher.process(
        Uint8List.fromList(utf8.encode(plaintext)),
      );
      final nonceText = base64UrlEncode(nonce);
      return ProtectedOutboxPayload(
        value: '$_prefix$keyId:$nonceText:${base64UrlEncode(encrypted)}',
        keyId: keyId,
        nonce: nonceText,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> reveal({
    required String ownerUserId,
    required String value,
  }) async {
    if (!value.startsWith(_prefix)) return value;
    try {
      final parts = value.substring(_prefix.length).split(':');
      if (parts.length != 3) return null;
      final key = await _loadExistingKey();
      if (key == null) return null;
      final expectedKeyId = sha256.convert(key).toString().substring(0, 16);
      if (parts[0] != expectedKeyId) return null;
      final nonce = base64Url.decode(parts[1]);
      final encrypted = base64Url.decode(parts[2]);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List.fromList(utf8.encode(ownerUserId.trim())),
          ),
        );
      return utf8.decode(cipher.process(encrypted));
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _loadOrCreateKey() async {
    final existing = await _loadExistingKey();
    if (existing != null) return existing;
    final created = _randomBytes(32);
    await _writeKey(base64UrlEncode(created));
    return created;
  }

  Future<Uint8List?> _loadExistingKey() async {
    final encoded = await _readKey();
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = base64Url.decode(encoded);
    return decoded.length == 32 ? decoded : null;
  }

  static Future<String?> _readSecureKey() {
    return _secureStorage.read(key: _storageKey);
  }

  static Future<void> _writeSecureKey(String value) {
    return _secureStorage.write(key: _storageKey, value: value);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
