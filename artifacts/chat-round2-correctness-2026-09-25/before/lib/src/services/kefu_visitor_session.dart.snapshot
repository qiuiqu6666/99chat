import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/kefu_visitor_api.dart';
import 'package:tencent_cloud_chat_demo/utils/customer_service_url_builder.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';
import 'package:uuid/uuid.dart';

class KefuVisitorSession {
  const KefuVisitorSession({
    required this.identifier,
    required this.sourceId,
    required this.pubsubToken,
    required this.conversationId,
  });

  final String identifier;
  final String sourceId;
  final String pubsubToken;
  final String conversationId;

  static const String _kIdentifier = 'kefu_visitor_identifier';
  static const String _kSourceId = 'kefu_visitor_source_id';
  static const String _kPubsub = 'kefu_visitor_pubsub_token';
  static const String _kConversation = 'kefu_visitor_conversation_id';
  static const String _kBase = 'kefu_visitor_base_url';

  static Future<KefuVisitorSession> ensure() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBase = KefuVisitorApi.instance.kefuBase;
    final savedBase = prefs.getString(_kBase) ?? '';
    final profile = await _contactProfile();

    var identifier = prefs.getString(_kIdentifier)?.trim() ?? '';
    if (identifier.isEmpty) {
      identifier = const Uuid().v4();
      await prefs.setString(_kIdentifier, identifier);
    }

    if (savedBase != currentBase) {
      await prefs.remove(_kSourceId);
      await prefs.remove(_kPubsub);
      await prefs.remove(_kConversation);
      await prefs.setString(_kBase, currentBase);
    }

    var sourceId = prefs.getString(_kSourceId)?.trim() ?? '';
    var pubsubToken = prefs.getString(_kPubsub)?.trim() ?? '';
    if (sourceId.isEmpty || pubsubToken.isEmpty) {
      final contact = await KefuVisitorApi.instance.createContact(
        identifier: identifier,
        name: profile.name,
        avatarUrl: profile.avatarUrl,
      );
      sourceId = contact.sourceId;
      pubsubToken = contact.pubsubToken;
      await prefs.setString(_kSourceId, sourceId);
      await prefs.setString(_kPubsub, pubsubToken);
    } else {
      try {
        await KefuVisitorApi.instance.updateContact(
          sourceId: sourceId,
          name: profile.name,
          avatarUrl: profile.avatarUrl,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('CUSTOMER_SERVICE update contact: $e');
        }
      }
    }

    var conversationId = prefs.getString(_kConversation)?.trim() ?? '';
    if (conversationId.isEmpty) {
      conversationId =
          await KefuVisitorApi.instance.createConversation(sourceId);
      await prefs.setString(_kConversation, conversationId);
    }

    return KefuVisitorSession(
      identifier: identifier,
      sourceId: sourceId,
      pubsubToken: pubsubToken,
      conversationId: conversationId,
    );
  }

  static Future<({String name, String avatarUrl})> _contactProfile() async {
    var name = '访客';
    var avatarUrl = CustomerServiceUrlBuilder.guestAvatarUrl;
    try {
      final visitor = await CustomerServiceUrlBuilder.resolveVisitor();
      final resolvedName = visitor.name.trim();
      if (resolvedName.isNotEmpty) {
        name = resolvedName;
      }
      final resolvedAvatar = visitor.avatar.trim();
      if (_isPublicHttpAvatar(resolvedAvatar)) {
        avatarUrl = resolvedAvatar;
      }
    } catch (_) {}
    if (!_isPublicHttpAvatar(avatarUrl)) {
      avatarUrl = '';
    }
    return (name: name, avatarUrl: avatarUrl);
  }

  static bool _isPublicHttpAvatar(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.startsWith('file:') || trimmed.startsWith('data:')) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host.endsWith('.local')) {
      return false;
    }
    return MediaUrlResolver.authHeadersFor(trimmed) == null;
  }
}
