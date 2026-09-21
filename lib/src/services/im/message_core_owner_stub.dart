import 'package:uuid/uuid.dart';

class MessageCoreOwner {
  static final MessageCoreOwner instance = MessageCoreOwner();
  final String id = 'flutter-message-core:${const Uuid().v4()}';
  Future<void> ensureReady() async {}
  Future<String> prepareLeaseOwner() async => id;
  Future<bool> isAbandoned(String ownerId) async => false;
}
