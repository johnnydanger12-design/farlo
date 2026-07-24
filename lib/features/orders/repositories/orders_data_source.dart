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
    '*, order_items(*), food_trucks(name, logo_url), profiles(display_name)';

abstract class OrdersDataSource {
  Future<Order?> findOrderByPaymentIntent(String paymentIntentId);

  Future<Order> insertOrder({
    required String truckId,
    required String consumerId,
    required List<CartItem> items,
    required String paymentIntentId,
    String? pickupNote,
    required double taxPrice,
    String? stripeAccountId,
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
    required double taxPrice,
    String? stripeAccountId,
  }) async {
    // total_price includes tax — matches the actual amount charged via Stripe
    // (create-payment-intent charges subtotal + tax as one PaymentIntent), so
    // this stays consistent with what the customer's card was really charged.
    final totalPrice = items.fold(0.0, (sum, i) => sum + i.lineTotal) + taxPrice;

    final orderRow = await _supabase
        .from('orders')
        .insert({
          'truck_id': truckId,
          'consumer_id': consumerId,
          'total_price': totalPrice,
          'tax_price': taxPrice,
          'stripe_payment_intent_id': paymentIntentId,
          if (pickupNote != null && pickupNote.isNotEmpty) 'pickup_note': pickupNote,
          // Only set for direct charges (see create-payment-intent) — lets
          // create-refund know which Stripe account a refund needs to be
          // scoped to. Null means the old destination-charge path, which
          // refunds against the platform account exactly as it always has.
          'stripe_connected_account_id': ?stripeAccountId,
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
                if (i.removedModifiers.isNotEmpty) 'removed_modifiers': i.removedModifiers,
                if (i.addedModifiers.isNotEmpty)
                  'added_modifiers': i.addedModifiers.map((m) => m.toMap()).toList(),
                if (i.selectedGroupOptions.isNotEmpty)
                  'selected_options': i.selectedGroupOptions.entries
                      .map((e) => {'group_name': e.key, ...e.value.toMap()})
                      .toList(),
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
