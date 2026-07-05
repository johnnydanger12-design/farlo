import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/booking_request.dart';

// ARCH-4 (code-quality.md): extracted out of the 1372-line booking_requests_screen.dart.

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String fmtShort(DateTime d) => '${months[d.month - 1]} ${d.day}, ${d.year}';
String fmtLong(DateTime d) => '${weekdays[d.weekday - 1]}, ${monthsFull[d.month - 1]} ${d.day}, ${d.year}';

int daysUntil(DateTime eventDate) {
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final day = DateTime(eventDate.year, eventDate.month, eventDate.day);
  return day.difference(today).inDays;
}

bool isOver(BookingRequest r) {
  final parts = r.eventTime.trim().split(' ');
  final hm = parts.isNotEmpty ? parts[0].split(':') : <String>[];
  int hour = hm.isNotEmpty ? (int.tryParse(hm[0]) ?? 0) : 0;
  final minute = hm.length > 1 ? (int.tryParse(hm[1]) ?? 0) : 0;
  final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
  if (isPm && hour != 12) hour += 12;
  if (!isPm && hour == 12) hour = 0;
  final durationMinutes = r.duration != null
      ? ((double.tryParse(r.duration!.split(' ').first) ?? 0) * 60).round()
      : 0;
  final end = DateTime(r.eventDate.year, r.eventDate.month, r.eventDate.day, hour, minute)
      .add(Duration(minutes: durationMinutes));
  return end.isBefore(DateTime.now());
}

class MsgBadge extends StatelessWidget {
  const MsgBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
