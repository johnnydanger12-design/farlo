import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/food_truck.dart';
import '../repositories/map_repository.dart';

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  return MapRepository(Supabase.instance.client);
});

final activeTrucksProvider = FutureProvider<List<FoodTruck>>((ref) {
  return ref.read(mapRepositoryProvider).fetchActiveTrucks();
});

// Returns null if permission denied or location unavailable.
final userLocationProvider = FutureProvider<Position?>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) return null;

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
});

class SelectedTruckNotifier extends Notifier<FoodTruck?> {
  @override
  FoodTruck? build() => null;

  void select(FoodTruck? truck) => state = truck;
}

final selectedTruckProvider = NotifierProvider<SelectedTruckNotifier, FoodTruck?>(
  SelectedTruckNotifier.new,
);
