import 'dart:typed_data';
import '../api/upload_api.dart';

/// Runs only after registration has established the authenticated session.
Future<void> uploadRegistrationAvatar(Uint8List bytes, String filename) async {
  await UploadApi.instance
      .uploadUserAvatarBytes(bytes: bytes, filename: filename);
}
