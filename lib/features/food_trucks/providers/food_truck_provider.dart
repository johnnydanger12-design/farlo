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
final foodTruckProvider = FutureProvider.family<FoodTruck, String>((ref, id) {
  return ref.read(foodTruckRepositoryProvider).fetchById(id);
});

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
      final channel = Supabase.instance.client
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
      ref.onDispose(channel.unsubscribe);
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
