import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/weekly_special.dart';
import '../repositories/weekly_specials_repository.dart';

final weeklySpecialsRepositoryProvider = Provider<WeeklySpecialsRepository>((ref) {
  return WeeklySpecialsRepository(Supabase.instance.client);
});

// Owner-facing: specials for a specific composed week (Announce sheet).
final truckWeeklySpecialsWeekProvider =
    FutureProvider.autoDispose.family<List<WeeklySpecial>, (String, DateTime)>(
  (ref, key) {
    final (truckId, monday) = key;
    return ref.read(weeklySpecialsRepositoryProvider).fetchForWeek(truckId, monday);
  },
);

// Public profile display: current calendar week only, computed from the
// real date — see WeeklySpecialsRepository.fetchCurrentWeek.
final truckCurrentWeekSpecialsProvider =
    FutureProvider.autoDispose.family<List<WeeklySpecial>, String>(
  (ref, truckId) {
    return ref.read(weeklySpecialsRepositoryProvider).fetchCurrentWeek(truckId);
  },
);
