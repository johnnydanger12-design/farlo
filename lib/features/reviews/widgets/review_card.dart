import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../models/review.dart';

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review, this.isOwn = false, this.onEdit, this.onDelete});

  final Review review;
  final bool isOwn;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                child: Text(
                  review.userDisplayName.isNotEmpty
                      ? review.userDisplayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.userDisplayName, style: AppTextStyles.label),
                    Text(_timeAgo(review.createdAt), style: AppTextStyles.caption),
                  ],
                ),
              ),
              StarRatingWidget(rating: review.rating.toDouble(), size: 14, showValue: false),
              if (isOwn) ...[
                if (onEdit != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: onEdit,
                    child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textHint),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(Icons.delete_outline, size: 18, color: AppColors.textHint),
                  ),
                ],
              ],
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(review.comment!, style: AppTextStyles.body),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
