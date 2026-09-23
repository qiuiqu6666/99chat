/// Values crossing the runtime boundary never retain SDK objects, collections,
/// BuildContexts, clocks or callbacks. Host adapters freeze their DTOs here.
class RuntimeDocument {
  RuntimeDocument(Map<String, Object?> values) : values = _freezeMap(values);

  final Map<String, Object?> values;

  Object? operator [](String key) => values[key];

  static Map<String, Object?> _freezeMap(Map values) =>
      Map<String, Object?>.unmodifiable(values.map((key, value) {
        if (key is! String) throw ArgumentError('Runtime keys must be strings');
        return MapEntry(key, _freeze(value));
      }));

  static Object? _freeze(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double && value.isFinite) return value;
    if (value is Map) return _freezeMap(value);
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    throw ArgumentError('Runtime payload contains a non-value object');
  }
}

class RuntimeAccountScope {
  RuntimeAccountScope({
    required String ownerUserID,
    required this.accountEpoch,
    required this.sdkDomainEpoch,
  }) : ownerUserID = ownerUserID.trim() {
    if (this.ownerUserID.isEmpty || accountEpoch < 0 || sdkDomainEpoch < 0) {
      throw ArgumentError('Invalid runtime account scope');
    }
  }

  final String ownerUserID;
  final int accountEpoch;
  final int sdkDomainEpoch;

  @override
  bool operator ==(Object other) =>
      other is RuntimeAccountScope &&
      ownerUserID == other.ownerUserID &&
      accountEpoch == other.accountEpoch &&
      sdkDomainEpoch == other.sdkDomainEpoch;

  @override
  int get hashCode => Object.hash(ownerUserID, accountEpoch, sdkDomainEpoch);
}

class RuntimeEnvelope {
  RuntimeEnvelope({
    required this.scope,
    required String conversationKey,
    required String eventID,
    required String operationID,
    required String correlationID,
    required this.source,
    required this.kind,
    required this.clearEpoch,
    required this.payload,
    this.causeID,
    this.expectedRevision,
    this.visitID,
    this.viewOperation,
  })  : conversationKey = conversationKey.trim(),
        eventID = eventID.trim(),
        operationID = operationID.trim(),
        correlationID = correlationID.trim() {
    if (this.conversationKey.isEmpty ||
        this.eventID.isEmpty ||
        this.operationID.isEmpty ||
        this.correlationID.isEmpty ||
        source.isEmpty ||
        kind.isEmpty ||
        clearEpoch < 0 ||
        (expectedRevision != null && expectedRevision! < 0) ||
        ((visitID == null) != (viewOperation == null))) {
      throw ArgumentError('Invalid runtime envelope');
    }
  }

  final RuntimeAccountScope scope;
  // Canonicalization belongs to the typed host conversation-ID adapter.
  final String conversationKey;
  final String eventID;
  final String operationID;
  final String correlationID;
  final String? causeID;
  final String source;
  final String kind;
  final int clearEpoch;
  final int? expectedRevision;
  final int? visitID;
  final int? viewOperation;
  final RuntimeDocument payload;
}

class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.scope,
    required this.conversationKey,
    required this.clearEpoch,
    required this.revision,
    required this.document,
  });

  final RuntimeAccountScope scope;
  final String conversationKey;
  final int clearEpoch;
  final int revision;
  final RuntimeDocument document;
}

class RuntimeEffectIntent {
  RuntimeEffectIntent({
    required this.operationID,
    required this.kind,
    required this.payload,
  }) {
    if (operationID.isEmpty || kind.isEmpty) {
      throw ArgumentError('Effect intent needs operation identity and kind');
    }
  }
  final String operationID;
  final String kind;
  final RuntimeDocument payload;
}

class RuntimeTransition {
  RuntimeTransition(
      {required this.document,
      Iterable<RuntimeEffectIntent> effects = const []})
      : effects = List<RuntimeEffectIntent>.unmodifiable(effects);
  final RuntimeDocument document;
  final List<RuntimeEffectIntent> effects;
}

typedef RuntimeReducer = RuntimeTransition Function(
    RuntimeSnapshot before, RuntimeEnvelope event);

enum RuntimeDisposition {
  committed,
  duplicate,
  staleAccount,
  staleClear,
  staleView,
  staleRevision,
  rejected
}

class RuntimeReceipt {
  const RuntimeReceipt(
      {required this.eventID,
      required this.ingressSequence,
      required this.disposition,
      required this.snapshot,
      this.effects = const [],
      this.error,
      this.stackTrace});
  final String eventID;
  final int ingressSequence;
  final RuntimeDisposition disposition;
  final RuntimeSnapshot snapshot;
  final List<RuntimeEffectIntent> effects;
  final Object? error;
  final StackTrace? stackTrace;
}
