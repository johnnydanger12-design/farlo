import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../bookings/models/booking_request.dart';
import '../models/employee_shift.dart';
import '../models/scheduled_shift.dart';

// Dot colors
const _dotBooking = AppColors.primary;
const _dotScheduled = Color(0xFF6366F1); // indigo
const _dotWorked = Color(0xFF6B7280); // grey

const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// ─── Public widget ─────────────────────────────────────────────────────────────
//
// isOwner = true  → shows employee names on shift rows, shows booking rows,
//                   exposes onEditWorkedShift + onAssignShift + onDeleteScheduled
// isOwner = false → employee view; exposes onRespondScheduled

class ShiftCalendarWidget extends StatefulWidget {
  const ShiftCalendarWidget({
    super.key,
    required this.truckId,
    required this.isOwner,
    this.workedShifts = const [],
    this.scheduledShifts = const [],
    this.bookings = const [],
    this.onMonthChanged,
    // Owner callbacks
    this.onEditWorkedShift,
    this.onAssignShift,
    this.onDeleteScheduled,
    this.onBookingTap,
    // Employee callbacks
    this.onRespondScheduled,
  });

  final String truckId;
  final bool isOwner;
  final List<EmployeeShift> workedShifts;
  final List<ScheduledShift> scheduledShifts;
  final List<BookingRequest> bookings;
  final void Function(int year, int month)? onMonthChanged;

  // Owner
  final void Function(EmployeeShift)? onEditWorkedShift;
  final void Function(DateTime date)? onAssignShift;
  final void Function(ScheduledShift)? onDeleteScheduled;
  final void Function(BookingRequest)? onBookingTap;

  // Employee
  final void Function(ScheduledShift shift, String status)? onRespondScheduled;

  @override
  State<ShiftCalendarWidget> createState() => _ShiftCalendarWidgetState();
}

