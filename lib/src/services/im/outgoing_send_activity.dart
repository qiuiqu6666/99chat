import 'writer_lease.dart';

/// Process-local ownership, not delivery evidence or permission to resend.
/// A process restart intentionally starts empty so interrupted durable rows
/// still enter reconciliation. Session/domain changes cannot inherit a pin.
class OutgoingSendActivity {
  static final instance = OutgoingSendActivity();

  final Map<(String, int, int, String), Set<Object>> _active = {};

  (String, int, int, String) _key(
          ImMessageCoreLeaseContext context, String operationId) =>
      (
        context.ownerUserId,
        context.accountGeneration,
        context.domainGeneration,
        operationId
      );

  bool isActive(ImMessageCoreLeaseContext context, String operationId) =>
      _active[_key(context, operationId)]?.isNotEmpty == true;

  Future<T> track<T>(ImMessageCoreLeaseContext context, String operationId,
      Future<T> Function() work) async {
    final key = _key(context, operationId);
    final token = Object();
    (_active[key] ??= {}).add(token);
    try {
      return await work();
    } finally {
      final tokens = _active[key];
      tokens?.remove(token);
      if (tokens?.isEmpty == true) _active.remove(key);
    }
  }
}
