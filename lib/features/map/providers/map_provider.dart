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

// Streams live position updates. Yields null if permission denied or unavailable.
// distanceFilter: 10 suppresses GPS jitter — only emits after 10 m of movement.
final userLocationProvider = StreamProvider<Position?>((ref) async* {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) { yield null; return; }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) { yield null; return; }
  }
  if (permission == LocationPermission.deniedForever) { yield null; return; }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  ).map((p) => p as Position?);
});

class SelectedTruckNotifier extends Notifier<FoodTruck?> {
  @override
  FoodTruck? build() => null;

  void select(FoodTruck? truck) => state = truck;
}

final selectedTruckProvider = NotifierProvider<SelectedTruckNotifier, FoodTruck?>(
  SelectedTruckNotifier.new,
);

final truckSearchProvider = FutureProvider.family<List<FoodTruck>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value([]);
  return ref.read(mapRepositoryProvider).searchTrucks(query);
});
