import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/order.dart';
import '../models/order_item.dart';

// ARCH-1 (code-quality.md §2.14, REMEDIATION_STATE.md's scoped-down definition):
// isolates OrdersRepository.placeOrder()'s raw Supabase I/O behind an
// injectable interface, so its idempotency logic (bugs.md Executive Summary
// #3 — stranded Stripe charges) can be unit-tested against a mock without
// replicating Supabase's fluent query-builder chain in a test double.

const _orderSelect =
    '*, order_items(*), food_trucks(name), profiles(display_name)';

abstract class OrdersDataSource {
  Future<Order?> findOrderByPaymentIntent(String paymentIntentId);

  Future<Order> insertOrder({
    required String truckId,
    required String consumerId,
    required List<CartItem> items,
    required String paymentIntentId,
    String? pickupNote,
  });
}

class SupabaseOrdersDataSource implements OrdersDataSource {
  SupabaseOrdersDataSource(this._supabase);
  final SupabaseClient _supabase;

  @override
  Future<Order?> findOrderByPaymentIntent(String paymentIntentId) async {
    final existing = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('stripe_payment_intent_id', paymentIntentId)
        .maybeSingle()
        .withNetworkTimeout;
    if (existing == null) return null;
    return Order.fromMap(existing);
  }

  @override
  Future<Order> insertOrder({
    required String truckId,
    required String consumerId,
    required List<CartItem> items,
    required String paymentIntentId,
    String? pickupNote,
  }) async {
    final totalPrice = items.fold(0.0, (sum, i) => sum + i.lineTotal);

    final orderRow = await _supabase
        .from('orders')
        .insert({
          'truck_id': truckId,
          'consumer_id': consumerId,
          'total_price': totalPrice,
          'stripe_payment_intent_id': paymentIntentId,
          if (pickupNote != null && pickupNote.isNotEmpty) 'pickup_note': pickupNote,
        })
        .select('id')
        .single()
        .withNetworkTimeout;

    final orderId = orderRow['id'] as String;

    await _supabase.from('order_items').insert(
      items
          .map((i) => {
                'order_id': orderId,
                'menu_item_id': i.menuItemId,
                'menu_item_name': i.name,
                'menu_item_price': i.price,
                'quantity': i.quantity,
                if (i.specialRequest != null && i.specialRequest!.isNotEmpty)
                  'special_request': i.specialRequest,
              })
          .toList(),
    ).withNetworkTimeout;

    final row = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single()
        .withNetworkTimeout;
    return Order.fromMap(row);
  }
}
