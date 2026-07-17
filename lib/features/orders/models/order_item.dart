// A selected paid add-on. `id` (the real menu_item_modifiers row) is used
// pre-order so the server can validate/price it against the real row —
// name + priceDelta are what's actually snapshotted at order time so later
// menu edits never rewrite history.
class SelectedModifier {
  const SelectedModifier({required this.id, required this.name, required this.priceDelta});
  final String id;
  final String name;
  final double priceDelta;

  factory SelectedModifier.fromMap(Map<String, dynamic> map) => SelectedModifier(
    id: map['id'] as String? ?? '',
    name: map['name'] as String,
    priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {'name': name, 'price_delta': priceDelta};
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    this.specialRequest,
    this.removedModifiers = const [],
    this.addedModifiers = const [],
  });

  final String id;
  final String orderId;
  final String? menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String? specialRequest;
  final List<String> removedModifiers;
  final List<SelectedModifier> addedModifiers;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      menuItemId: map['menu_item_id'] as String?,
      name: map['menu_item_name'] as String,
      price: (map['menu_item_price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      specialRequest: map['special_request'] as String?,
      removedModifiers: (map['removed_modifiers'] as List?)?.cast<String>() ?? const [],
      addedModifiers: (map['added_modifiers'] as List?)
              ?.map((e) => SelectedModifier.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  double get lineTotal =>
      (price + addedModifiers.fold(0.0, (sum, m) => sum + m.priceDelta)) * quantity;

  OrderItem copyWith({int? quantity, String? specialRequest}) {
    return OrderItem(
      id: id,
      orderId: orderId,
      menuItemId: menuItemId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
      specialRequest: specialRequest ?? this.specialRequest,
      removedModifiers: removedModifiers,
      addedModifiers: addedModifiers,
    );
  }
}

// In-memory cart item (no id/orderId yet — assigned by DB on placeOrder).
class CartItem {
  const CartItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    this.specialRequest,
    this.removedModifiers = const [],
    this.addedModifiers = const [],
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String? specialRequest;
  final List<String> removedModifiers;
  final List<SelectedModifier> addedModifiers;

  double get lineTotal =>
      (price + addedModifiers.fold(0.0, (sum, m) => sum + m.priceDelta)) * quantity;

  // Distinguishes different customizations of the same menu item as separate
  // cart lines (e.g. "no mustard" vs. "everything") — without this, the cart
  // (keyed by menuItemId alone) would collapse them into one line and lose
  // one customization entirely. Falls back to plain menuItemId when there's
  // no customization at all, so uncustomized items behave exactly as before.
  String get cartKey {
    if (removedModifiers.isEmpty && addedModifiers.isEmpty) return menuItemId;
    final removed = [...removedModifiers]..sort();
    final added = [...addedModifiers.map((m) => m.name)]..sort();
    return '$menuItemId::${removed.join(',')}::${added.join(',')}';
  }

  CartItem copyWith({int? quantity, String? specialRequest}) {
    return CartItem(
      menuItemId: menuItemId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
      specialRequest: specialRequest ?? this.specialRequest,
      removedModifiers: removedModifiers,
      addedModifiers: addedModifiers,
    );
  }
}
