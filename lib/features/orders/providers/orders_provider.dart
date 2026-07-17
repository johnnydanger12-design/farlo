import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../repositories/orders_repository.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(Supabase.instance.client);
});

// ─── Owner: live order queue for a truck ─────────────────────────────────────

class OwnerOrdersNotifier extends AsyncNotifier<List<Order>> {
  @override
  Future<List<Order>> build() async => [];

  Future<void> load(String truckId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(ordersRepositoryProvider).fetchOrdersForTruck(truckId),
    );
  }

  Future<void> updateStatus(String orderId, String status) async {
    await ref.read(ordersRepositoryProvider).updateOrderStatus(orderId, status);
    final current = state.asData?.value ?? [];
    state = AsyncData(
      current.map((o) => o.id == orderId ? o.copyWith(status: status) : o).toList(),
    );
  }
}

final ownerOrdersProvider =
    AsyncNotifierProvider<OwnerOrdersNotifier, List<Order>>(
  OwnerOrdersNotifier.new,
);

// ─── Consumer: my order history ──────────────────────────────────────────────

class MyOrdersNotifier extends AsyncNotifier<List<Order>> {
  @override
  Future<List<Order>> build() async => [];

  Future<void> load(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(ordersRepositoryProvider).fetchOrdersForConsumer(userId),
    );
  }

  Future<void> cancel(String orderId) async {
    await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
    final current = state.asData?.value ?? [];
    state = AsyncData(
      current.map((o) => o.id == orderId ? o.copyWith(status: 'cancelled') : o).toList(),
    );
  }

  void prepend(Order order) {
    final current = state.asData?.value ?? [];
    state = AsyncData([order, ...current]);
  }
}

final myOrdersProvider =
    AsyncNotifierProvider<MyOrdersNotifier, List<Order>>(
  MyOrdersNotifier.new,
);

// ─── Cart: in-memory, keyed by CartItem.cartKey (menuItemId, or
// menuItemId+customization if the item has any removed/added modifiers — see
// CartItem.cartKey) so two different customizations of the same dish are
// separate lines instead of colliding into one.

class CartNotifier extends Notifier<Map<String, CartItem>> {
  @override
  Map<String, CartItem> build() => {};

  void add(CartItem item) {
    final key = item.cartKey;
    final current = state[key];
    if (current != null) {
      state = {...state, key: current.copyWith(quantity: current.quantity + 1)};
    } else {
      state = {...state, key: item};
    }
  }

  void remove(String cartKey) {
    final current = state[cartKey];
    if (current == null) return;
    if (current.quantity <= 1) {
      final next = Map<String, CartItem>.from(state)..remove(cartKey);
      state = next;
    } else {
      state = {...state, cartKey: current.copyWith(quantity: current.quantity - 1)};
    }
  }

  void setSpecialRequest(String cartKey, String? text) {
    final current = state[cartKey];
    if (current == null) return;
    state = {...state, cartKey: current.copyWith(specialRequest: text)};
  }

  void clear() => state = {};

  List<CartItem> get items => state.values.toList();

  double get total => state.values.fold(0.0, (sum, i) => sum + i.lineTotal);

  int get totalQuantity => state.values.fold(0, (sum, i) => sum + i.quantity);

  // Aggregate quantity across every customization of one menu item — used for
  // the simple "+N" badge on a menu card, which doesn't distinguish which
  // customization is in the cart, just how many of that dish total.
  int quantityForMenuItem(String menuItemId) =>
      state.values.where((i) => i.menuItemId == menuItemId).fold(0, (sum, i) => sum + i.quantity);
}

final cartProvider = NotifierProvider<CartNotifier, Map<String, CartItem>>(
  CartNotifier.new,
);
