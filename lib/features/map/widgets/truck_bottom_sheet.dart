import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../models/food_truck.dart';

class TruckBottomSheet extends StatelessWidget {
  const TruckBottomSheet({super.key, required this.truck});

  final FoodTruck truck;

  // Avatar protrudes by exactly this amount above the card top edge.
  static const double _avatarRadius = 30.0;
  static const double _avatarLeft = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Card ────────────────────────────────────────────────────────
          Container(
            // Pushes the card down so the top half of the avatar floats above.
            margin: const EdgeInsets.only(top: _avatarRadius),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textHint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header row — left space clears the protruding avatar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Placeholder width: avatar diameter + gap to name
                      const SizedBox(width: _avatarRadius * 2 + AppSpacing.md),
                      Expanded(
                        child: Text(
                          truck.name,
                          style: AppTextStyles.heading3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _TakeMeThereButton(
                        latitude: truck.latitude,
                        longitude: truck.longitude,
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(truck.cuisineType, style: AppTextStyles.bodySmall),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
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
                      if (truck.description != null &&
                          truck.description!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          truck.description!,
                          style: AppTextStyles.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.push('/map/truck/${truck.id}'),
                          child: const Text('View Full Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Avatar + open badge — center of avatar sits on card's top edge ──
          Positioned(
            top: 0,
            left: _avatarLeft,
            child: SizedBox(
              width: _avatarRadius * 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TruckAvatar(
                    logoUrl: truck.logoUrl,
                    isOpen: truck.isOpen,
                    radius: _avatarRadius,
                  ),
                  const SizedBox(height: 4),
                  _OpenBadge(isOpen: truck.isOpen),
                ],
              ),
            ),
          ),
        ],
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
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: Colors.white, width: 3),
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

class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.openGreen : AppColors.textHint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          isOpen ? 'Open' : 'Closed',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
