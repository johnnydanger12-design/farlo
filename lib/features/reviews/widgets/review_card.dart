import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../models/review.dart';

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.review,
    this.isOwn = false,
    this.isOwnerOfTruck = false,
    this.onEdit,
    this.onDelete,
    this.onReply,
    this.onEditReply,
    this.onDeleteReply,
  });

  final Review review;
  final bool isOwn;
  final bool isOwnerOfTruck;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;
  final VoidCallback? onEditReply;
  final VoidCallback? onDeleteReply;

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
                child: review.userAvatarUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: review.userAvatarUrl!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Text(
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
                      )
                    : Text(
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
                  Semantics(
                    label: 'Edit your review',
                    button: true,
                    child: GestureDetector(
                      onTap: onEdit,
                      child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textHint),
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    label: 'Delete your review',
                    button: true,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: const Icon(Icons.delete_outline, size: 18, color: AppColors.textHint),
                    ),
                  ),
                ],
              ],
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(review.comment!, style: AppTextStyles.body),
          ],
          if (review.ownerResponse != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store_outlined, size: 14,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Owner response',
                        style: AppTextStyles.caption.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isOwnerOfTruck) ...[
                        const Spacer(),
                        Semantics(
                          label: 'Edit your reply',
                          button: true,
                          child: GestureDetector(
                            onTap: onEditReply,
                            child: const Icon(Icons.edit_outlined, size: 15, color: AppColors.textHint),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Semantics(
                          label: 'Delete your reply',
                          button: true,
                          child: GestureDetector(
                            onTap: onDeleteReply,
                            child: const Icon(Icons.delete_outline, size: 15, color: AppColors.textHint),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(review.ownerResponse!, style: AppTextStyles.body),
                ],
              ),
            ),
          ] else if (isOwnerOfTruck) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onReply,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.reply_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      'Reply',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
