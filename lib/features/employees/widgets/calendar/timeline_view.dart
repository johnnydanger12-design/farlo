import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../bookings/models/booking_request.dart';
import '../../models/employee_shift.dart';
import '../../models/planned_location.dart';
import '../../models/scheduled_shift.dart';
import 'calendar_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1448-line calendar_screen.dart.

const _hourHeight = 60.0;
const _startHour = 0; // 12 AM
const _endHour = 24; // 12 AM (next day)
const _timeColW = 52.0;

TimeOfDay? _parseTimeString(String s) {
  final re = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?$');
  final m = re.firstMatch(s.trim());
  if (m == null) return null;
  int h = int.parse(m.group(1)!);
  int min = int.parse(m.group(2)!);
  final ampm = m.group(3)?.toLowerCase();
  if (ampm == 'pm' && h != 12) h += 12;
  if (ampm == 'am' && h == 12) h = 0;
  return TimeOfDay(hour: h, minute: min);
}

double _topFor(int hour, int minute) => ((hour + minute / 60.0) - _startHour) * _hourHeight;

class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.bookings,
    required this.scheduled,
    required this.worked,
    required this.locations,
    required this.isOwner,
    this.onDeleteScheduled,
    this.onEditWorked,
    this.onRespondScheduled,
  });

  final List<BookingRequest> bookings;
  final List<ScheduledShift> scheduled;
  final List<EmployeeShift> worked;
  final List<PlannedLocation> locations;
  final bool isOwner;
  final void Function(ScheduledShift)? onDeleteScheduled;
  final void Function(EmployeeShift)? onEditWorked;
  final void Function(ScheduledShift, String)? onRespondScheduled;

  @override
  Widget build(BuildContext context) {
    final totalH = (_endHour - _startHour) * _hourHeight;
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.5);
    final labelStyle = AppTextStyles.caption.copyWith(color: AppColors.textHint);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── All-day: planned locations ──────────────────────────────────────
          if (locations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: locations.map((l) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colLocation.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: colLocation, width: 3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.title,
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 13,
                                  fontWeight: FontWeight.w600, height: 1.2)),
                            if (l.address != null)
                              Text(l.address!,
                                  style: const TextStyle(
                                    color: Colors.white70, fontSize: 11, height: 1.2),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
            const Divider(height: 12),
          ],
          SizedBox(
            height: totalH,
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hour labels ──────────────────────────────────────────────────
            SizedBox(
              width: _timeColW,
              height: totalH,
              child: Stack(
                children: [
                  for (int h = _startHour; h <= _endHour; h++)
                    Positioned(
                      top: (h - _startHour) * _hourHeight - 7,
                      left: 0,
                      right: 0,
                      child: Text(
                        _fmtHour(h),
                        style: labelStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Grid + events ────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Hour gridlines
                  for (int h = _startHour; h <= _endHour; h++)
                    Positioned(
                      top: (h - _startHour) * _hourHeight,
                      left: 0, right: 0,
                      child: Divider(height: 1, color: dividerColor),
                    ),

                  // Booking blocks
                  for (final b in bookings) ..._bookingBlock(context, b),

                  // Scheduled shift blocks
                  for (final s in scheduled)
                    _shiftBlock(context, s),

                  // Worked shift blocks
                  for (final w in worked)
                    _workedBlock(context, w),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
        ],
      ),
    );
  }

  String _fmtHour(int h) {
    if (h == 0 || h == 24) return '12 AM';
    if (h == 12) return '12 PM';
    return h < 12 ? '$h AM' : '${h - 12} PM';
  }

  /// Parse duration strings like "1 hour", "1.5 hours", "2 hours" → hours as double.
  double _parseDurationHours(String? s) {
    if (s == null || s.isEmpty) return 1.0;
    final match = RegExp(r'([\d.]+)').firstMatch(s);
    if (match == null) return 1.0;
    return double.tryParse(match.group(1)!) ?? 1.0;
  }

  List<Widget> _bookingBlock(BuildContext context, BookingRequest b) {
    final time = _parseTimeString(b.eventTime);
    if (time == null) return [];
    final top    = _topFor(time.hour, time.minute);
    if (top < 0 || top >= (_endHour - _startHour) * _hourHeight) return [];
    final durationH = _parseDurationHours(b.duration);
    final blockH = (durationH * _hourHeight).clamp(48.0, double.infinity);
    return [
      Positioned(
        top: top,
        left: 4, right: 4,
        child: _TimelineBlock(
          height: blockH,
          color: colBooking,
          title: b.contactName,
          subtitle: b.eventType,
        ),
      ),
    ];
  }

  Widget _shiftBlock(BuildContext context, ScheduledShift s) {
    final top  = _topFor(s.scheduledStart.hour, s.scheduledStart.minute);
    final dur  = s.scheduledEnd.difference(s.scheduledStart).inMinutes / 60.0;
    final h    = (dur * _hourHeight).clamp(32.0, double.infinity);
    if (top < 0 || top >= (_endHour - _startHour) * _hourHeight) return const SizedBox.shrink();
    return Positioned(
      top: top,
      left: 4, right: 4,
      child: _TimelineBlock(
        height: h,
        color: colScheduled,
        title: s.employeeName?.split(' ').first ?? 'Shift',
        subtitle: '${fmtTime(s.scheduledStart)} – ${fmtTime(s.scheduledEnd)}',
        status: s.status,
        trailing: isOwner && onDeleteScheduled != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Colors.white70,
                tooltip: 'Delete scheduled shift',
                onPressed: () => onDeleteScheduled!(s),
              )
            : (!isOwner && s.isPending && onRespondScheduled != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniButton(
                        label: '✓',
                        semanticLabel: 'Accept shift',
                        color: AppColors.openGreen,
                        onTap: () => onRespondScheduled!(s, 'accepted'),
                      ),
                      const SizedBox(width: 4),
                      _MiniButton(
                        label: '✗',
                        semanticLabel: 'Decline shift',
                        color: AppColors.closedRed,
                        onTap: () => onRespondScheduled!(s, 'declined'),
                      ),
                    ],
                  )
                : null),
      ),
    );
  }

  Widget _workedBlock(BuildContext context, EmployeeShift w) {
    final top = _topFor(w.clockedInAt.hour, w.clockedInAt.minute);
    final end = w.clockedOutAt ?? DateTime.now();
    final dur = end.difference(w.clockedInAt).inMinutes / 60.0;
    final h   = (dur * _hourHeight).clamp(32.0, double.infinity);
    if (top < 0 || top >= (_endHour - _startHour) * _hourHeight) return const SizedBox.shrink();
    return Positioned(
      top: top,
      left: 4, right: 4,
      child: _TimelineBlock(
        height: h,
        color: colWorked,
        title: w.employeeName?.split(' ').first ?? 'Worked',
        subtitle: w.isActive
            ? '${fmtTime(w.clockedInAt)} – active'
            : '${fmtTime(w.clockedInAt)} – ${fmtTime(w.clockedOutAt!)}',
        trailing: isOwner && !w.isActive && onEditWorked != null
            ? IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: Colors.white70,
                tooltip: 'Edit worked shift',
                onPressed: () => onEditWorked!(w),
              )
            : null,
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({
    required this.height,
    required this.color,
    required this.title,
    this.subtitle,
    this.status,
    this.trailing,
  });

  final double height;
  final Color color;
  final String title;
  final String? subtitle;
  final String? status;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && height > 44)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.semanticLabel, required this.color, required this.onTap});
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
