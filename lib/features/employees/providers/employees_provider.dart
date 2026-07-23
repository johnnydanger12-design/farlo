import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/location_tracking_service.dart';
import '../../../features/food_trucks/providers/food_truck_provider.dart';
import '../../../features/map/models/food_truck.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/truck_employee.dart';
import '../repositories/employees_repository.dart';

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  return EmployeesRepository(Supabase.instance.client);
});

// Owner: watch employees list for their truck
final truckEmployeesProvider =
    AsyncNotifierProvider.autoDispose.family<TruckEmployeesNotifier, List<TruckEmployee>, String>(
  (truckId) => TruckEmployeesNotifier(truckId),
);

class TruckEmployeesNotifier extends AsyncNotifier<List<TruckEmployee>> {
  TruckEmployeesNotifier(this._truckId);
  final String _truckId;

  @override
  Future<List<TruckEmployee>> build() async {
    return ref.read(employeesRepositoryProvider).fetchEmployees(_truckId);
  }

  Future<bool> invite(String email) async {
    final alreadyUser = await ref.read(employeesRepositoryProvider).inviteEmployee(_truckId, email);
    ref.invalidateSelf();
    await future;
    return alreadyUser;
  }

  Future<void> remove(String employeeId) async {
    await ref.read(employeesRepositoryProvider).removeEmployee(employeeId);
    ref.invalidateSelf();
    await future;
  }
}

// Employee: list of trucks they're assigned to
final myEmployeeTrucksProvider =
    AsyncNotifierProvider<MyEmployeeTrucksNotifier, List<FoodTruck>>(
  MyEmployeeTrucksNotifier.new,
);

class MyEmployeeTrucksNotifier extends AsyncNotifier<List<FoodTruck>> {
  @override
  Future<List<FoodTruck>> build() async {
    final user = await ref.watch(authProvider.future);
    if (user == null) return [];
    return ref.read(employeesRepositoryProvider).fetchEmployeeTrucks(user.id);
  }
}

// Employee: go-live notifier for a specific truck (parameterised by truckId)
final employeeGoLiveProvider =
    AsyncNotifierProvider.autoDispose.family<EmployeeGoLiveNotifier, FoodTruck?, String>(
  (truckId) => EmployeeGoLiveNotifier(truckId),
);

class EmployeeGoLiveNotifier extends AsyncNotifier<FoodTruck?> {
  EmployeeGoLiveNotifier(this._truckId);
  final String _truckId;

  @override
  Future<FoodTruck?> build() async {
    final data = await Supabase.instance.client
        .from('food_trucks')
        .select('*, operating_hours(*), menu_items(*), menu_categories(*)')
        .eq('id', _truckId)
        .single();
    final truck = FoodTruck.fromMap(data);

    // Watch for remote changes so an owner-terminated session flips the toggle immediately.
    final channel = Supabase.instance.client
        .channel('employee-truck-$_truckId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'food_trucks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _truckId,
          ),
          callback: (_) => _syncFromRemote(),
        )
        .subscribe();
    ref.onDispose(channel.unsubscribe);

    return truck;
  }

  Future<void> _syncFromRemote() async {
    final wasOpen = state.asData?.value?.isOpen ?? false;
    try {
      final data = await Supabase.instance.client
          .from('food_trucks')
          .select('*, operating_hours(*), menu_items(*), menu_categories(*)')
          .eq('id', _truckId)
          .single();
      final fresh = FoodTruck.fromMap(data);
      if (wasOpen && !fresh.isOpen) {
        LocationTrackingService.instance.stop();
      }
      state = AsyncData(fresh);
    } catch (_) {}
  }

  Future<void> setOpenStatus(bool isOpen) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    state = AsyncData(truck.copyWith(
      isOpen: isOpen,
      sessionStartedAt: isOpen ? DateTime.now() : null,
      openedByUserId: isOpen ? userId : null,
      // Closing always disables auto-hours server-side (see
      // FoodTruckRepository.updateOpenStatus) so cron can't reopen a truck
      // someone just manually closed — mirror that locally.
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
    state = AsyncData(truck.copyWith(
      latitude: lat,
      longitude: lng,
      address: address,
      locationUpdatedAt: DateTime.now(),
    ));
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
}

// Shared go-open handler — used by both owner dashboard and employee card.
Future<void> handleGoLive({
  required bool isOpen,
  required bool isFixed,
  required Future<void> Function(bool) setOpenStatus,
  required Future<void> Function(double, double, {String? address}) updateLocation,
  required void Function(String, {bool isError}) showMessage,
}) async {
  if (!isOpen) {
    await setOpenStatus(false);
    LocationTrackingService.instance.stop();
    return;
  }

  // Fixed businesses have a permanent address — skip GPS entirely.
  if (isFixed) {
    try {
      await setOpenStatus(true);
      showMessage('You\'re open — customers can find you now!');
    } catch (e) {
      showMessage('Could not update status: $e', isError: true);
    }
    return;
  }

  // Mobile business — request location and start GPS tracking.
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    showMessage('Location permission is required', isError: true);
    return;
  }

  showMessage('Getting your location…');

  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    String? address;
    try {
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final street = [
          if (p.subThoroughfare?.isNotEmpty ?? false) p.subThoroughfare!,
          if (p.thoroughfare?.isNotEmpty ?? false) p.thoroughfare!,
        ].join(' ');
        final city = p.locality ?? '';
        if (street.isNotEmpty && city.isNotEmpty) {
          address = '$street, $city';
        } else if (city.isNotEmpty) {
          address = city;
        } else if (street.isNotEmpty) {
          address = street;
        }
      }
    } catch (_) {}
    await updateLocation(pos.latitude, pos.longitude, address: address);
    await setOpenStatus(true);
    LocationTrackingService.instance.start(onLocation: updateLocation);
    showMessage('You\'re open — customers can find you now!');
  } catch (e) {
    showMessage('Could not get location: $e', isError: true);
  }
}
