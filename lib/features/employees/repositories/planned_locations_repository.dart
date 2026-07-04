import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/planned_location.dart';

class PlannedLocationsRepository {
  const PlannedLocationsRepository(this._client);
  final SupabaseClient _client;

  Future<List<PlannedLocation>> fetchForMonth(String truckId, int year, int month) async {
    final from = DateTime(year, month, 1).toIso8601String().substring(0, 10);
    final to   = DateTime(year, month + 1, 0).toIso8601String().substring(0, 10);
    final data = await _client
        .from('planned_locations')
        .select()
        .eq('truck_id', truckId)
        .gte('event_date', from)
        .lte('event_date', to)
        .order('event_date')
        .withNetworkTimeout;
    return (data as List).map((m) => PlannedLocation.fromMap(m)).toList();
  }

  Future<List<PlannedLocation>> fetchForWeek(String truckId, DateTime monday) async {
    final from = monday.toIso8601String().substring(0, 10);
    final to   = monday.add(const Duration(days: 6)).toIso8601String().substring(0, 10);
    final data = await _client
        .from('planned_locations')
        .select()
        .eq('truck_id', truckId)
        .gte('event_date', from)
        .lte('event_date', to)
        .order('event_date')
        .withNetworkTimeout;
    return (data as List).map((m) => PlannedLocation.fromMap(m)).toList();
  }

  Future<PlannedLocation> create({
    required String truckId,
    required DateTime eventDate,
    required String title,
    String? address,
    double? latitude,
    double? longitude,
    String? notes,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client.from('planned_locations').insert({
      'truck_id'   : truckId,
      'event_date' : eventDate.toIso8601String().substring(0, 10),
      'title'      : title.trim(),
      'address'    : address,
      'latitude'   : latitude,
      'longitude'  : longitude,
      'notes'      : notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'created_by' : userId,
    }).select().single().withNetworkTimeout;
    return PlannedLocation.fromMap(row);
  }

  Future<void> delete(String id) async {
    await _client.from('planned_locations').delete().eq('id', id).withNetworkTimeout;
  }
}
