import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';

// ARCH-4 (code-quality.md): extracted out of the 1425-line truck_profile_screen.dart.

class ReviewFilter extends StatelessWidget {
  const ReviewFilter({super.key, required this.selected, required this.onSelected});

  final int? selected;
  final void Function(int?) onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ReviewFilterChip(
            label: 'All',
            active: selected == null,
            onTap: () => onSelected(null),
            primary: primary,
          ),
          ...List.generate(5, (i) {
            final star = 5 - i;
            return ReviewFilterChip(
              label: '$star ★',
              active: selected == star,
              onTap: () => onSelected(selected == star ? null : star),
              primary: primary,
            );
          }),
        ],
      ),
    );
  }
}

class ReviewFilterChip extends StatelessWidget {
  const ReviewFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? primary : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class OwnerReplySheet extends StatefulWidget {
  const OwnerReplySheet({super.key, this.existingResponse});
  final String? existingResponse;

  @override
  State<OwnerReplySheet> createState() => _OwnerReplySheetState();
}

class _OwnerReplySheetState extends State<OwnerReplySheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existingResponse);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final canSubmit = _ctrl.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.existingResponse == null ? 'Reply to Review' : 'Edit Reply',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Thank the customer or address their feedback…',
              alignLabelWithHint: true,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              child: Text(widget.existingResponse == null ? 'Post Reply' : 'Save Reply'),
            ),
          ),
        ],
      ),
    );
  }
}
