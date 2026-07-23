import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/location_tracking_service.dart';
import '../repositories/food_truck_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/models/food_truck.dart';

final foodTruckRepositoryProvider = Provider<FoodTruckRepository>((ref) {
  return FoodTruckRepository(Supabase.instance.client);
});

// Fetches a single truck by ID with operating hours and menu items joined.
class _FoodTruckNotifier extends AsyncNotifier<FoodTruck> {
  _FoodTruckNotifier(this._truckId);
  final String _truckId;

  @override
  Future<FoodTruck> build() async {
    final truck = await ref.read(foodTruckRepositoryProvider).fetchById(_truckId);

    // Realtime: refresh when menu items or category order change so consumer
    // profile stays current (e.g. an owner reordering categories while a
    // customer already has this profile open).
    final channel = Supabase.instance.client
        .channel('consumer-menu-$_truckId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: _truckId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: _truckId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        // Realtime for the truck row itself — is_open, hours_hidden,
        // auto_hours_enabled, orders_accepting, etc. Without this, a consumer
        // already viewing this profile never sees an owner-side change (e.g.
        // toggling "Show hours to customers") until they leave and re-enter.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: SupabaseConstants.foodTrucksTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _truckId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
    ref.onDispose(channel.unsubscribe);

    return truck;
  }
}

final foodTruckProvider =
    AsyncNotifierProvider.autoDispose.family<_FoodTruckNotifier, FoodTruck, String>(
  (id) => _FoodTruckNotifier(id),
);

// Owner's own trucks — refreshable notifier.
class OwnerTruckNotifier extends AsyncNotifier<FoodTruck?> {
  @override
  Future<FoodTruck?> build() async {
    final user = ref.watch(authProvider).asData?.value;
    if (user == null) return null;
    final trucks = await ref
        .read(foodTruckRepositoryProvider)
        .fetchOwnerTrucks(user.id);
    final truck = trucks.isEmpty ? null : trucks.first;
    // Re-attach GPS tracking if the truck was open when the app relaunched.
    // Fixed businesses never use GPS tracking — skip for them.
    if ((truck?.isOpen ?? false) && !(truck?.isFixed ?? false) && !LocationTrackingService.instance.isRunning) {
      Future.microtask(() => LocationTrackingService.instance.start(onLocation: updateLocation));
    }

    // Keep dashboard in sync when an employee changes the truck row remotely.
    if (truck != null) {
      final truckChannel = Supabase.instance.client
          .channel('owner-truck-${truck.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: SupabaseConstants.foodTrucksTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: truck.id,
            ),
            callback: (_) => refresh(),
          )
          .subscribe();
      ref.onDispose(truckChannel.unsubscribe);

      // Realtime for menu item changes (availability toggles, add/remove,
      // item reordering) and category reordering — both needed so a second
      // session on the same truck (e.g. an employee's dashboard, or the
      // owner on another device) sees reorders live instead of only after
      // navigating away and back.
      final menuChannel = Supabase.instance.client
          .channel('owner-menu-${truck.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menu_items',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'truck_id',
              value: truck.id,
            ),
            callback: (_) => refresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menu_categories',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'truck_id',
              value: truck.id,
            ),
            callback: (_) => refresh(),
          )
          .subscribe();
      ref.onDispose(menuChannel.unsubscribe);
    }

    return truck;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authProvider).asData?.value;
      if (user == null) return null;
      final trucks = await ref
          .read(foodTruckRepositoryProvider)
          .fetchOwnerTrucks(user.id);
      return trucks.isEmpty ? null : trucks.first;
    });
  }

  Future<void> setOpenStatus(bool isOpen) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    final userId = ref.read(authProvider).asData?.value?.id;
    state = AsyncData(truck.copyWith(
      isOpen: isOpen,
      sessionStartedAt: isOpen ? DateTime.now() : null,
      openedByUserId: isOpen ? userId : null,
      // Closing always disables auto-hours server-side (see
      // FoodTruckRepository.updateOpenStatus) so cron can't reopen a truck
      // someone just manually closed — mirror that locally so the switch
      // reflects it immediately instead of waiting on a realtime refetch.
      autoHoursEnabled: isOpen ? null : false,
    ));
    try {
      await ref
          .read(foodTruckRepositoryProvider)
          .updateOpenStatus(truck.id, isOpen: isOpen, userId: userId);
    } catch (_) {
      state = AsyncData(truck);
      rethrow;
    }
  }

  Future<void> updateLocation(double lat, double lng, {String? address}) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    state = AsyncData(
      truck.copyWith(
        latitude: lat,
        longitude: lng,
        address: address,
        locationUpdatedAt: DateTime.now(),
      ),
    );
    await ref
        .read(foodTruckRepositoryProvider)
        .updateLocation(truck.id, lat, lng, address: address);
  }

  Future<void> updateOrdersAccepting(bool accepting) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    state = AsyncData(truck.copyWith(ordersAccepting: accepting));
    try {
      await ref.read(foodTruckRepositoryProvider).updateOrdersAccepting(truck.id, accepting);
    } catch (_) {
      state = AsyncData(truck);
      rethrow;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    await ref.read(foodTruckRepositoryProvider).updateProfile(truck.id, fields);
    await refresh();
  }
}

final ownerTruckProvider =
    AsyncNotifierProvider<OwnerTruckNotifier, FoodTruck?>(OwnerTruckNotifier.new);

// Category name -> currently purchasable right now (get-category-availability
// edge function). A category missing from the returned map has no purchase
// window at all and is always available whenever the truck is open — see
// that function for the full computation, which reuses the exact same
// truck-local-time window logic as sync-truck-hours and create-payment-intent
// so the badge shown here can never disagree with what checkout will allow.
final categoryAvailabilityProvider =
    FutureProvider.autoDispose.family<Map<String, bool>, String>((ref, truckId) async {
  final res = await Supabase.instance.client.functions.invoke(
    'get-category-availability',
    body: {'truck_id': truckId},
  );
  final data = res.data as Map<String, dynamic>? ?? {};
  return data.map((key, value) => MapEntry(key, value as bool));
});
