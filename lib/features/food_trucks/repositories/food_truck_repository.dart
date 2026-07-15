import 'package:supabase_flutter/supabase_flutter.dart';
import '../../map/models/food_truck.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/extensions/future_timeout.dart';

class FoodTruckRepository {
  FoodTruckRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<FoodTruck> fetchById(String id) async {
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select('*, operating_hours(*), menu_items(*), menu_categories(*)')
        .eq('id', id)
        .single()
        .withNetworkTimeout;
    return FoodTruck.fromMap(data);
  }

  Future<List<FoodTruck>> fetchOwnerTrucks(String ownerId) async {
    final data = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select('*, operating_hours(*), menu_items(*), menu_categories(*)')
        .eq('owner_id', ownerId)
        .withNetworkTimeout;
    return (data as List).map((e) => FoodTruck.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateProfile(String id, Map<String, dynamic> fields) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update(fields)
        .eq('id', id)
        .withNetworkTimeout;
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
        .eq('id', id)
        .withNetworkTimeout;
  }

  Future<void> updateOrdersAccepting(String id, bool accepting) async {
    await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .update({'orders_accepting': accepting})
        .eq('id', id)
        .withNetworkTimeout;
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
        .eq('id', id)
        .withNetworkTimeout;
  }

  // Operating hours — all 7 days upserted in one call instead of one
  // round-trip per day (code-quality.md §2.8/§2.15 — was the only N+1
  // write-loop pattern found in the codebase, and non-atomic: a failure
  // partway through used to leave some days saved and others not).
  Future<void> upsertOperatingHoursBatch(
    String truckId,
    Map<int, ({bool isClosed, String? openTime, String? closeTime})> entries,
  ) async {
    await _supabase.from(SupabaseConstants.operatingHoursTable).upsert(
          entries.entries
              .map((e) => {
                    'truck_id': truckId,
                    'day_of_week': e.key,
                    'is_closed': e.value.isClosed,
                    'open_time': e.value.isClosed ? null : e.value.openTime,
                    'close_time': e.value.isClosed ? null : e.value.closeTime,
                  })
              .toList(),
          onConflict: 'truck_id,day_of_week',
        ).withNetworkTimeout;
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
    }).withNetworkTimeout;
  }

  Future<void> updateMenuItem(String itemId, Map<String, dynamic> fields) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).update(fields).eq('id', itemId).withNetworkTimeout;
  }

  Future<void> deleteMenuItem(String itemId) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).delete().eq('id', itemId).withNetworkTimeout;
  }

  // Bulk-insert confirmed items from a menu photo/PDF import — one round trip
  // for the whole batch rather than N (same convention as
  // upsertOperatingHoursBatch above).
  Future<void> bulkAddMenuItems(String truckId, List<({
    String name, String? description, double price, String category, int sortOrder,
  })> items) async {
    await _supabase.from(SupabaseConstants.menuItemsTable).insert([
      for (final i in items)
        {
          'truck_id': truckId,
          'name': i.name,
          'description': i.description,
          'price': i.price,
          'category': i.category,
          'sort_order': i.sortOrder,
          'is_available': true,
        },
    ]).withNetworkTimeout;
  }

  // Menu categories
  // Persists a full new ordering in one batch upsert (same pattern as
  // upsertOperatingHoursBatch above) rather than one round-trip per category.
  // Takes plain names (not MenuCategory rows) since the caller may include a
  // category that only exists on menu_items so far and has no row here yet —
  // the upsert creates it in the same call.
  Future<void> reorderMenuCategories(String truckId, List<String> namesInNewOrder) async {
    await _supabase.from(SupabaseConstants.menuCategoriesTable).upsert(
          [
            for (var i = 0; i < namesInNewOrder.length; i++)
              {
                'truck_id': truckId,
                'name': namesInNewOrder[i],
                'sort_order': i,
              },
          ],
          onConflict: 'truck_id,name',
        ).withNetworkTimeout;
  }

  // Called after adding/editing a menu item — registers a category row the
  // first time a given category name is used for this truck (e.g. a
  // newly-typed custom category), so it gets an explicit sort position
  // instead of only ever being derived from item order. Existing categories
  // are left untouched (ignoreDuplicates) so this never resets a category's
  // position that the owner has already reordered.
  Future<void> ensureCategoryExists(String truckId, String category, {required int fallbackSortOrder}) async {
    await _supabase.from(SupabaseConstants.menuCategoriesTable).upsert(
          {
            'truck_id': truckId,
            'name': category,
            'sort_order': fallbackSortOrder,
          },
          onConflict: 'truck_id,name',
          ignoreDuplicates: true,
        ).withNetworkTimeout;
  }
}
