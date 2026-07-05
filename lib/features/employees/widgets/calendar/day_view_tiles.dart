import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/employee_shift.dart';
import '../../models/scheduled_shift.dart';
import 'calendar_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1448-line calendar_screen.dart.

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.color, required this.time, required this.title, this.subtitle});
  final Color color;
  final String time;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3, height: 44,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  Text(title, style: AppTextStyles.bodySmall),
                  if (subtitle != null)
                    Text(subtitle!, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                ],
              ),
            ),
          ],
        ),
      );
}

class ScheduledTile extends StatelessWidget {
  const ScheduledTile({super.key, required this.shift, required this.isOwner, this.onDelete, this.onRespond});
  final ScheduledShift shift;
  final bool isOwner;
  final VoidCallback? onDelete;
  final void Function(String)? onRespond;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (shift.status) {
      'accepted' => AppColors.openGreen,
      'declined' => AppColors.closedRed,
      _          => colScheduled,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3, height: 44,
            decoration: BoxDecoration(color: colScheduled, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtTime(shift.scheduledStart)} – ${fmtTime(shift.scheduledEnd)}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
                if (isOwner && shift.employeeName != null)
                  Text(shift.employeeName!.split(' ').first, style: AppTextStyles.bodySmall),
                if (shift.notes?.isNotEmpty ?? false)
                  Text(shift.notes!, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shift.status[0].toUpperCase() + shift.status.substring(1),
                    style: AppTextStyles.caption
                        .copyWith(color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!isOwner && shift.isPending && onRespond != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => onRespond!('declined'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.closedRed,
                          side: const BorderSide(color: AppColors.closedRed),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => onRespond!('accepted'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.openGreen,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isOwner && onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.textHint,
              tooltip: 'Delete shift',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class WorkedTile extends StatelessWidget {
  const WorkedTile({super.key, required this.shift, required this.isOwner, this.onEdit});
  final EmployeeShift shift;
  final bool isOwner;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final d           = shift.elapsed;
    final durationStr = d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes % 60}m';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3, height: 44,
            decoration: BoxDecoration(color: colWorked, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.isActive
                      ? '${fmtTime(shift.clockedInAt)} – active'
                      : '${fmtTime(shift.clockedInAt)} – ${fmtTime(shift.clockedOutAt!)}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
                if (isOwner && shift.employeeName != null)
                  Text(shift.employeeName!.split(' ').first, style: AppTextStyles.bodySmall),
                if (!shift.isActive)
                  Text(durationStr, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          if (isOwner && !shift.isActive && onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppColors.textHint,
              tooltip: 'Edit shift',
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}
