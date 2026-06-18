import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/food_truck.dart';
import '../../../core/constants/supabase_constants.dart';

class MapRepository {
  MapRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<FoodTruck>> fetchActiveTrucks() async {
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select()
        .eq('is_active', true)
        .eq('is_open', true)
        .not('latitude', 'is', null)
        .not('longitude', 'is', null);
    return (data as List).map((e) => FoodTruck.fromMap(e as Map<String, dynamic>)).toList();
  }

  Stream<List<FoodTruck>> streamActiveTrucks() {
    StreamController<List<FoodTruck>>? controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final trucks = await fetchActiveTrucks();
        final c = controller;
        if (c != null && !c.isClosed) c.add(trucks);
      } catch (_) {}
    }

    controller = StreamController<List<FoodTruck>>(
      onListen: () {
        refresh();
        channel = _supabase
            .channel('active-trucks')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: SupabaseConstants.foodTrucksTable,
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () {
        channel?.unsubscribe();
        channel = null;
        controller?.close();
      },
    );

    return controller.stream;
  }

  Future<List<FoodTruck>> searchTrucks(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select()
        .eq('is_active', true)
        .or('name.ilike.%$q%,cuisine_type.ilike.%$q%')
        .limit(10);
    return (data as List).map((e) => FoodTruck.fromMap(e as Map<String, dynamic>)).toList();
  }
}
