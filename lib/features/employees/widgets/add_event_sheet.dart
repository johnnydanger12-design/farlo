import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Bottom sheet that lets owners choose what type of event to add.
/// Returns the chosen [AddEventType] or null if dismissed.
enum AddEventType { shift, location, booking, announceWeek }

class AddEventSheet extends StatelessWidget {
  const AddEventSheet({super.key, required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Add Event', style: AppTextStyles.heading3),
          const SizedBox(height: 16),
          _Option(
            icon: Icons.people_outline,
            color: const Color(0xFF6366F1),
            title: 'Assign Shift',
            subtitle: 'Schedule an employee for a shift',
            onTap: () => Navigator.pop(context, AddEventType.shift),
          ),
          _Option(
            icon: Icons.location_on_outlined,
            color: const Color(0xFF0D9488),
            title: 'Plan a Location',
            subtitle: 'Add where you\'ll be on a specific day',
            onTap: () => Navigator.pop(context, AddEventType.location),
          ),
          _Option(
            icon: Icons.event_outlined,
            color: const Color(0xFFF59E0B),
            title: 'Add Booking',
            subtitle: 'View and manage event booking requests',
            onTap: () => Navigator.pop(context, AddEventType.booking),
          ),
          _Option(
            icon: Icons.campaign_outlined,
            color: AppColors.primary,
            title: 'Announce This Week',
            subtitle: 'Send followers your weekly schedule in one notification',
            onTap: () => Navigator.pop(context, AddEventType.announceWeek),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
