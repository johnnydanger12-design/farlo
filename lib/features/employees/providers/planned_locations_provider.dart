import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/planned_location.dart';
import '../repositories/planned_locations_repository.dart';

final plannedLocationsRepositoryProvider = Provider<PlannedLocationsRepository>((ref) {
  return PlannedLocationsRepository(Supabase.instance.client);
});

typedef _MonthKey = (String, int, int);

// Owner/employee: planned locations for a calendar month
final truckPlannedLocationsProvider = FutureProvider.autoDispose.family<List<PlannedLocation>, _MonthKey>(
  (ref, key) {
    final (truckId, year, month) = key;
    return ref
        .read(plannedLocationsRepositoryProvider)
        .fetchForMonth(truckId, year, month);
  },
);

// Planned locations for the current week (used by ShiftWeekCard)
final truckPlannedLocationsWeekProvider =
    FutureProvider.autoDispose.family<List<PlannedLocation>, (String, DateTime)>(
  (ref, key) {
    final (truckId, monday) = key;
    return ref
        .read(plannedLocationsRepositoryProvider)
        .fetchForWeek(truckId, monday);
  },
);
