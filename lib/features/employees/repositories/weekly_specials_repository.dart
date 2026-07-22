import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/weekly_special.dart';

class WeeklySpecialsRepository {
  const WeeklySpecialsRepository(this._client);
  final SupabaseClient _client;

  Future<List<WeeklySpecial>> fetchForWeek(String truckId, DateTime monday) async {
    final from = monday.toIso8601String().substring(0, 10);
    final to = monday.add(const Duration(days: 6)).toIso8601String().substring(0, 10);
    final data = await _client
        .from('weekly_specials')
        .select()
        .eq('truck_id', truckId)
        .gte('event_date', from)
        .lte('event_date', to)
        .order('event_date', ascending: true)
        .withNetworkTimeout;
    return (data as List).map((m) => WeeklySpecial.fromMap(m)).toList();
  }

  // Public profile display: the current calendar week only, computed from
  // the real date at query time — this is what makes specials entered ahead
  // of time for a future week (e.g. an owner planning next week's specials
  // on a Saturday) stay invisible until that week's Monday actually arrives,
  // with no cron/scheduling needed.
  Future<List<WeeklySpecial>> fetchCurrentWeek(String truckId) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final today = DateTime(now.year, now.month, now.day);
    final sunday = monday.add(const Duration(days: 6));
    final data = await _client
        .from('weekly_specials')
        .select()
        .eq('truck_id', truckId)
        .gte('event_date', today.toIso8601String().substring(0, 10))
        .lte('event_date', sunday.toIso8601String().substring(0, 10))
        .order('event_date', ascending: true)
        .withNetworkTimeout;
    return (data as List).map((m) => WeeklySpecial.fromMap(m)).toList();
  }

  Future<WeeklySpecial> create({
    required String truckId,
    required DateTime eventDate,
    required String title,
    double? price,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client.from('weekly_specials').insert({
      'truck_id': truckId,
      'event_date': eventDate.toIso8601String().substring(0, 10),
      'title': title.trim(),
      'price': price,
      'created_by': userId,
    }).select().single().withNetworkTimeout;
    return WeeklySpecial.fromMap(row);
  }

  Future<void> update({
    required String id,
    required String title,
    double? price,
  }) async {
    await _client.from('weekly_specials').update({
      'title': title.trim(),
      'price': price,
    }).eq('id', id).withNetworkTimeout;
  }

  Future<void> delete(String id) async {
    await _client.from('weekly_specials').delete().eq('id', id).withNetworkTimeout;
  }
}
