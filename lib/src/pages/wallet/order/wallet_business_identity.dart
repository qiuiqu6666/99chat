/// The business family carried by a wallet card. A card's mutable status may
/// come from REST, but an IM message's family must never change in projection.
enum WalletBusinessFamily { redPacket, transfer, groupTransfer }

extension WalletBusinessFamilyWire on WalletBusinessFamily {
  String get wireType => switch (this) {
        WalletBusinessFamily.redPacket => 'wallet_red_packet',
        WalletBusinessFamily.transfer => 'wallet_transfer',
        WalletBusinessFamily.groupTransfer => 'wallet_group_transfer',
      };

  String get cardPrefix =>
      this == WalletBusinessFamily.transfer ? 'transfer' : 'rp';
}

class WalletBusinessIdentity {
  const WalletBusinessIdentity({
    required this.family,
    required this.orderId,
    required this.clientOrderId,
    required this.cardId,
  });

  final WalletBusinessFamily family;
  final String orderId;
  final String clientOrderId;
  final String cardId;

  static String _value(Map data, String key) =>
      data[key]?.toString().trim() ?? '';

  static WalletBusinessFamily? _family(String value) => switch (value) {
        'wallet_red_packet' => WalletBusinessFamily.redPacket,
        'wallet_transfer' => WalletBusinessFamily.transfer,
        'wallet_group_transfer' => WalletBusinessFamily.groupTransfer,
        _ => null,
      };

  /// Reject ambiguous customType/type pairs instead of choosing a precedence.
  /// An absent businessID is supported for older wallet messages.
  static WalletBusinessIdentity? fromMap(Map data) {
    final businessID = _value(data, 'businessID');
    if (businessID.isNotEmpty && businessID != 'wallet_order') return null;
    final customType = _value(data, 'customType');
    final legacyType = _value(data, 'type');
    final custom = customType.isEmpty ? null : _family(customType);
    final legacy = legacyType.isEmpty ? null : _family(legacyType);
    if ((customType.isNotEmpty && custom == null) ||
        (legacyType.isNotEmpty && legacy == null) ||
        (custom != null && legacy != null && custom != legacy)) {
      return null;
    }
    final family = custom ?? legacy;
    if (family == null) return null;
    final order = _value(data, 'orderId');
    final fallback = _value(data, 'id');
    if (order.isNotEmpty && fallback.isNotEmpty && order != fallback) {
      return null;
    }
    final orderId = order.isNotEmpty ? order : fallback;
    final cardId = _value(data, 'cardId');
    if (cardId.isNotEmpty &&
        (orderId.isEmpty || cardId != '${family.cardPrefix}:$orderId')) {
      return null;
    }
    return WalletBusinessIdentity(
      family: family,
      orderId: orderId,
      clientOrderId: _value(data, 'clientOrderId'),
      cardId: cardId,
    );
  }

  String get expectedCardId => '${family.cardPrefix}:$orderId';

  /// Numeric order ids may overlap between transfer and packet namespaces.
  /// Across families, only a shared card id or client order id proves collision.
  bool sharesConfirmedIdentityWith(WalletBusinessIdentity other) =>
      (cardId.isNotEmpty && cardId == other.cardId) ||
      (clientOrderId.isNotEmpty && clientOrderId == other.clientOrderId) ||
      (family == other.family &&
          orderId.isNotEmpty &&
          orderId == other.orderId);
}
