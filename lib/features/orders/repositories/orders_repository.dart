import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/order_item.dart';

class OrdersRepository {
  OrdersRepository(this._supabase);
  final SupabaseClient _supabase;

  static const _orderSelect =
      '*, order_items(*), food_trucks(name), profiles(display_name)';

  // -------------------------------------------------------------------------
  // Consumer — payment + order placement
  // -------------------------------------------------------------------------

  Future<({String clientSecret, String paymentIntentId})> createPaymentIntent({
    required String truckId,
    required List<CartItem> items,
  }) async {
    // The server recomputes the charge amount from real menu_items prices — it
    // no longer trusts a client-supplied total, so only item/quantity is sent.
    final res = await _supabase.functions.invoke(
      'create-payment-intent',
      body: {
        'truck_id': truckId,
        'items': items
            .map((i) => {'menu_item_id': i.menuItemId, 'quantity': i.quantity})
            .toList(),
      },
    );
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return (
      clientSecret: data['client_secret'] as String,
      paymentIntentId: data['payment_intent_id'] as String,
    );
  }

  Future<Order> placeOrder({
    required String truckId,
    required List<CartItem> items,
    String? pickupNote,
    required String paymentIntentId,
  }) async {
    final consumerId = _supabase.auth.currentUser!.id;
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
        .single();

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
    );

    _invokeNotification('order_placed', orderId);

    final row = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .single();
    return Order.fromMap(row);
  }

  Future<List<Order>> fetchOrdersForConsumer(String userId) async {
    final rows = await _supabase
        .from('orders')
        .select('*, order_items(*), food_trucks(name)')
        .eq('consumer_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Order.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelOrder(String orderId) async {
    await _supabase
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId);
    _invokeNotification('order_cancelled', orderId);
    _invokeRefund(orderId);
  }

  // -------------------------------------------------------------------------
  // Owner
  // -------------------------------------------------------------------------

  Future<List<Order>> fetchOrdersForTruck(String truckId) async {
    final rows = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('truck_id', truckId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Order.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _supabase
        .from('orders')
        .update({'status': status, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', orderId);

    final notifAction = switch (status) {
      'accepted' => 'order_accepted',
      'ready' => 'order_ready',
      'declined' => 'order_declined',
      _ => null,
    };
    if (notifAction != null) _invokeNotification(notifAction, orderId);
    if (status == 'declined') _invokeRefund(orderId);
  }

  // -------------------------------------------------------------------------
  // Owner — Stripe Connect onboarding
  // -------------------------------------------------------------------------

  Future<String> connectStripeAccount() async {
    final res = await _supabase.functions.invoke('stripe-connect-onboard');
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return data['url'] as String;
  }

  // -------------------------------------------------------------------------
  // Fire-and-forget helpers
  // -------------------------------------------------------------------------

  void _invokeNotification(String action, String orderId) {
    () async {
      try {
        await _supabase.functions.invoke(
          'send-order-notification',
          body: {'action': action, 'order_id': orderId},
        );
      } catch (e) {
        debugPrint('Order notification invoke failed: $e');
      }
    }();
  }

  void _invokeRefund(String orderId) {
    () async {
      try {
        await _supabase.functions.invoke(
          'create-refund',
          body: {'order_id': orderId},
        );
      } catch (e) {
        debugPrint('Refund invoke failed: $e');
      }
    }();
  }
}
