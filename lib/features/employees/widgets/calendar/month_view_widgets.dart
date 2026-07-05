import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

// ARCH-4 (code-quality.md): extracted out of the 1448-line calendar_screen.dart.

class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.date, required this.isOwner, required this.onAssign});
  final DateTime date;
  final bool isOwner;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months   = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final label    = '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.label),
          const Spacer(),
          if (isOwner)
            TextButton.icon(
              onPressed: onAssign,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Event'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

class ChipDayCell extends StatelessWidget {
  const ChipDayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isWeekend,
    required this.chips,
    required this.overflowCount,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final bool isWeekend;
  final List<(String, Color)> chips;
  final int overflowCount;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day number
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? primary
                    : isToday
                        ? primary.withValues(alpha: 0.12)
                        : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : isToday
                          ? primary
                          : isWeekend
                              ? AppColors.textHint
                              : null,
                ),
              ),
            ),
          ),
        ),
        // Event chips
        ...chips.take(2).map((e) {
          final (label, color) = e;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
        if (overflowCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+$overflowCount',
              style: AppTextStyles.caption.copyWith(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 5, height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
