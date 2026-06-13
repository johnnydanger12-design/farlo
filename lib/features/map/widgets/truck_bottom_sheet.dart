import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../models/food_truck.dart';

class TruckBottomSheet extends ConsumerWidget {
  const TruckBottomSheet({super.key, required this.truck});

  final FoodTruck truck;

  static const double _avatarRadius = 30.0;
  static const double _avatarLeft = AppSpacing.md;

  static void _showPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: InteractiveViewer(
            child: Center(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).asData?.value;
    final isAuthenticated = user != null;
    final isFav = ref.watch(favoritedTruckIdsProvider).asData?.value.contains(truck.id) ?? false;

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Card ────────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: _avatarRadius),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textHint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          truck.name,
                          style: AppTextStyles.heading3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Right column: buttons only
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAuthenticated)
                            _HeartButton(
                              truckId: truck.id,
                              isFav: isFav,
                              onTap: () => ref.read(favoritedTruckIdsProvider.notifier).toggle(truck.id),
                            ),
                          if (isAuthenticated) const SizedBox(width: AppSpacing.sm),
                          _TakeMeThereButton(
                            latitude: truck.latitude,
                            longitude: truck.longitude,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(truck.cuisineType, style: AppTextStyles.bodySmall),
                          if (truck.address != null && truck.address!.isNotEmpty)
                            Text(
                              truck.address!,
                              style: AppTextStyles.caption,
                              textAlign: TextAlign.end,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      GestureDetector(
                        onTap: () {
                          final prefix = (user?.isOwner ?? false) ? '/owner-map' : '/map';
                          context.push('$prefix/truck/${truck.id}', extra: true);
                        },
                        child: Row(
                          children: [
                            StarRatingWidget(
                              rating: truck.averageRating,
                              size: 16,
                              showValue: false,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              truck.reviewCount > 0
                                  ? '${truck.averageRating.toStringAsFixed(1)} (${truck.reviewCount})'
                                  : 'No reviews yet',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      if (truck.description != null && truck.description!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          truck.description!,
                          style: AppTextStyles.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (truck.photoUrls.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: truck.photoUrls.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (context, i) => GestureDetector(
                              onTap: () => _showPhoto(context, truck.photoUrls[i]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  truck.photoUrls[i],
                                  width: 96,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            final prefix = (user?.isOwner ?? false) ? '/owner-map' : '/map';
                            context.push('$prefix/truck/${truck.id}');
                          },
                          child: const Text('View Full Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Avatar + status text in one line ───────────────────────────
          Positioned(
            top: 0,
            left: _avatarLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TruckAvatar(
                  logoUrl: truck.logoUrl,
                  isOpen: truck.isOpen,
                  radius: _avatarRadius,
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    truck.isOpen ? 'Open Now' : 'Closed',
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
        ],
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.truckId, required this.isFav, required this.onTap});

  final String truckId;
  final bool isFav;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(isFav),
          color: isFav ? Colors.red : AppColors.textHint,
          size: 24,
        ),
      ),
    );
  }
}

class _TruckAvatar extends StatelessWidget {
  const _TruckAvatar({
    required this.logoUrl,
    required this.isOpen,
    required this.radius,
  });

  final String? logoUrl;
  final bool isOpen;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bgColor = isOpen ? Theme.of(context).colorScheme.primary : AppColors.textHint;
    return Stack(
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: Theme.of(context).colorScheme.surface, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: logoUrl != null
              ? ClipOval(
                  child: Image.network(
                    logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _TruckIcon(radius: radius),
                  ),
                )
              : _TruckIcon(radius: radius),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOpen ? AppColors.openGreen : AppColors.textHint,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _TruckIcon extends StatelessWidget {
  const _TruckIcon({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.lunch_dining, color: Colors.white, size: radius * 1.1);
  }
}

class _TakeMeThereButton extends StatelessWidget {
  const _TakeMeThereButton({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Future<void> _launch() async {
    final uri = Platform.isIOS
        ? Uri.parse('maps://?daddr=$latitude,$longitude&dirflg=d')
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
          );
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _launch,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}

