import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/push_notification_service.dart';
import '../../bookings/models/booking_request.dart';
import '../../bookings/providers/bookings_provider.dart';
import '../models/employee_shift.dart';
import '../models/scheduled_shift.dart';
import '../models/planned_location.dart';
import '../providers/employees_provider.dart';
import '../providers/planned_locations_provider.dart';
import '../providers/shifts_provider.dart';
import '../widgets/add_event_sheet.dart';
import '../../bookings/widgets/book_truck_sheet.dart';
import '../widgets/announce_week_sheet.dart';
import '../widgets/assign_shift_sheet.dart';
import '../widgets/plan_location_sheet.dart';

enum _CalendarView { list, chips, timeline }

const _colBooking   = AppColors.primary;
const _colScheduled = Color(0xFF6366F1);
const _colWorked    = Color(0xFF6B7280);
const _colLocation  = Color(0xFF0D9488); // teal

const _weekdayHeaders = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _monthNames     = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtTime(DateTime dt) {
  final h    = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final m    = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour < 12 ? 'am' : 'pm';
  return '$h:$m $ampm';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({
    super.key,
    required this.truckId,
    required this.truckName,
    required this.isOwner,
    required this.initialDate,
    this.onRespondScheduled,
  });

  final String truckId;
  final String truckName;
  final bool isOwner;
  final DateTime initialDate;
  final void Function(ScheduledShift, String)? onRespondScheduled;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late int _year;
  late int _month;
  late DateTime _selectedDate;
  _CalendarView _view = _CalendarView.list;
  bool _inDayView = false; // true when drilled into a specific day from month grid

  static const _prefKey = 'calendar_view';

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _year  = widget.initialDate.year;
    _month = widget.initialDate.month;
    _loadViewPref();
  }

  Future<void> _loadViewPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (!mounted || saved == null) return;
    setState(() {
      _view = switch (saved) {
        'chips'    => _CalendarView.chips,
        'timeline' => _CalendarView.timeline,
        _          => _CalendarView.list,
      };
    });
  }

  Future<void> _saveViewPref(_CalendarView view) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, view.name);
  }

  void _prevMonth() => setState(() {
        if (_month == 1) { _month = 12; _year--; }
        else { _month--; }
      });

  void _nextMonth() => setState(() {
        if (_month == 12) { _month = 1; _year++; }
        else { _month++; }
      });

  Future<void> _showAddEvent(DateTime date) async {
    final type = await showModalBottomSheet<AddEventType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(isOwner: widget.isOwner),
    );
    if (type == null || !mounted) return;

    switch (type) {
      case AddEventType.shift:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AssignShiftSheet(truckId: widget.truckId, initialDate: date),
        );
        if (!mounted) return;
        ref.invalidate(truckScheduledShiftsProvider((widget.truckId, _year, _month)));
      case AddEventType.location:
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PlanLocationSheet(truckId: widget.truckId, initialDate: date),
        );
        if (!mounted) return;
        ref.invalidate(truckPlannedLocationsProvider((widget.truckId, _year, _month)));
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
        if (!mounted) return;
        ref.invalidate(acceptedBookingsForMonthProvider((widget.truckId, _year, _month)));
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


  Future<void> _confirmDeleteScheduled(ScheduledShift shift) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? Colors.white : null,
        title: const Text('Delete Shift?', textAlign: TextAlign.center),
        content: const Text(
          'This will remove the scheduled shift and notify the employee.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(employeesRepositoryProvider).deleteScheduledShift(shift.id);
      ref.invalidate(truckScheduledShiftsProvider((widget.truckId, _year, _month)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete shift: $e')));
      }
    }
  }

  void _showEditWorkedDialog(EmployeeShift shift) {
    showDialog<void>(
      context: context,
      builder: (_) => EditWorkedShiftDialog(shift: shift, truckId: widget.truckId),
    ).then((_) =>
        ref.invalidate(truckShiftsProvider((widget.truckId, _year, _month))));
  }

  Future<void> _handleRespond(ScheduledShift shift, String status) async {
    try {
      await ref
          .read(employeesRepositoryProvider)
          .respondToScheduledShift(shiftId: shift.id, status: status);
      await PushNotificationService.sendShiftResponse(shift.id);
      ref.invalidate(myScheduledShiftsProvider(
          (widget.truckId, shift.scheduledStart.year, shift.scheduledStart.month)));
      widget.onRespondScheduled?.call(shift, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update shift: $e')));
      }
    }
  }

  // ── Day view (Apple Calendar day style) ────────────────────────────────────
  Widget _buildDayView(
    BuildContext context,
    List<BookingRequest> dayBookings,
    List<ScheduledShift> dayScheduled,
    List<EmployeeShift> dayWorked,
    List<PlannedLocation> dayLocations,
    DateTime todayD,
  ) {
    const weekdayShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const weekdayFull  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months       = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    final monday    = DateTime(_selectedDate.year, _selectedDate.month,
        _selectedDate.day - (_selectedDate.weekday - 1));
    final weekDates = List.generate(7, (i) => monday.add(Duration(days: i)));
    final dayLabel  = '${weekdayFull[_selectedDate.weekday - 1]}, '
        '${months[_selectedDate.month - 1]} ${_selectedDate.day}';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to month view',
          onPressed: () => setState(() => _inDayView = false),
        ),
        title: Text(dayLabel),
        actions: [
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add shift or event',
              onPressed: () => _showAddEvent(_selectedDate),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Week strip ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: List.generate(7, (i) {
                final date       = weekDates[i];
                final isSelected = _sameDay(date, _selectedDate);
                final isDayToday = _sameDay(date, todayD);
                final isWeekend  = i >= 5;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedDate = date;
                      _year  = date.year;
                      _month = date.month;
                    }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          weekdayShort[i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isWeekend ? AppColors.textHint : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : isDayToday
                                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                                    : Colors.transparent,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected || isDayToday ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected
                                  ? Colors.white
                                  : isDayToday
                                      ? Theme.of(context).colorScheme.primary
                                      : isWeekend ? AppColors.textHint : null,
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
          // ── Timeline ──────────────────────────────────────────────────────
          Expanded(
            child: _TimelineView(
              bookings: dayBookings,
              scheduled: dayScheduled,
              worked: dayWorked,
              locations: dayLocations,
              isOwner: widget.isOwner,
              onDeleteScheduled: _confirmDeleteScheduled,
              onEditWorked: _showEditWorkedDialog,
              onRespondScheduled: !widget.isOwner ? _handleRespond : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today  = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);
    final key    = (widget.truckId, _year, _month);

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

    bool hasBooking(int day) {
      final d = DateTime(_year, _month, day);
      return bookings.any((b) => _sameDay(b.eventDate, d));
    }
    bool hasScheduled(int day) {
      final d = DateTime(_year, _month, day);
      return scheduled.any((s) => _sameDay(s.scheduledStart, d));
    }
    bool hasWorked(int day) {
      final d = DateTime(_year, _month, day);
      return worked.any((s) => _sameDay(s.clockedInAt, d));
    }
    bool hasLocation(int day) {
      final d = DateTime(_year, _month, day);
      return locations.any((l) => _sameDay(l.eventDate, d));
    }

    final dayWorked    = worked.where((s) => _sameDay(s.clockedInAt, _selectedDate)).toList();
    final dayScheduled = scheduled.where((s) => _sameDay(s.scheduledStart, _selectedDate)).toList();
    final dayBookings  = bookings.where((b) => _sameDay(b.eventDate, _selectedDate)).toList();
    final dayLocations = locations.where((l) => _sameDay(l.eventDate, _selectedDate)).toList();

    final daysInMonth   = DateUtils.getDaysInMonth(_year, _month);
    // Monday-first offset: DateTime.weekday is 1=Mon…7=Sun
    final firstOffset   = (DateTime(_year, _month, 1).weekday - 1) % 7;
    final totalCells    = firstOffset + daysInMonth;

    // Day view: triggered by tapping a day in chips/month view only.
    if (_view == _CalendarView.chips && _inDayView) {
      return _buildDayView(context, dayBookings, dayScheduled, dayWorked, dayLocations, todayD);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          PopupMenuButton<_CalendarView>(
            icon: const Icon(Icons.view_module_outlined),
            tooltip: 'Change view',
            onSelected: (v) {
              setState(() => _view = v);
              _saveViewPref(v);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _CalendarView.list,
                child: Row(children: [
                  Icon(Icons.view_list_outlined,
                      size: 20,
                      color: _view == _CalendarView.list
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  const SizedBox(width: 10),
                  Text('List',
                      style: TextStyle(
                          fontWeight: _view == _CalendarView.list
                              ? FontWeight.w700
                              : FontWeight.normal)),
                ]),
              ),
              PopupMenuItem(
                value: _CalendarView.chips,
                child: Row(children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 20,
                      color: _view == _CalendarView.chips
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  const SizedBox(width: 10),
                  Text('Month',
                      style: TextStyle(
                          fontWeight: _view == _CalendarView.chips
                              ? FontWeight.w700
                              : FontWeight.normal)),
                ]),
              ),
              PopupMenuItem(
                value: _CalendarView.timeline,
                child: Row(children: [
                  Icon(Icons.view_day_outlined,
                      size: 20,
                      color: _view == _CalendarView.timeline
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  const SizedBox(width: 10),
                  Text('Timeline',
                      style: TextStyle(
                          fontWeight: _view == _CalendarView.timeline
                              ? FontWeight.w700
                              : FontWeight.normal)),
                ]),
              ),
            ],
          ),
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add shift or event',
              onPressed: () => _showAddEvent(_selectedDate),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Month header ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${_monthNames[_month - 1]} $_year',
                    style: AppTextStyles.heading3,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous month',
                    onPressed: _prevMonth,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next month',
                    onPressed: _nextMonth,
                  ),
                ],
              ),
            ),
          ),

          // ── Weekday labels ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: _weekdayHeaders.map((l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (l == 'SAT' || l == 'SUN')
                            ? AppColors.textHint
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 4)),

          // ── Month grid ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: _view == _CalendarView.chips ? 80.0 : 52.0,
              ),
              itemCount: totalCells,
              itemBuilder: (context, index) {
                if (index < firstOffset) return const SizedBox.shrink();
                final day        = index - firstOffset + 1;
                final date       = DateTime(_year, _month, day);
                final isToday    = _sameDay(date, todayD);
                final isSelected = _sameDay(date, _selectedDate);
                final isWeekend  = date.weekday >= 6;

                final bk = hasBooking(day);
                final sc = hasScheduled(day);
                final wk = hasWorked(day);
                final lc = hasLocation(day);

                // Build chip labels for the chips view
                final chipEvents = <(String, Color)>[];
                if (_view == _CalendarView.chips) {
                  if (lc) {
                    final l = locations.firstWhere((x) => _sameDay(x.eventDate, date));
                    chipEvents.add((l.title, _colLocation));
                  }
                  if (bk) {
                    final b = bookings.firstWhere((x) => _sameDay(x.eventDate, date));
                    chipEvents.add((b.contactName, _colBooking));
                  }
                  if (sc) {
                    final s = scheduled.firstWhere((x) => _sameDay(x.scheduledStart, date));
                    chipEvents.add((s.employeeName?.split(' ').first ?? 'Shift', _colScheduled));
                  }
                  if (wk) {
                    final w = worked.firstWhere((x) => _sameDay(x.clockedInAt, date));
                    chipEvents.add((w.employeeName?.split(' ').first ?? 'Worked', _colWorked));
                  }
                }

                // Total event count for "+N" overflow
                final totalEvents = locations.where((x) => _sameDay(x.eventDate, date)).length
                    + (bk ? bookings.where((x) => _sameDay(x.eventDate, date)).length : 0)
                    + scheduled.where((x) => _sameDay(x.scheduledStart, date)).length
                    + worked.where((x) => _sameDay(x.clockedInAt, date)).length;

                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDate = date;
                    if (_view == _CalendarView.chips) _inDayView = true;
                  }),
                  child: _view == _CalendarView.chips
                      ? _ChipDayCell(
                          day: day,
                          isToday: isToday,
                          isSelected: isSelected,
                          isWeekend: isWeekend,
                          chips: chipEvents,
                          overflowCount: totalEvents > chipEvents.length
                              ? totalEvents - chipEvents.length
                              : 0,
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : isToday
                                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                                        : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? Colors.white
                                      : isToday
                                          ? Theme.of(context).colorScheme.primary
                                          : isWeekend
                                              ? AppColors.textHint
                                              : null,
                                ),
                              ),
                            ),
                            if (lc || bk || sc || wk) ...[
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (lc) _Dot(_colLocation),
                                  if (bk) _Dot(_colBooking),
                                  if (sc) _Dot(_colScheduled),
                                  if (wk) _Dot(_colWorked),
                                ],
                              ),
                            ],
                          ],
                        ),
                );
              },
            ),
          ),

          // ── Event area — shown for list and timeline views ──────────────────
          // Chips view drills into the day view on tap instead.
          if (_view != _CalendarView.chips) ...[
            const SliverToBoxAdapter(child: Divider(height: 1)),
            SliverFillRemaining(
              hasScrollBody: true,
              child: _view == _CalendarView.timeline
                  ? Column(
                      children: [
                        _DayHeader(
                          date: _selectedDate,
                          isOwner: widget.isOwner,
                          onAssign: () => _showAddEvent(_selectedDate),
                        ),
                        Expanded(
                          child: _TimelineView(
                            bookings: dayBookings,
                            scheduled: dayScheduled,
                            worked: dayWorked,
                            locations: dayLocations,
                            isOwner: widget.isOwner,
                            onDeleteScheduled: _confirmDeleteScheduled,
                            onEditWorked: _showEditWorkedDialog,
                            onRespondScheduled: !widget.isOwner ? _handleRespond : null,
                          ),
                        ),
                      ],
                    )
                  : (dayBookings.isEmpty && dayScheduled.isEmpty && dayWorked.isEmpty && dayLocations.isEmpty
                      ? Column(
                          children: [
                            _DayHeader(
                              date: _selectedDate,
                              isOwner: widget.isOwner,
                              onAssign: () => _showAddEvent(_selectedDate),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'No events',
                                  style: AppTextStyles.body.copyWith(color: AppColors.textHint),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _DayHeader(
                              date: _selectedDate,
                              isOwner: widget.isOwner,
                              onAssign: () => _showAddEvent(_selectedDate),
                            ),
                            if (dayLocations.isNotEmpty) ...[
                              _SectionLabel('Planned Locations', _colLocation),
                              ...dayLocations.map((l) => _EventTile(
                                    color: _colLocation,
                                    time: l.address ?? 'No address',
                                    title: l.title,
                                    subtitle: l.notes,
                                  )),
                            ],
                            if (dayBookings.isNotEmpty) ...[
                              _SectionLabel('Bookings', _colBooking),
                              ...dayBookings.map((b) => _EventTile(
                                    color: _colBooking,
                                    time: b.eventTime,
                                    title: b.contactName,
                                    subtitle: b.eventType,
                                  )),
                            ],
                            if (dayScheduled.isNotEmpty) ...[
                              _SectionLabel('Scheduled Shifts', _colScheduled),
                              ...dayScheduled.map((s) => _ScheduledTile(
                                    shift: s,
                                    isOwner: widget.isOwner,
                                    onDelete: widget.isOwner ? () => _confirmDeleteScheduled(s) : null,
                                    onRespond: !widget.isOwner ? (st) => _handleRespond(s, st) : null,
                                  )),
                            ],
                            if (dayWorked.isNotEmpty) ...[
                              _SectionLabel('Worked Shifts', _colWorked),
                              ...dayWorked.map((s) => _WorkedTile(
                                    shift: s,
                                    isOwner: widget.isOwner,
                                    onEdit: widget.isOwner ? () => _showEditWorkedDialog(s) : null,
                                  )),
                            ],
                          ],
                        )),
            ),
          ],
        ],
      ),
    );
  }

}

