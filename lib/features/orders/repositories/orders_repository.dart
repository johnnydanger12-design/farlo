import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import 'orders_data_source.dart';

// Caps how many past orders a single fetch pulls back — an owner/consumer
// with a long history was pulling every row ever created with no limit,
// feeding an eager (non-lazy) ListView that built every row regardless of
// scroll position (performance.md §5, code-quality.md §2.15).
const _orderPageSize = 200;

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
  OrdersRepository(this._supabase, {OrdersDataSource? dataSource})
      : _dataSource = dataSource ?? SupabaseOrdersDataSource(_supabase);
  final SupabaseClient _supabase;
  final OrdersDataSource _dataSource;

  static const _orderSelect =
      '*, order_items(*), food_trucks(name), profiles(display_name)';

  // -------------------------------------------------------------------------
  // Consumer — payment + order placement
  // -------------------------------------------------------------------------

  Future<({String clientSecret, String paymentIntentId, double taxPrice})> createPaymentIntent({
    required String truckId,
    required List<CartItem> items,
    required String idempotencyKey,
  }) async {
    // The server recomputes the charge amount (including tax, from the truck's
    // own tax_rate_percent) from real menu_items prices — it no longer trusts a
    // client-supplied total, so only item/quantity is sent. idempotencyKey is
    // generated once per checkout attempt by the caller and reused across
    // retries of that same attempt, so a network-blip retry reuses the same
    // Stripe PaymentIntent instead of charging twice (bugs.md Executive
    // Summary #3).
    final res = await _supabase.functions.invoke(
      'create-payment-intent',
      body: {
        'truck_id': truckId,
        'items': items
            .map((i) => {
                  'menu_item_id': i.menuItemId,
                  'quantity': i.quantity,
                  if (i.addedModifiers.isNotEmpty)
                    'added_modifier_ids': i.addedModifiers.map((m) => m.id).toList(),
                  if (i.selectedGroupOptions.isNotEmpty)
                    'selected_group_option_ids': i.selectedGroupOptions.values.map((m) => m.id).toList(),
                })
            .toList(),
        'idempotency_key': idempotencyKey,
      },
    ).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return (
      clientSecret: data['client_secret'] as String,
      paymentIntentId: data['payment_intent_id'] as String,
      taxPrice: (data['tax_cents'] as num) / 100,
    );
  }

  Future<Order> placeOrder({
    required String truckId,
    required String consumerId,
    required List<CartItem> items,
    String? pickupNote,
    required String paymentIntentId,
    required double taxPrice,
  }) async {
    // Idempotent by paymentIntentId: if a prior attempt already inserted the
    // order for this same charge (e.g. the charge succeeded but a later step
    // in that attempt failed and the caller retried), return the existing
    // order instead of inserting a duplicate — this is what actually makes a
    // retry after a stranded charge safe end-to-end, on top of the Stripe
    // idempotency key covering the charge itself.
    final existing = await _dataSource.findOrderByPaymentIntent(paymentIntentId);
    if (existing != null) return existing;

    final order = await _dataSource.insertOrder(
      truckId: truckId,
      consumerId: consumerId,
      items: items,
      paymentIntentId: paymentIntentId,
      pickupNote: pickupNote,
      taxPrice: taxPrice,
    );

    _invokeNotification('order_placed', order.id);
    return order;
  }

  Future<List<Order>> fetchOrdersForConsumer(String userId) async {
    final rows = await _supabase
        .from('orders')
        .select('*, order_items(*), food_trucks(name)')
        .eq('consumer_id', userId)
        .order('created_at', ascending: false)
        .limit(_orderPageSize)
        .withNetworkTimeout;
    return (rows as List)
        .map((r) => Order.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // "Order Again" shelf on a truck's profile — this consumer's own recent
  // orders at THIS truck specifically, not their whole history. Excludes
  // cancelled/declined since those were never actually fulfilled and aren't
  // meaningful "order this again" candidates.
  Future<List<Order>> fetchRecentOrdersForConsumerAtTruck(
    String userId,
    String truckId, {
    int limit = 5,
  }) async {
    final rows = await _supabase
        .from('orders')
        .select('*, order_items(*), food_trucks(name)')
        .eq('consumer_id', userId)
        .eq('truck_id', truckId)
        .neq('status', 'cancelled')
        .neq('status', 'declined')
        .order('created_at', ascending: false)
        .limit(limit)
        .withNetworkTimeout;
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
        .select('id')
        .withNetworkTimeout;
    if ((updated as List).isEmpty) {
      throw OrderAlreadyActedOnException(
        'This order has already been accepted by the business and can no longer be cancelled.',
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
        .order('created_at', ascending: false)
        .limit(_orderPageSize)
        .withNetworkTimeout;
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
    final updated = await query.select('id').withNetworkTimeout;
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
    final res = await _supabase.functions.invoke('stripe-connect-onboard').withNetworkTimeout;
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
