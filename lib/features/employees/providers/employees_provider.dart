import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
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
    AsyncNotifierProvider.family<TruckEmployeesNotifier, List<TruckEmployee>, String>(
  (truckId) => TruckEmployeesNotifier(truckId),
);

class TruckEmployeesNotifier extends AsyncNotifier<List<TruckEmployee>> {
  TruckEmployeesNotifier(this._truckId);
  final String _truckId;

  @override
  Future<List<TruckEmployee>> build() async {
    return ref.read(employeesRepositoryProvider).fetchEmployees(_truckId);
  }

  Future<void> invite(String email) async {
    await ref.read(employeesRepositoryProvider).inviteEmployee(_truckId, email);
    ref.invalidateSelf();
    await future;
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
    AsyncNotifierProvider.family<EmployeeGoLiveNotifier, FoodTruck?, String>(
  (truckId) => EmployeeGoLiveNotifier(truckId),
);

class EmployeeGoLiveNotifier extends AsyncNotifier<FoodTruck?> {
  EmployeeGoLiveNotifier(this._truckId);
  final String _truckId;

  @override
  Future<FoodTruck?> build() async {
    final data = await Supabase.instance.client
        .from('food_trucks')
        .select('*, operating_hours(*), menu_items(*)')
        .eq('id', _truckId)
        .single();
    return FoodTruck.fromMap(data);
  }

  Future<void> setOpenStatus(bool isOpen) async {
    final truck = state.asData?.value;
    if (truck == null) return;
    state = AsyncData(truck.copyWith(isOpen: isOpen));
    try {
      await ref
          .read(foodTruckRepositoryProvider)
          .updateOpenStatus(truck.id, isOpen: isOpen);
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
}

// Shared go-live handler — used by both owner dashboard and employee card.
Future<void> handleGoLive({
  required bool isOpen,
  required Future<void> Function(bool) setOpenStatus,
  required Future<void> Function(double, double, {String? address}) updateLocation,
  required void Function(String, {bool isError}) showMessage,
}) async {
  if (!isOpen) {
    await setOpenStatus(false);
    return;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    showMessage('Location permission is required to go live', isError: true);
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
    showMessage('You\'re live — customers can find you now!');
  } catch (e) {
    showMessage('Could not get location: $e', isError: true);
  }
}
