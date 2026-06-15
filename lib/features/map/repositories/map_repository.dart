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
    return _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .map((rows) => rows
            .where((e) =>
                e['is_open'] == true &&
                e['latitude'] != null &&
                e['longitude'] != null)
            .map((e) => FoodTruck.fromMap(e))
            .toList());
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
