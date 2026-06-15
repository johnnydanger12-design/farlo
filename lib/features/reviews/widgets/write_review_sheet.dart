import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/reviews_provider.dart';
import '../models/review.dart';

/// Call via showModalBottomSheet. Passes back `true` on successful submit.
class WriteReviewSheet extends ConsumerStatefulWidget {
  const WriteReviewSheet({super.key, required this.truckId, this.existing});

  final String truckId;
  final Review? existing; // pre-fill if editing

  @override
  ConsumerState<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends ConsumerState<WriteReviewSheet> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _rating = widget.existing!.rating;
      _commentCtrl.text = widget.existing!.comment ?? '';
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).asData?.value;
      final displayName = user?.displayName ?? 'Anonymous';
      await ref.read(reviewsRepositoryProvider).submitReview(
            truckId: widget.truckId,
            userDisplayName: displayName,
            userAvatarUrl: user?.avatarUrl,
            rating: _rating,
            comment: _commentCtrl.text,
          );
      ref.invalidate(truckReviewsProvider(widget.truckId));
      ref.invalidate(myReviewProvider(widget.truckId));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            widget.existing != null ? 'Edit Your Review' : 'Leave a Review',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: AppSpacing.md),

          // Star picker
          Row(
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = star),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    _rating >= star ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: _rating >= star ? const Color(0xFFF59E0B) : AppColors.textHint,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.md),

          // Comment field
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Share your experience (optional)',
              hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          AppButton(
            label: widget.existing != null ? 'Update Review' : 'Submit Review',
            onPressed: _loading ? null : _submit,
            isLoading: _loading,
          ),
        ],
      ),
    );
  }
}
