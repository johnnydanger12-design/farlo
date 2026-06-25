import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../bookings/models/booking_request.dart';
import '../../bookings/providers/bookings_provider.dart';
import '../models/scheduled_shift.dart';
import '../providers/planned_locations_provider.dart';
import '../providers/shifts_provider.dart';
import '../screens/calendar_screen.dart';
import 'add_event_sheet.dart';
import '../../bookings/widgets/book_truck_sheet.dart';
import 'announce_week_sheet.dart';
import 'assign_shift_sheet.dart';
import 'plan_location_sheet.dart';

const _colBooking   = AppColors.primary;
const _colScheduled = Color(0xFF6366F1);
const _colWorked    = Color(0xFF6B7280);
const _colLocation  = Color(0xFF0D9488);

const _weekdayShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _monthNames   = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];
const _weekdayNames = [
  'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday',
];

DateTime _mondayOf(DateTime d) {
  final offset = d.weekday - 1; // weekday: 1=Mon … 7=Sun
  return DateTime(d.year, d.month, d.day - offset);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtTime(DateTime dt) {
  final h    = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final m    = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour < 12 ? 'am' : 'pm';
  return '$h:$m $ampm';
}

// ─── Public widget ────────────────────────────────────────────────────────────

class ShiftWeekCard extends ConsumerStatefulWidget {
  const ShiftWeekCard({
    super.key,
    required this.truckId,
    required this.truckName,
    required this.isOwner,
    this.onRespondScheduled,
  });

  final String truckId;
  final String truckName;
  final bool isOwner;
  final void Function(ScheduledShift, String)? onRespondScheduled;

  @override
  ConsumerState<ShiftWeekCard> createState() => _ShiftWeekCardState();
}

class _ShiftWeekCardState extends ConsumerState<ShiftWeekCard> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _selectedDate = DateTime(n.year, n.month, n.day);
  }

  List<DateTime> get _weekDates {
    final monday = _mondayOf(_selectedDate);
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  void _openCalendar() {
    if (widget.isOwner) {
      // Owner: use GoRouter so double-tapping Dashboard resets the stack.
      context.push('/dashboard/calendar', extra: {
        'truckId'    : widget.truckId,
        'truckName'  : widget.truckName,
        'isOwner'    : true,
        'initialDate': _selectedDate,
      });
    } else {
      // Employee: use Navigator.push to stay within the consumer shell.
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CalendarScreen(
            truckId: widget.truckId,
            truckName: widget.truckName,
            isOwner: false,
            initialDate: _selectedDate,
            onRespondScheduled: widget.onRespondScheduled,
          ),
        ),
      );
    }
  }

  Future<void> _showAddEvent(DateTime date) async {
    final type = await showModalBottomSheet<AddEventType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(isOwner: widget.isOwner),
    );
    if (type == null || !mounted) return;
    final y = date.year;
    final m = date.month;

    switch (type) {
      case AddEventType.shift:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AssignShiftSheet(truckId: widget.truckId, initialDate: date),
        );
        ref.invalidate(truckScheduledShiftsProvider((widget.truckId, y, m)));
      case AddEventType.location:
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PlanLocationSheet(truckId: widget.truckId, initialDate: date),
        );
        ref.invalidate(truckPlannedLocationsProvider((widget.truckId, y, m)));
      case AddEventType.booking:
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ManualBookingSheet(
            truckId: widget.truckId,
            truckName: widget.truckName,
          ),
        );
        ref.invalidate(acceptedBookingsForMonthProvider(
            (widget.truckId, date.year, date.month)));
      case AddEventType.announceWeek:
        final monday = DateTime(date.year, date.month, date.day - (date.weekday - 1));
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AnnounceWeekSheet(
            truckId: widget.truckId,
            truckName: widget.truckName,
            weekMonday: monday,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final key = (widget.truckId, _selectedDate.year, _selectedDate.month);

    final worked = widget.isOwner
        ? ref.watch(truckShiftsProvider(key)).asData?.value ?? []
        : ref.watch(myShiftsProvider(key)).asData?.value ?? [];
    final scheduled = widget.isOwner
        ? ref.watch(truckScheduledShiftsProvider(key)).asData?.value ?? []
        : ref.watch(myScheduledShiftsProvider(key)).asData?.value ?? [];
    final bookings = widget.isOwner
        ? ref.watch(acceptedBookingsForMonthProvider(key)).asData?.value ?? []
        : <BookingRequest>[];
    final locations = ref.watch(truckPlannedLocationsProvider(key)).asData?.value ?? [];

    final dayWorked    = worked.where((s) => _sameDay(s.clockedInAt, _selectedDate)).toList();
    final dayScheduled = scheduled.where((s) => _sameDay(s.scheduledStart, _selectedDate)).toList();
    final dayBookings  = bookings.where((b) => _sameDay(b.eventDate, _selectedDate)).toList();
    final dayLocations = locations.where((l) => _sameDay(l.eventDate, _selectedDate)).toList();

    final isToday  = _sameDay(_selectedDate, todayDate);
    final weekday  = _weekdayNames[_selectedDate.weekday - 1];
    final month    = _monthNames[_selectedDate.month - 1];
    final weekDates = _weekDates;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          GestureDetector(
            onTap: _openCalendar,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${_selectedDate.day}',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(month, style: AppTextStyles.heading3),
                      Text(
                        isToday ? 'Today, $weekday' : weekday,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (widget.isOwner)
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _showAddEvent(_selectedDate),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        shape: const CircleBorder(),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Week strip ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: List.generate(7, (i) {
                final date   = weekDates[i];
                final isSelected = _sameDay(date, _selectedDate);
                final isDayToday = _sameDay(date, todayDate);
                final isWeekend = i >= 5;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = date),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _weekdayShort[i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isWeekend
                                ? AppColors.textHint
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : isDayToday
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected || isDayToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected
                                  ? Colors.white
                                  : isDayToday
                                      ? Theme.of(context).colorScheme.primary
                                      : isWeekend
                                          ? AppColors.textHint
                                          : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const Divider(height: 1),

          // ── Event list ──────────────────────────────────────────────────────
          if (dayBookings.isEmpty && dayScheduled.isEmpty && dayWorked.isEmpty && dayLocations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'No events',
                style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                children: [
                  ...dayLocations.map((l) => _EventRow(
                        color: _colLocation,
                        time: l.address ?? '',
                        title: l.title,
                        subtitle: l.notes,
                      )),
                  ...dayBookings.map((b) => _EventRow(
                        color: _colBooking,
                        time: b.eventTime,
                        title: b.contactName,
                        subtitle: b.eventType,
                      )),
                  ...dayScheduled.map((s) => _ScheduledEventRow(
                        shift: s,
                        isOwner: widget.isOwner,
                        onRespond: widget.onRespondScheduled != null
                            ? (status) => widget.onRespondScheduled!(s, status)
                            : null,
                      )),
                  ...dayWorked.map((s) => _EventRow(
                        color: _colWorked,
                        time: '${_fmtTime(s.clockedInAt)} – ${s.clockedOutAt != null ? _fmtTime(s.clockedOutAt!) : 'active'}',
                        title: s.employeeName?.split(' ').first ??
                            (widget.isOwner ? 'Employee' : 'Worked'),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Event row widgets ────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.color,
    required this.time,
    required this.title,
    this.subtitle,
  });

  final Color color;
  final String time;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(title, style: AppTextStyles.bodySmall),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledEventRow extends StatelessWidget {
  const _ScheduledEventRow({
    required this.shift,
    required this.isOwner,
    this.onRespond,
  });

  final ScheduledShift shift;
  final bool isOwner;
  final void Function(String status)? onRespond;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (shift.status) {
      'accepted' => AppColors.openGreen,
      'declined' => AppColors.closedRed,
      _          => _colScheduled,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: _colScheduled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmtTime(shift.scheduledStart)} – ${_fmtTime(shift.scheduledEnd)}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (isOwner && shift.employeeName != null)
                  Text(shift.employeeName!.split(' ').first,
                      style: AppTextStyles.bodySmall),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shift.status[0].toUpperCase() + shift.status.substring(1),
                    style: AppTextStyles.caption.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isOwner && shift.isPending && onRespond != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => onRespond!('declined'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.closedRed,
                          side: const BorderSide(color: AppColors.closedRed),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Decline', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => onRespond!('accepted'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.openGreen,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Accept', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
