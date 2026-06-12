import 'package:flutter/material.dart';
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              truck.name,
                              style: AppTextStyles.heading3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            _OpenBadge(isOpen: truck.isOpen),
                          ],
                        ),
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
                          onPressed: null,
                          child: const Text('View Full Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Avatar — center sits on the card's top-left edge ────────────
          Positioned(
            top: 0,
            left: _avatarLeft,
            child: _TruckAvatar(
              logoUrl: truck.logoUrl,
              name: truck.name,
              radius: _avatarRadius,
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
    required this.name,
    required this.radius,
  });

  final String? logoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
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
                errorBuilder: (_, _, _) => _Fallback(name: name, radius: radius),
              ),
            )
          : _Fallback(name: name, radius: radius),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
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
