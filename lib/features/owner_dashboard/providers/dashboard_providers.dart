import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../orders/models/order.dart';

// Dashboard-only lightweight providers, shared across the dashboard screen's
// extracted widgets (code-quality.md ARCH-4 — decomposed out of the
// 1500+ line dashboard_screen.dart into per-widget files).

final stripeConnectedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;
  final row = await Supabase.instance.client
      .from('profiles')
      .select('stripe_account_id')
      .eq('id', userId)
      .single();
  return (row['stripe_account_id'] as String?) != null;
});

final activeOrdersProvider =
    FutureProvider.autoDispose.family<List<Order>, String>((ref, truckId) async {
  final data = await Supabase.instance.client
      .from('orders')
      .select(
          'id, truck_id, consumer_id, status, total_price, payment_status,'
          ' pickup_note, stripe_payment_intent_id, created_at, updated_at,'
          ' order_items(*)')
      .eq('truck_id', truckId)
      .inFilter('status', const ['pending', 'accepted', 'ready'])
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => Order.fromMap(e as Map<String, dynamic>))
      .toList();
});

final profileDisplayNameProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, userId) async {
  // profiles is self-read-only via RLS — use the narrow RPC for another
  // user's display name (e.g. "opened by <employee name>").
  final name = await Supabase.instance.client
      .rpc('profile_display_name', params: {'p_user_id': userId});
  return name as String?;
});
