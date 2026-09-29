const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const r=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,100));s=s.replace(a,b);}; fn(r,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
edit('lib/src/chat.dart',(r)=>{
 r('    _restoreActiveChatRegistry();\n    _clearMountedDisplayListCache();\n    final convKey',`    _restoreActiveChatRegistry();
    // A maintained route already owns its message anchors and relative offset.
    // Ordinary returns must not reset its window or schedule a stale scroll.
    if (_hasVisibleHistoryMessages()) return;
    _clearMountedDisplayListCache();
    final convKey`);
 const old=`    } else {
      // 有缓存消息仍空白时：贴底 + 轻量刷新驱动列表重绘。
      try {
        final scroll = _chatController.scrollController;
        if (scroll != null && scroll.hasClients) {
          scroll.jumpTo(scroll.position.minScrollExtent);
        }
      } catch (_) {}
      ChatDiagLog.log(
        'ChatHistory',
        'overlay_return_refresh_ui',
        conversationID: _resolvedConversationID(),
        extras: <String, Object?>{
          'reason': reason,
          'rawCount':
              convKey.isEmpty ? 0 : globalModel.rawMessageCount(convKey),
        },
      );
    }`;
 r(old,'    }');
});
edit('lib/src/navigation/app_chat_route.dart',(r,get,set)=>{
 r("import 'dart:async';","import 'dart:async';\nimport 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';");
 r('class AppChatRouteRegistry {',`class _PendingChatOpen {
  _PendingChatOpen(BuildContext context) : callers = [context];
  final List<BuildContext> callers;
  final Completer<Object?> result = Completer<Object?>();
}

String _accountRouteKey(String key) {
  final session = SessionIdentityService.instance.capture();
  return session.ownerUserId + '|' + session.generation.toString() + '|' + key;
}

class AppChatRouteRegistry {`);
 r('  void register({',`  final Map<NavigatorState, Map<String, _PendingChatOpen>> _pending = {};
  @visibleForTesting
  Future<void> Function()? prepareForTest;
  @visibleForTesting
  Route<dynamic> Function()? routeForTest;

  void register({`);
 // Only register and lookup: unregister scans route identity, even after account change.
 const pos=get().indexOf('  void unregister('),end=get().indexOf('  Route<dynamic>? activeRoute(',pos);
 set(get().slice(0,pos)+`  void unregister({required NavigatorState navigator, required String sessionKey,
      required Route<dynamic> route}) {
    final routes = _routes[navigator];
    if (routes == null) return;
    for (final list in routes.values) { list.removeWhere((candidate) => identical(candidate, route)); }
    routes.removeWhere((_, list) => list.isEmpty);
    if (routes.isEmpty) _routes.remove(navigator);
  }

`+get().slice(end));
 set(get().replaceAll('final key = sessionKey.trim();','final key = _accountRouteKey(sessionKey.trim());'));
 r('  void reset() => _routes.clear();','  void reset() { _routes.clear(); _pending.clear(); prepareForTest = null; routeForTest = null; }');
 r('  final sessionKey = appChatSessionKey(conversation);\n  return AppMaterialPageRoute<T>(',"  final sessionKey = appChatSessionKey(conversation) +\n      (resolvedAnchor == null ? '' : '|anchor:' + resolvedAnchor.stableKey);\n  return AppMaterialPageRoute<T>(");
 const boundary='  // 只等本地 fast classify。H0 由 prepareOpenViewport 并行启动，不阻塞 push。';
 r(boundary,`  final registry = AppChatRouteRegistry.instance;
  final identity = SessionIdentityService.instance.capture();
  final anchor = searchJumpAnchor ?? (initFindingMsg == null ? null
      : MessageAnchor.fromConversationMessage(conversation, initFindingMsg));
  final reservationKey = _accountRouteKey(sessionKey + (anchor == null ? '' : '|anchor:' + anchor.stableKey));
  final reservations = registry._pending[navigator] ??= {};
  final pending = reservations[reservationKey];
  if (pending != null) {
    pending.callers.add(context);
    ChatOpenPerfLog.mark('route_open_shared', trace: openTrace);
    final value = await pending.result.future;
    return value is T ? value : null;
  }
  final reservation = _PendingChatOpen(context);
  reservations[reservationKey] = reservation;
  Future<Object?> openReserved() async {
${boundary}`);
 r("() => ChatOpenViewportCoordinator.instance.prepareOpenViewport(","() => registry.prepareForTest?.call() ?? ChatOpenViewportCoordinator.instance.prepareOpenViewport(");
 r('        source: openSource);\n  } catch (_) {','        source: openSource).timeout(ChatOpenViewportCoordinator.localBudget);\n  } catch (_) {');
 r("  if (!context.mounted) {\n    ChatOpenPerfLog.mark('route_cancelled', trace: openTrace);", "  if (!navigator.mounted || !reservation.callers.any((caller) => caller.mounted) ||\n      SessionIdentityService.instance.capture() != identity) {\n    ChatOpenPerfLog.mark('route_cancelled', trace: openTrace);");
 r('  return navigator.push<T>(\n    appChatRoute<T>(', '  return navigator.push<dynamic>(\n    registry.routeForTest?.call() ?? appChatRoute<dynamic>(');
 r('    ),\n  );\n}\n\nFuture<T?> openChatWithAnchor',`    ),
  );
  }
  // Reserve synchronously before the first await and retain until real pop.
  unawaited(openReserved().then(reservation.result.complete,
      onError: reservation.result.completeError).whenComplete(() {
    if (identical(reservations[reservationKey], reservation)) reservations.remove(reservationKey);
    if (reservations.isEmpty && identical(registry._pending[navigator], reservations)) registry._pending.remove(navigator);
  }));
  final value = await reservation.result.future;
  return value is T ? value : null;
}

Future<T?> openChatWithAnchor`);
});
