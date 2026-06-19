import 'package:supabase_flutter/supabase_flutter.dart';
import '../../map/models/food_truck.dart';
import '../../../core/constants/supabase_constants.dart';

class FoodTruckRepository {
  FoodTruckRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<FoodTruck> fetchById(String id) async {
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select('*, operating_hours(*), menu_items(*)')
        .eq('id', id)
        .single();
    return FoodTruck.fromMap(data);
  }

  Future<List<FoodTruck>> fetchOwnerTrucks(String ownerId) async {
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select('*, operating_hours(*), menu_items(*)')
        .eq('owner_id', ownerId);
    return (data as List).map((e) => FoodTruck.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateProfile(String id, Map<String, dynamic> fields) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update(fields)
        .eq('id', id);
  }

  Future<void> updateOpenStatus(String id, {required bool isOpen, String? userId}) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update({
          'is_open': isOpen,
          'session_started_at': isOpen ? DateTime.now().toUtc().toIso8601String() : null,
          'opened_by_user_id': isOpen ? userId : null,
          if (isOpen) 'has_ever_opened': true,
        })
        .eq('id', id);
  }

  Future<void> updateOrdersAccepting(String id, bool accepting) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update({'orders_accepting': accepting})
        .eq('id', id);
  }

  Future<void> updateLocation(String id, double lat, double lng, {String? address}) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update({
          'latitude': lat,
          'longitude': lng,
          'location_updated_at': DateTime.now().toUtc().toIso8601String(),
          'address': address,
        })
        .eq('id', id);
  }

  // Operating hours — upsert per day
  Future<void> upsertOperatingHours(String truckId, int dayOfWeek, {
    required bool isClosed,
    String? openTime,
    String? closeTime,
  }) async {
    await _supabase
        .from(SupabaseConstants.operatingHoursTable)
        .upsert({
          'truck_id': truckId,
          'day_of_week': dayOfWeek,
          'is_closed': isClosed,
          'open_time': isClosed ? null : openTime,
          'close_time': isClosed ? null : closeTime,
        }, onConflict: 'truck_id,day_of_week');
  }

  // Menu items
  Future<void> addMenuItem(String truckId, {
    required String name,
    String? description,
    required double price,
    required String category,
    required int sortOrder,
    String? imageUrl,
  }) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).insert({
      'truck_id': truckId,
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'sort_order': sortOrder,
      'is_available': true,
      'image_url': ?imageUrl,
    });
  }

  Future<void> updateMenuItem(String itemId, Map<String, dynamic> fields) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).update(fields).eq('id', itemId);
  }

  Future<void> deleteMenuItem(String itemId) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).delete().eq('id', itemId);
  }
}
