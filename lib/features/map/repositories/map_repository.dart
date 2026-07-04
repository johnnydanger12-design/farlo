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

    // Two separate .ilike() queries merged client-side, not a single .or()
    // combinator string — PostgREST's .or() syntax treats "," and "(" ")" in
    // the *value* as structural separators, so ordinary search text like
    // "mac, cheese" or "bbq (smoked)" previously threw a parse error (bugs.md
    // §2.7.1). Each .ilike() call passes its pattern as a normal query
    // parameter, so no manual escaping/parsing is needed. Also adds the same
    // not-null location filter fetchActiveTrucks() already has — its absence
    // let a truck that had never gone live (null lat/lng) into search
    // results, crashing the results screen (bugs.md Executive Summary #1).
    final results = await Future.wait([
      _supabase
          .from(SupabaseConstants.foodTrucksTable)
          .select()
          .eq('is_active', true)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .ilike('name', '%$q%')
          .limit(10),
      _supabase
          .from(SupabaseConstants.foodTrucksTable)
          .select()
          .eq('is_active', true)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .ilike('cuisine_type', '%$q%')
          .limit(10),
    ]);

    final byId = <String, FoodTruck>{};
    for (final rows in results) {
      for (final row in rows as List) {
        final truck = FoodTruck.fromMap(row as Map<String, dynamic>);
        byId[truck.id] = truck;
      }
    }
    return byId.values.take(10).toList();
  }
}