// ─── Small reusable widgets ───────────────────────────────────────────────────

// ─── Timeline view ────────────────────────────────────────────────────────────

const _hourHeight  = 60.0;
const _startHour   = 0;   // 12 AM
const _endHour     = 24;  // 12 AM (next day)
const _timeColW    = 52.0;

TimeOfDay? _parseTimeString(String s) {
  final re = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?$');
  final m  = re.firstMatch(s.trim());
  if (m == null) return null;
  int h   = int.parse(m.group(1)!);
  int min = int.parse(m.group(2)!);
  final ampm = m.group(3)?.toLowerCase();
  if (ampm == 'pm' && h != 12) h += 12;
  if (ampm == 'am' && h == 12) h = 0;
  return TimeOfDay(hour: h, minute: min);
}

double _topFor(int hour, int minute) =>
    ((hour + minute / 60.0) - _startHour) * _hourHeight;

class _TimelineView extends StatelessWidget {
  const _TimelineView({
    required this.bookings,
    required this.scheduled,
    required this.worked,
    required this.locations,
    required this.isOwner,
    this.onDeleteScheduled,
    this.onEditWorked,
    this.onRespondScheduled,
  });

  final List<BookingRequest>  bookings;
  final List<ScheduledShift>  scheduled;
  final List<EmployeeShift>   worked;
  final List<PlannedLocation> locations;
  final bool isOwner;
  final void Function(ScheduledShift)? onDeleteScheduled;
  final void Function(EmployeeShift)?  onEditWorked;
  final void Function(ScheduledShift, String)? onRespondScheduled;

