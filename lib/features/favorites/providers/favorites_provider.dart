import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/favorites_repository.dart';
import '../models/favorite_entry.dart';
import '../../auth/providers/auth_provider.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(Supabase.instance.client);
});

// Full list of favorited trucks with joined FoodTruck data, for FavoritesScreen.
final favoritesListProvider = FutureProvider<List<FavoriteEntry>>((ref) {
  final user = ref.watch(authProvider).asData?.value;
  if (user == null) return Future.value([]);
  return ref.read(favoritesRepositoryProvider).fetchForUser();
});

// Set of favorited truck IDs — used for heart button state across cards/profiles.
// Backed by an AsyncNotifier so we can do optimistic toggles.
class FavoritedTruckIdsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final user = ref.watch(authProvider).asData?.value;
    if (user == null) return {};
    return ref.read(favoritesRepositoryProvider).fetchFavoritedTruckIds();
  }

  Future<void> toggle(String truckId) async {
    final current = state.asData?.value ?? {};
    final isFav = current.contains(truckId);

    // Optimistic update
    state = AsyncData(
      isFav ? (Set<String>.from(current)..remove(truckId)) : {...current, truckId},
    );

    try {
      final repo = ref.read(favoritesRepositoryProvider);
      if (isFav) {
        await repo.remove(truckId);
      } else {
        await repo.add(truckId);
      }
      // Keep favoritesListProvider and follower count in sync
      ref.invalidate(favoritesListProvider);
      ref.invalidate(truckFollowerCountProvider(truckId));
    } catch (_) {
      // Revert on failure
      state = AsyncData(current);
      rethrow;
    }
  }

  // Used by FavoritesScreen where we always know the item IS favorited.
  // Avoids the race condition in toggle() where the state may still be loading.
  Future<void> remove(String truckId) async {
    final current = state.asData?.value ?? {};
    state = AsyncData(Set<String>.from(current)..remove(truckId));
    try {
      await ref.read(favoritesRepositoryProvider).remove(truckId);
      ref.invalidate(favoritesListProvider);
      ref.invalidate(truckFollowerCountProvider(truckId));
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  bool isFavorited(String truckId) => state.asData?.value.contains(truckId) ?? false;
}

final favoritedTruckIdsProvider =
    AsyncNotifierProvider<FavoritedTruckIdsNotifier, Set<String>>(
  FavoritedTruckIdsNotifier.new,
);

// Follower count for a single truck — invalidated on every heart toggle.
final truckFollowerCountProvider =
    FutureProvider.family<int, String>((ref, truckId) {
  return ref.read(favoritesRepositoryProvider).fetchFollowerCount(truckId);
});
