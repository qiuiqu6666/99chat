import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';

/// Lives above the navigator, so business-token expiry also ends sessions
/// while chat/IM is healthy and no HTTP request is being made.
class BusinessSessionGuard extends StatefulWidget {
  const BusinessSessionGuard({super.key, required this.child, this.now});

  final Widget child;
  final DateTime Function()? now;

  @override
  State<BusinessSessionGuard> createState() => _BusinessSessionGuardState();
}

class _BusinessSessionGuardState extends State<BusinessSessionGuard>
    with WidgetsBindingObserver {
  Timer? _expiryTimer;
  final _client = ApiClient.instance;
  bool _foreground = true;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    _client.sessionRevision.addListener(_schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schedule();
    });
  }

  void _schedule() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (!_foreground || _client.isLogoutInProgress) return;
    final deadline = ApiClient.jwtExpiresAt(_client.token);
    if (deadline == null) return;
    final remaining = deadline.difference(_now);
    if (remaining <= Duration.zero) {
      // Defer navigation until credential writes / the current build finish.
      _expiryTimer = Timer(Duration.zero, () {
        unawaited(_client.expireSessionIfNeeded(now: _now));
      });
    } else {
      // Bound long timers (including the browser's timer range), and re-read
      // the wall clock to tolerate system clock corrections.
      final delay = remaining > const Duration(minutes: 1)
          ? const Duration(minutes: 1)
          : remaining;
      _expiryTimer = Timer(delay, _schedule);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _schedule();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _client.sessionRevision.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
