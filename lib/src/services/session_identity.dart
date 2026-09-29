import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_session_cache.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// Identity captured by an asynchronous operation.
class SessionIdentity {
  const SessionIdentity({required this.ownerUserId, required this.generation});

  final String ownerUserId;
  final int generation;

  @override
  bool operator ==(Object other) {
    return other is SessionIdentity &&
        other.ownerUserId == ownerUserId &&
        other.generation == generation;
  }

  @override
  int get hashCode => Object.hash(ownerUserId, generation);
}

/// Process-wide account boundary for operations that outlive a route.
class SessionIdentityService {
  SessionIdentityService._();

  static final SessionIdentityService instance = SessionIdentityService._();

  int _generation = 0;
  final Set<void Function(int generation, String reason)>
      _invalidationListeners = <void Function(int, String)>{};

  int get generation => _generation;

  void addInvalidationListener(
      void Function(int generation, String reason) listener) {
    _invalidationListeners.add(listener);
  }

  void removeInvalidationListener(
    void Function(int generation, String reason) listener,
  ) {
    _invalidationListeners.remove(listener);
  }

  /// Resolves the owner before logout clears any IM or token state.
  /// The encrypted cache is a last resort for kicked-offline flows where the
  /// SDK has already discarded its live login user.
  Future<String> resolveCurrentOwnerUserId() async {
    var owner = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    if (owner.isNotEmpty) {
      return owner;
    }
    owner = ChatIdFormat.rawUserUid(ApiClient.instance.authenticatedUserId);
    if (owner.isNotEmpty) {
      return owner;
    }
    try {
      final login = await TencentImSDKPlugin.v2TIMManager
          .getLoginUser()
          .timeout(const Duration(seconds: 2));
      owner = ChatIdFormat.rawUserUid(login.data);
    } catch (_) {}
    if (owner.isNotEmpty) {
      return owner;
    }
    try {
      owner = ChatIdFormat.rawUserUid(
        await ImSessionCache.instance.readCachedUserId(),
      );
    } catch (_) {}
    return owner;
  }

  SessionIdentity capture({String? ownerUserId}) {
    final owner = ChatIdFormat.rawUserUid(
      ownerUserId ?? ContactSocialCacheStore.safeLoginUserId(),
    );
    return SessionIdentity(ownerUserId: owner, generation: _generation);
  }

  bool isCurrent(
    SessionIdentity identity, {
    String? currentOwnerUserId,
  }) {
    final currentOwner = ChatIdFormat.rawUserUid(
      currentOwnerUserId ?? ContactSocialCacheStore.safeLoginUserId(),
    );
    return identity.ownerUserId.isNotEmpty &&
        identity.generation == _generation &&
        identity.ownerUserId == currentOwner;
  }

  /// Generation-only guard for authentication work that starts before UIKit
  /// has installed the new account owner.
  bool isGenerationCurrent(int generation) => generation == _generation;

  /// Invalidates all operations started before the account boundary.
  int invalidate({String reason = 'session_boundary'}) {
    _generation++;
    for (final listener in List.of(_invalidationListeners)) {
      try {
        listener(_generation, reason);
      } catch (_) {}
    }
    return _generation;
  }
}
