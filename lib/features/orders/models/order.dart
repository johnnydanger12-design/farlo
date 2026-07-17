import 'order_item.dart';

class Order {
  const Order({
    required this.id,
    required this.truckId,
    this.truckName,
    required this.consumerId,
    this.consumerName,
    required this.status,
    this.pickupNote,
    required this.totalPrice,
    this.taxPrice = 0,
    this.paymentIntentId,
    required this.paymentStatus,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String truckId;
  final String? truckName;
  final String consumerId;
  final String? consumerName;
  final String status; // pending | accepted | ready | completed | declined | cancelled
  final String? pickupNote;
  final double totalPrice;
  final double taxPrice;
  final String? paymentIntentId;
  final String paymentStatus; // unpaid | paid | refunded
  final List<OrderItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == 'pending';
  bool get isActive => status == 'accepted' || status == 'ready';
  bool get isTerminal =>
      status == 'completed' || status == 'declined' || status == 'cancelled';

  factory Order.fromMap(Map<String, dynamic> map) {
    final itemMaps = map['order_items'] as List<dynamic>? ?? [];
    final items = itemMaps
        .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
        .toList();

    final truckMap = map['food_trucks'] as Map<String, dynamic>?;
    final profileMap = map['profiles'] as Map<String, dynamic>?;

    return Order(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      truckName: truckMap?['name'] as String?,
      consumerId: map['consumer_id'] as String,
      consumerName: profileMap?['display_name'] as String?,
      status: map['status'] as String,
      pickupNote: map['pickup_note'] as String?,
      totalPrice: (map['total_price'] as num).toDouble(),
      taxPrice: (map['tax_price'] as num?)?.toDouble() ?? 0,
      paymentIntentId: map['stripe_payment_intent_id'] as String?,
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      items: items,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Order copyWith({String? status, String? paymentStatus}) {
    return Order(
      id: id,
      truckId: truckId,
      truckName: truckName,
      consumerId: consumerId,
      consumerName: consumerName,
      status: status ?? this.status,
      pickupNote: pickupNote,
      totalPrice: totalPrice,
      taxPrice: taxPrice,
      paymentIntentId: paymentIntentId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
