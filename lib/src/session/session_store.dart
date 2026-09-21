import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'session.business_token';
  static const _userIdKey = 'session.user_id';
  static const _sdkAppIdKey = 'session.sdk_app_id';
  static const _imUserSigKey = 'session.im_user_sig';
  static const _imExpiresAtKey = 'session.im_expires_at';

  Future<String?> readBusinessToken() => _storage.read(key: _tokenKey);
  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  Future<void> saveBusinessSession({
    required String token,
    required String userId,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<void> saveImCredential({
    required int sdkAppId,
    required String userSig,
    required int expiresIn,
  }) async {
    await _storage.write(key: _sdkAppIdKey, value: '$sdkAppId');
    await _storage.write(key: _imUserSigKey, value: userSig);
    await _storage.write(
      key: _imExpiresAtKey,
      value: '${DateTime.now().millisecondsSinceEpoch + expiresIn * 1000}',
    );
  }

  Future<(int, String)?> readImCredential() async {
    final appId = await _storage.read(key: _sdkAppIdKey);
    final sig = await _storage.read(key: _imUserSigKey);
    final parsed = int.tryParse(appId ?? '');
    final expiresAt = int.tryParse(await _storage.read(key: _imExpiresAtKey) ?? '');
    if (parsed == null || parsed <= 0 || sig == null || sig.isEmpty ||
        expiresAt == null || expiresAt <= DateTime.now().millisecondsSinceEpoch + 30000) {
      return null;
    }
    return (parsed, sig);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _sdkAppIdKey),
      _storage.delete(key: _imUserSigKey),
      _storage.delete(key: _imExpiresAtKey),
    ]);
  }
}