  @override
  Widget build(BuildContext context) {
    final totalH = (_endHour - _startHour) * _hourHeight;
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.5);
    final labelStyle   = AppTextStyles.caption.copyWith(color: AppColors.textHint);

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
                    color: _colLocation.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: _colLocation, width: 3)),
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
          color: _colBooking,
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
        color: _colScheduled,
        title: s.employeeName?.split(' ').first ?? 'Shift',
        subtitle: '${_fmtTime(s.scheduledStart)} – ${_fmtTime(s.scheduledEnd)}',
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
        color: _colWorked,
        title: w.employeeName?.split(' ').first ?? 'Worked',
        subtitle: w.isActive
            ? '${_fmtTime(w.clockedInAt)} – active'
            : '${_fmtTime(w.clockedInAt)} – ${_fmtTime(w.clockedOutAt!)}',
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

// ─── Selected day header ──────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.isOwner, required this.onAssign});
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

// ─── Chips day cell (month view) ─────────────────────────────────────────────

class _ChipDayCell extends StatelessWidget {
  const _ChipDayCell({
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

// ─── Small shared widgets ─────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 5, height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.color);
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

class _EventTile extends StatelessWidget {
  const _EventTile({required this.color, required this.time, required this.title, this.subtitle});
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

class _ScheduledTile extends StatelessWidget {
  const _ScheduledTile({required this.shift, required this.isOwner, this.onDelete, this.onRespond});
  final ScheduledShift shift;
  final bool isOwner;
  final VoidCallback? onDelete;
  final void Function(String)? onRespond;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (shift.status) {
      'accepted' => AppColors.openGreen,
      'declined' => AppColors.closedRed,
      _          => _colScheduled,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3, height: 44,
            decoration: BoxDecoration(color: _colScheduled, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmtTime(shift.scheduledStart)} – ${_fmtTime(shift.scheduledEnd)}',
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

class _WorkedTile extends StatelessWidget {
  const _WorkedTile({required this.shift, required this.isOwner, this.onEdit});
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
            decoration: BoxDecoration(color: _colWorked, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.isActive
                      ? '${_fmtTime(shift.clockedInAt)} – active'
                      : '${_fmtTime(shift.clockedInAt)} – ${_fmtTime(shift.clockedOutAt!)}',
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