class _ShiftCalendarWidgetState extends State<ShiftCalendarWidget> {
  late int _year;
  late int _month;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
      _selectedDay = null;
    });
    widget.onMonthChanged?.call(_year, _month);
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
      _selectedDay = null;
    });
    widget.onMonthChanged?.call(_year, _month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<BookingRequest> _bookingsOnDay(int day) {
    final d = DateTime(_year, _month, day);
    return widget.bookings
        .where((b) => b.status == 'accepted' && _sameDay(b.eventDate, d))
        .toList();
  }

  List<ScheduledShift> _scheduledOnDay(int day) {
    final d = DateTime(_year, _month, day);
    return widget.scheduledShifts
        .where((s) => _sameDay(s.scheduledStart, d))
        .toList();
  }

  List<EmployeeShift> _workedOnDay(int day) {
    final d = DateTime(_year, _month, day);
    return widget.workedShifts
        .where((s) => _sameDay(s.clockedInAt, d))
        .toList();
  }

  bool _hasAny(int day) =>
      _bookingsOnDay(day).isNotEmpty ||
      _scheduledOnDay(day).isNotEmpty ||
      _workedOnDay(day).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_year, _month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateUtils.getDaysInMonth(_year, _month);
    final today = DateTime.now();

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
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(
              children: [
                Text(
                  '${_monthNames[_month - 1]} $_year',
                  style: AppTextStyles.label,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _prevMonth,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _nextMonth,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // ── Weekday labels ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            child: Row(
              children: _weekdayLabels
                  .map(
                    (l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // ── Day grid ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.85,
              ),
              itemCount: firstWeekday + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstWeekday) return const SizedBox.shrink();
                final day = index - firstWeekday + 1;
                final isToday = today.year == _year &&
                    today.month == _month &&
                    today.day == day;
                final isSelected = _selectedDay == day;
                final hasData = _hasAny(day);

                final bookingsHere = _bookingsOnDay(day);
                final scheduledHere = _scheduledOnDay(day);
                final workedHere = _workedOnDay(day);

                return GestureDetector(
                  onTap: () => setState(
                    () => _selectedDay = isSelected ? null : day,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : isToday
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$day',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: isToday || isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : isToday
                                    ? AppColors.primary
                                    : null,
                          ),
                        ),
                      ),
                      if (hasData) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (bookingsHere.isNotEmpty)
                              _Dot(color: _dotBooking),
                            if (scheduledHere.isNotEmpty)
                              _Dot(color: _dotScheduled),
                            if (workedHere.isNotEmpty)
                              _Dot(color: _dotWorked),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Expanded day detail ──
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _selectedDay != null
                ? _DayDetail(
                    day: _selectedDay!,
                    year: _year,
                    month: _month,
                    isOwner: widget.isOwner,
                    bookings: _bookingsOnDay(_selectedDay!),
                    scheduledShifts: _scheduledOnDay(_selectedDay!),
                    workedShifts: _workedOnDay(_selectedDay!),
                    onEditWorkedShift: widget.onEditWorkedShift,
                    onAssignShift: widget.onAssignShift,
                    onDeleteScheduled: widget.onDeleteScheduled,
                    onBookingTap: widget.onBookingTap,
                    onRespondScheduled: widget.onRespondScheduled,
                  )
                : const SizedBox(width: double.infinity),
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Legend ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                if (widget.isOwner) ...[
                  _LegendDot(color: _dotBooking, label: 'Booking'),
                  const SizedBox(width: AppSpacing.md),
                ],
                _LegendDot(color: _dotScheduled, label: 'Scheduled'),
                const SizedBox(width: AppSpacing.md),
                _LegendDot(color: _dotWorked, label: 'Worked'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Day detail panel ─────────────────────────────────────────────────────────

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.year,
    required this.month,
    required this.isOwner,
    required this.bookings,
    required this.scheduledShifts,
    required this.workedShifts,
    this.onEditWorkedShift,
    this.onAssignShift,
    this.onDeleteScheduled,
    this.onBookingTap,
    this.onRespondScheduled,
  });

  final int day;
  final int year;
  final int month;
  final bool isOwner;
  final List<BookingRequest> bookings;
  final List<ScheduledShift> scheduledShifts;
  final List<EmployeeShift> workedShifts;
  final void Function(EmployeeShift)? onEditWorkedShift;
  final void Function(DateTime)? onAssignShift;
  final void Function(ScheduledShift)? onDeleteScheduled;
  final void Function(BookingRequest)? onBookingTap;
  final void Function(ScheduledShift, String)? onRespondScheduled;

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        bookings.isEmpty && scheduledShifts.isEmpty && workedShifts.isEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _fmtDay(DateTime(year, month, day)),
                style: AppTextStyles.label,
              ),
              const Spacer(),
              if (isOwner)
                TextButton.icon(
                  onPressed: () =>
                      onAssignShift?.call(DateTime(year, month, day)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Assign Shift'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('No events',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textHint)),
            ),

          // Bookings
          if (bookings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _GroupHeader('Bookings', _dotBooking),
            ...bookings.map(
              (b) => _BookingRow(
                booking: b,
                onTap: () => onBookingTap?.call(b),
              ),
            ),
          ],

          // Scheduled shifts
          if (scheduledShifts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _GroupHeader('Scheduled', _dotScheduled),
            ...scheduledShifts.map(
              (s) => _ScheduledRow(
                shift: s,
                isOwner: isOwner,
                onDelete: () => onDeleteScheduled?.call(s),
                onRespond: (status) => onRespondScheduled?.call(s, status),
              ),
            ),
          ],

          // Worked shifts
          if (workedShifts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _GroupHeader('Worked', _dotWorked),
            ...workedShifts.map(
              (s) => _WorkedRow(
                shift: s,
                isOwner: isOwner,
                onEdit: () => onEditWorkedShift?.call(s),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDay(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

// ─── Row widgets ──────────────────────────────────────────────────────────────

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking, required this.onTap});
  final BookingRequest booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: _dotBooking,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.contactName, style: AppTextStyles.bodySmall),
                  Text(
                    '${booking.eventTime}${booking.duration != null ? '  ·  ${booking.duration}' : ''}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({
    required this.shift,
    required this.isOwner,
    required this.onDelete,
    required this.onRespond,
  });
  final ScheduledShift shift;
  final bool isOwner;
  final VoidCallback onDelete;
  final void Function(String status) onRespond;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (shift.status) {
      'accepted' => AppColors.openGreen,
      'declined' => AppColors.closedRed,
      _ => _dotScheduled,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: _dotScheduled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOwner && shift.employeeName != null)
                  Text(shift.employeeName!.split(' ').first,
                      style: AppTextStyles.bodySmall),
                Text(
                  '${_fmtTime(shift.scheduledStart)} – ${_fmtTime(shift.scheduledEnd)}',
                  style: AppTextStyles.caption,
                ),
                if (shift.notes?.isNotEmpty ?? false)
                  Text(shift.notes!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
                // Status badge
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shift.status[0].toUpperCase() + shift.status.substring(1),
                    style: AppTextStyles.caption.copyWith(
                        color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                // Employee: accept / decline buttons when pending
                if (!isOwner && shift.isPending) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => onRespond('declined'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.closedRed,
                          side: const BorderSide(color: AppColors.closedRed),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Decline',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: () => onRespond('accepted'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.openGreen,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Accept',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppColors.textHint,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'am' : 'pm';
    return '$h:$m$ampm';
  }
}

class _WorkedRow extends StatelessWidget {
  const _WorkedRow({
    required this.shift,
    required this.isOwner,
    required this.onEdit,
  });
  final EmployeeShift shift;
  final bool isOwner;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final d = shift.elapsed;
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: _dotWorked,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOwner && shift.employeeName != null)
                  Text(shift.employeeName!.split(' ').first,
                      style: AppTextStyles.bodySmall),
                Text(
                  shift.isActive
                      ? '${_fmtTime(shift.clockedInAt)} – active'
                      : '${_fmtTime(shift.clockedInAt)} – ${_fmtTime(shift.clockedOutAt!)}',
                  style: AppTextStyles.caption,
                ),
                if (!shift.isActive)
                  Text(durationStr,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (isOwner && !shift.isActive)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.textHint,
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'am' : 'pm';
    return '$h:$m$ampm';
  }
}

// ─── Small shared pieces ──────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}
