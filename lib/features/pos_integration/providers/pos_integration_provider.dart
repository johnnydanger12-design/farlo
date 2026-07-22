import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/pos_integration.dart';
import '../repositories/pos_integration_repository.dart';

final posIntegrationRepositoryProvider = Provider<PosIntegrationRepository>((ref) {
  return PosIntegrationRepository(Supabase.instance.client);
});

final posIntegrationProvider = FutureProvider.autoDispose<PosIntegration?>((ref) async {
  final truck = ref.watch(ownerTruckProvider).asData?.value;
  if (truck == null) return null;
  return ref.read(posIntegrationRepositoryProvider).fetchForTruck(truck.id);
});
