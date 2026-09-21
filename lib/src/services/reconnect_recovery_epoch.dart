/// Counts genuine IM reconnects: a socket that was connected, dropped, and
/// then reported `onConnectSuccess` again.
///
/// The handshake display period, repeated connect-success callbacks without an
/// intermediate drop, and cold-start first connections never advance the
/// epoch. Chat latest-window trust and `OpenViewportCache` entries are stamped
/// with this value; a mismatch means the cached latest window predates a real
/// reconnect and can no longer prove freshness.
class ReconnectRecoveryEpoch {
  int _epoch = 0;
  bool _droppedAfterConnect = false;

  int get epoch => _epoch;

  /// Whether a drop has been observed since the last successful connection.
  bool get hasPendingDrop => _droppedAfterConnect;

  /// Called when the socket that had been connected reports a disconnect or a
  /// reconnecting state.
  void onDisconnectedAfterConnected() {
    _droppedAfterConnect = true;
  }

  /// Called on every `onConnectSuccess`. Returns true when this success closes
  /// a real drop and the epoch advanced.
  bool onConnectSuccess() {
    if (!_droppedAfterConnect) {
      return false;
    }
    _epoch++;
    _droppedAfterConnect = false;
    return true;
  }

  /// Logout / account switch. The epoch never rewinds so stale stamps from the
  /// previous session can never match again.
  void resetLaunchSession() {
    _droppedAfterConnect = false;
  }
}
