import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../models/food_truck.dart';

class TruckBottomSheet extends StatelessWidget {
  const TruckBottomSheet({super.key, required this.truck});

  final FoodTruck truck;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(truck.name, style: AppTextStyles.heading3)),
                    _OpenBadge(isOpen: truck.isOpen),
                  ],
                ),
                const SizedBox(height: 4),
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
                if (truck.description != null && truck.description!.isNotEmpty) ...[
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
    );
  }
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.openGreen : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            isOpen ? 'Open' : 'Closed',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
