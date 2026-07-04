import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/favorite_entry.dart';

class FavoritesRepository {
  FavoritesRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<FavoriteEntry>> fetchForUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _supabase
        .from(SupabaseConstants.favoritesTable)
        .select('*, food_trucks(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .withNetworkTimeout;
    return (data as List).map((e) => FavoriteEntry.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Returns the set of truck IDs favorited by the current user.
  Future<Set<String>> fetchFavoritedTruckIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final data = await _supabase
        .from(SupabaseConstants.favoritesTable)
        .select('truck_id')
        .eq('user_id', userId)
        .withNetworkTimeout;
    return {for (final row in data as List) row['truck_id'] as String};
  }

  Future<void> add(String truckId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from(SupabaseConstants.favoritesTable).upsert(
      {'user_id': userId, 'truck_id': truckId},
      onConflict: 'user_id,truck_id',
    ).withNetworkTimeout;
  }

  Future<void> remove(String truckId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase
        .from(SupabaseConstants.favoritesTable)
        .delete()
        .eq('user_id', userId)
        .eq('truck_id', truckId)
        .withNetworkTimeout;
  }

  Future<int> fetchFollowerCount(String truckId) async {
    final result = await _supabase.rpc(
      'get_truck_follower_count',
      params: {'p_truck_id': truckId},
    ).withNetworkTimeout;
    return (result as int?) ?? 0;
  }
}
