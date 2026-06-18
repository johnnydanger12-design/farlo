class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
    this.specialRequest,
  });

  final String id;
  final String orderId;
  final String? menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String? specialRequest;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      menuItemId: map['menu_item_id'] as String?,
      name: map['menu_item_name'] as String,
      price: (map['menu_item_price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      specialRequest: map['special_request'] as String?,
    );
  }

  double get lineTotal => price * quantity;

  OrderItem copyWith({int? quantity, String? specialRequest}) {
    return OrderItem(
      id: id,
      orderId: orderId,
      menuItemId: menuItemId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
      specialRequest: specialRequest ?? this.specialRequest,
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
  });

  final String menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String? specialRequest;

  double get lineTotal => price * quantity;

  CartItem copyWith({int? quantity, String? specialRequest}) {
    return CartItem(
      menuItemId: menuItemId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
      specialRequest: specialRequest ?? this.specialRequest,
    );
  }
}
