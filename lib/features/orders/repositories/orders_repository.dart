import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/order_item.dart';

/// Thrown when a status-changing action (cancel/accept/decline/etc.) didn't
/// apply because the order had already moved to a different status —
/// surfaces the real "someone else already acted on this" case to the UI
/// instead of silently succeeding or throwing a generic error.
class OrderAlreadyActedOnException implements Exception {
  OrderAlreadyActedOnException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
    required String idempotencyKey,
  }) async {
    // The server recomputes the charge amount from real menu_items prices — it
    // no longer trusts a client-supplied total, so only item/quantity is sent.
    // idempotencyKey is generated once per checkout attempt by the caller and
    // reused across retries of that same attempt, so a network-blip retry
    // reuses the same Stripe PaymentIntent instead of charging twice
    // (bugs.md Executive Summary #3).
    final res = await _supabase.functions.invoke(
      'create-payment-intent',
      body: {
        'truck_id': truckId,
        'items': items
            .map((i) => {'menu_item_id': i.menuItemId, 'quantity': i.quantity})
            .toList(),
        'idempotency_key': idempotencyKey,
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
    required String consumerId,
    required List<CartItem> items,
    String? pickupNote,
    required String paymentIntentId,
  }) async {
    // Idempotent by paymentIntentId: if a prior attempt already inserted the
    // order for this same charge (e.g. the charge succeeded but a later step
    // in that attempt failed and the caller retried), return the existing
    // order instead of inserting a duplicate — this is what actually makes a
    // retry after a stranded charge safe end-to-end, on top of the Stripe
    // idempotency key covering the charge itself.
    final existing = await _supabase
        .from('orders')
        .select(_orderSelect)
        .eq('stripe_payment_intent_id', paymentIntentId)
        .maybeSingle();
    if (existing != null) return Order.fromMap(existing);

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

  // Only cancels an order still 'pending' — without this precondition, a
  // consumer's cancel could silently overwrite an owner's concurrent accept
  // (bugs.md Executive Summary #2 / #2.3.1), refunding an order the truck is
  // already preparing. Throws OrderAlreadyActedOnException if the order moved
  // out of 'pending' before this reached the server, so the UI can tell the
  // user rather than silently proceeding to refund.
  Future<void> cancelOrder(String orderId) async {
    final updated = await _supabase
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId)
        .eq('status', 'pending')
        .select('id');
    if ((updated as List).isEmpty) {
      throw OrderAlreadyActedOnException(
        'This order has already been accepted by the truck and can no longer be cancelled.',
      );
    }
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

  // Requires the order currently be in the one valid prior status for the
  // requested transition — without this, two concurrent owner devices (or a
  // consumer's cancel racing an owner's accept, bugs.md #2.3.1) can silently
  // clobber each other with no error. Throws OrderAlreadyActedOnException if
  // the order isn't in the expected prior status.
  static const _validPriorStatus = {
    'accepted': 'pending',
    'declined': 'pending',
    'ready': 'accepted',
    'completed': 'ready',
  };

  Future<void> updateOrderStatus(String orderId, String status) async {
    final priorStatus = _validPriorStatus[status];
    var query = _supabase.from('orders').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
    if (priorStatus != null) {
      query = query.eq('status', priorStatus);
    }
    final updated = await query.select('id');
    if ((updated as List).isEmpty) {
      throw OrderAlreadyActedOnException(
        'This order was already updated — refresh to see its current status.',
      );
    }

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
