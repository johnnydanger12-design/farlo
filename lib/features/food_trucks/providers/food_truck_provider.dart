import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/food_truck_repository.dart';
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
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final trucks = await ref
        .read(foodTruckRepositoryProvider)
        .fetchOwnerTrucks(user.id);
    return trucks.isEmpty ? null : trucks.first;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = Supabase.instance.client.auth.currentUser;
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
    // Optimistic update
    state = AsyncData(truck.copyWith(isOpen: isOpen));
    try {
      await ref
          .read(foodTruckRepositoryProvider)
          .updateOpenStatus(truck.id, isOpen: isOpen);
    } catch (_) {
      // Revert on failure
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

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    await ref.read(foodTruckRepositoryProvider).updateProfile(truck.id, fields);
    await refresh();
  }
}

final ownerTruckProvider =
    AsyncNotifierProvider<OwnerTruckNotifier, FoodTruck?>(OwnerTruckNotifier.new);
