import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';

class BusinessTypePicker extends StatelessWidget {
  const BusinessTypePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _TypeCard(
          selected: selected == 'mobile',
          icon: Icons.local_shipping_outlined,
          label: 'Mobile',
          description: 'Food truck or pop-up',
          onTap: () => onChanged('mobile'),
        )),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _TypeCard(
          selected: selected == 'fixed',
          icon: Icons.storefront_outlined,
          label: 'Fixed Location',
          description: 'Restaurant, café, shop',
          onTap: () => onChanged('fixed'),
        )),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.selected,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: selected ? primary : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.label.copyWith(color: selected ? primary : null), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(description, style: AppTextStyles.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
