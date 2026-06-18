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

// ─── Cart: in-memory, keyed by menuItemId ────────────────────────────────────

class CartNotifier extends Notifier<Map<String, CartItem>> {
  @override
  Map<String, CartItem> build() => {};

  void add(CartItem item) {
    final current = state[item.menuItemId];
    if (current != null) {
      state = {...state, item.menuItemId: current.copyWith(quantity: current.quantity + 1)};
    } else {
      state = {...state, item.menuItemId: item};
    }
  }

  void remove(String menuItemId) {
    final current = state[menuItemId];
    if (current == null) return;
    if (current.quantity <= 1) {
      final next = Map<String, CartItem>.from(state)..remove(menuItemId);
      state = next;
    } else {
      state = {...state, menuItemId: current.copyWith(quantity: current.quantity - 1)};
    }
  }

  void setSpecialRequest(String menuItemId, String? text) {
    final current = state[menuItemId];
    if (current == null) return;
    state = {...state, menuItemId: current.copyWith(specialRequest: text)};
  }

  void clear() => state = {};

  List<CartItem> get items => state.values.toList();

  double get total => state.values.fold(0.0, (sum, i) => sum + i.lineTotal);

  int get totalQuantity => state.values.fold(0, (sum, i) => sum + i.quantity);
}

final cartProvider = NotifierProvider<CartNotifier, Map<String, CartItem>>(
  CartNotifier.new,
);
