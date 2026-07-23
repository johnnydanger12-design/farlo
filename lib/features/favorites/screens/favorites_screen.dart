import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/tab_reselect_provider.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../../services/storage_service.dart';
import '../../account/widgets/account_widgets.dart';
import '../../map/models/food_truck.dart';
import '../../map/providers/map_provider.dart';
import '../../map/widgets/map_search_widgets.dart';
import '../models/favorite_entry.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/favorites_provider.dart';
import '../../food_trucks/providers/announcement_prefs_provider.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TabReselectEvent?>(tabReselectProvider, (prev, next) {
      if (next != null && next.index == 1 && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ref.invalidate(favoritesListProvider);
        ref.invalidate(nearbyRecommendedProvider);
      }
    });
    final asyncFavorites = ref.watch(favoritesListProvider);
    final asyncNearby = ref.watch(nearbyRecommendedProvider);
    final userPos = ref.watch(userLocationProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(favoritesListProvider);
          ref.invalidate(nearbyRecommendedProvider);
        },
        color: Theme.of(context).colorScheme.primary,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SectionHeader('Following'),
            asyncFavorites.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  children: [
                    Text('Could not load favorites', style: AppTextStyles.bodySmall),
                    TextButton(
                      onPressed: () => ref.invalidate(favoritesListProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (favorites) {
                if (favorites.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'Tap the heart on any business to follow it — it\'ll show up here.',
                      style: AppTextStyles.bodySmall,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final entry in favorites) ...[
                      _FavoriteTile(entry: entry),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Recommended Near You'),
            asyncNearby.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('Could not load recommendations', style: AppTextStyles.bodySmall),
              ),
              data: (nearby) {
                if (nearby.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No other businesses found nearby yet.',
                      style: AppTextStyles.bodySmall,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final truck in nearby) ...[
                      _NearbyTile(truck: truck, userPos: userPos),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyTile extends ConsumerWidget {
  const _NearbyTile({required this.truck, this.userPos});

  final FoodTruck truck;
  final Position? userPos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.push('/map/truck/${truck.id}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              ),
              child: truck.logoUrl != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: transformedImageUrl(truck.logoUrl!, width: 112, height: 112),
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const _TruckIcon(),
                      ),
                    )
                  : const _TruckIcon(),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    truck.name,
                    style: AppTextStyles.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(truck.cuisineType, style: AppTextStyles.caption),
                      if (userPos != null && truck.latitude != null && truck.longitude != null) ...[
                        const SizedBox(width: 6),
                        DistanceChip(
                          meters: Geolocator.distanceBetween(
                            userPos!.latitude, userPos!.longitude,
                            truck.latitude!, truck.longitude!,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (truck.reviewCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StarRatingWidget(rating: truck.averageRating, size: 12, showValue: false),
                        const SizedBox(width: 4),
                        Text(
                          '${truck.averageRating.toStringAsFixed(1)} (${truck.reviewCount})',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (truck.isOpen ? AppColors.openGreen : AppColors.textHint)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    truck.isOpen ? 'Open' : 'Closed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: truck.isOpen ? AppColors.openGreen : AppColors.textHint,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label: 'Follow ${truck.name}',
                  button: true,
                  child: GestureDetector(
                    onTap: () => ref.read(favoritedTruckIdsProvider.notifier).toggle(truck.id),
                    child: Icon(Icons.favorite_border, color: AppColors.textHint, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({required this.entry});

  final FavoriteEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final truck = entry.truck;

    return GestureDetector(
      onTap: truck != null ? () => context.push('/map/truck/${truck.id}') : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Logo
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              ),
              child: truck?.logoUrl != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: transformedImageUrl(truck!.logoUrl!, width: 112, height: 112),
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const _TruckIcon(),
                      ),
                    )
                  : const _TruckIcon(),
            ),
            const SizedBox(width: AppSpacing.md),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    truck?.name ?? 'Unknown business',
                    style: AppTextStyles.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    truck?.cuisineType ?? '',
                    style: AppTextStyles.caption,
                  ),
                  if (truck != null && truck.reviewCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StarRatingWidget(rating: truck.averageRating, size: 12, showValue: false),
                        const SizedBox(width: 4),
                        Text(
                          '${truck.averageRating.toStringAsFixed(1)} (${truck.reviewCount})',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Open badge + unfavorite
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (truck != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (truck.isOpen ? AppColors.openGreen : AppColors.textHint)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      truck.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: truck.isOpen ? AppColors.openGreen : AppColors.textHint,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Announcement bell toggle
                    if (truck != null)
                      Semantics(
                        label: (ref.watch(announcementPrefProvider(entry.truckId)).asData?.value ?? true)
                            ? 'Mute announcements for ${truck.name}'
                            : 'Unmute announcements for ${truck.name}',
                        button: true,
                        child: GestureDetector(
                          onTap: () async {
                            await ref.read(announcementPrefProvider(entry.truckId).notifier).toggle();
                            final enabled = ref.read(announcementPrefProvider(entry.truckId)).asData?.value ?? true;
                            if (context.mounted) {
                              context.showInfo(
                                enabled
                                    ? 'Announcements on for ${truck.name}'
                                    : 'Announcements muted for ${truck.name}',
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              );
                            }
                          },
                          child: Builder(builder: (ctx) {
                            final enabled = ref
                                .watch(announcementPrefProvider(entry.truckId))
                                .asData?.value ?? true;
                            return Icon(
                              enabled
                                  ? Icons.notifications_rounded
                                  : Icons.notifications_off_outlined,
                              color: enabled ? AppColors.textSecondary : AppColors.textHint,
                              size: 20,
                            );
                          }),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: 'Remove ${truck?.name ?? 'this business'} from favorites',
                      button: true,
                      child: GestureDetector(
                        onTap: () => ref.read(favoritedTruckIdsProvider.notifier).remove(entry.truckId),
                        child: const Icon(Icons.favorite_rounded, color: Colors.red, size: 22),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TruckIcon extends StatelessWidget {
  const _TruckIcon();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.storefront_outlined,
      color: Theme.of(context).colorScheme.primary,
      size: 28,
    );
  }
}
