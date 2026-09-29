import '../../session/session_state.dart';

/// Search follows the login lifecycle, not the asynchronously loaded profile.
/// The SDK still reports transport/local-search availability on each request.
String resolveSearchAccountOwner({
  required SessionState session,
  required String authenticatedUserId,
  String coreUserId = '',
  bool coreLoginSucceeded = false,
}) {
  final authenticated = authenticatedUserId.trim();
  if (session.phase == SessionPhase.ready ||
      session.phase == SessionPhase.offline) {
    final owner = session.userId?.trim() ?? '';
    // A changed business credential must never search the previous IM account.
    return authenticated.isEmpty || authenticated == owner ? owner : '';
  }

  // Compatibility for a UIKit-owned login before SessionManager takes over.
  // Never resurrect a cached UIKit identity during logout or account switching.
  if (session.phase == SessionPhase.unknown && coreLoginSucceeded) {
    final owner = coreUserId.trim();
    if (owner.isNotEmpty && owner == authenticated) return owner;
  }
  return '';
}
