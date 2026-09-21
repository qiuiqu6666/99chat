/// Dedup / in-flight marks for wallet-card outbound sends (per conversation).
class WalletCardOutboundSidecar {
  WalletCardOutboundSidecar._();

  static final WalletCardOutboundSidecar instance = WalletCardOutboundSidecar._();

  final Map<String, Set<String>> sentByConv = <String, Set<String>>{};
  final Map<String, Set<String>> sendingMarksByConv = <String, Set<String>>{};
  final Map<String, int> retryingConvs = <String, int>{};

  Set<String> sentMarksFor(String convId) =>
      sentByConv.putIfAbsent(convId, () => <String>{});

  Set<String> sendingMarksFor(String convId) =>
      sendingMarksByConv.putIfAbsent(convId, () => <String>{});

  bool beginRetry(String convId) {
    final id = convId.trim();
    if (id.isEmpty) return false;
    retryingConvs[id] = (retryingConvs[id] ?? 0) + 1;
    return true;
  }

  void endRetry(String convId) {
    final id = convId.trim();
    final next = (retryingConvs[id] ?? 1) - 1;
    if (next <= 0) {
      retryingConvs.remove(id);
    } else {
      retryingConvs[id] = next;
    }
  }

  void resetForConversation(String convId) {
    sentByConv.remove(convId);
    sendingMarksByConv.remove(convId);
    retryingConvs.remove(convId);
  }
}
