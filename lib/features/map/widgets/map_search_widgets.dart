import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../services/storage_service.dart';
import '../models/food_truck.dart';

// ARCH-4 (code-quality.md): extracted out of the 1106-line map_screen.dart.
// Named MapSearchBar (not SearchBar) to avoid colliding with Flutter's own
// Material `SearchBar` widget.

class MapSearchBar extends StatelessWidget {
  const MapSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search, color: AppColors.textHint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search by name or cuisine…',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (controller.text.isNotEmpty) ...[
            Semantics(
              label: 'Clear search',
              button: true,
              child: GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, color: AppColors.textHint, size: 18),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class SearchResults extends StatelessWidget {
  const SearchResults({super.key, required this.searchAsync, required this.onTap, this.userPos});

  final AsyncValue<List<FoodTruck>> searchAsync;
  final ValueChanged<FoodTruck> onTap;
  final Position? userPos;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: searchAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Search failed', style: TextStyle(color: AppColors.textHint)),
          ),
          data: (trucks) {
            if (trucks.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No businesses found', style: TextStyle(color: AppColors.textHint, fontSize: 14)),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: trucks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final truck = trucks[i];
                return InkWell(
                  onTap: () => onTap(truck),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: truck.isOpen
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                : AppColors.divider,
                          ),
                          child: ClipOval(
                            child: truck.logoUrl != null
                                ? CachedNetworkImage(imageUrl: transformedImageUrl(truck.logoUrl!, width: 80, height: 80), fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => const Icon(Icons.storefront_outlined, size: 20, color: AppColors.textHint))
                                : const Icon(Icons.storefront_outlined, size: 20, color: AppColors.textHint),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(truck.name, style: AppTextStyles.label),
                              Row(
                                children: [
                                  Text(truck.cuisineType, style: AppTextStyles.caption),
                                  if (userPos != null) ...[
                                    const SizedBox(width: 6),
                                    _DistanceChip(
                                      meters: Geolocator.distanceBetween(
                                        userPos!.latitude, userPos!.longitude,
                                        truck.latitude!, truck.longitude!,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (truck.isOpen ? AppColors.openGreen : AppColors.textHint).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
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
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.meters});

  final double meters;

  @override
  Widget build(BuildContext context) {
    final miles = meters / 1609.344;
    final label = miles < 0.1 ? 'Nearby' : '${miles.toStringAsFixed(1)} mi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), width: 0.5),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), offset: Offset(0, 1), blurRadius: 1, spreadRadius: -1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me, size: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class RecentSearches extends StatelessWidget {
  const RecentSearches({
    super.key,
    required this.recents,
    required this.onTap,
    required this.onRemove,
  });

  final List<String> recents;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  const Text(
                    'Recent searches',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            ...recents.map(
              (q) => InkWell(
                onTap: () => onTap(q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 16, color: AppColors.textHint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(q, style: const TextStyle(fontSize: 14)),
                      ),
                      GestureDetector(
                        onTap: () => onRemove(q),
                        behavior: HitTestBehavior.opaque,
                        child: const Icon(Icons.close, size: 16, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
