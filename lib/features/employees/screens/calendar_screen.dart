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
import '../widgets/calendar/calendar_shared.dart';
import '../widgets/calendar/day_view_tiles.dart';
import '../widgets/calendar/month_view_widgets.dart';
import '../widgets/calendar/timeline_view.dart';

enum _CalendarView { list, chips, timeline }

const _weekdayHeaders = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _monthNames     = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
            child: TimelineView(
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
                    chipEvents.add((l.title, colLocation));
                  }
                  if (bk) {
                    final b = bookings.firstWhere((x) => _sameDay(x.eventDate, date));
                    chipEvents.add((b.contactName, colBooking));
                  }
                  if (sc) {
                    final s = scheduled.firstWhere((x) => _sameDay(x.scheduledStart, date));
                    chipEvents.add((s.employeeName?.split(' ').first ?? 'Shift', colScheduled));
                  }
                  if (wk) {
                    final w = worked.firstWhere((x) => _sameDay(x.clockedInAt, date));
                    chipEvents.add((w.employeeName?.split(' ').first ?? 'Worked', colWorked));
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
                      ? ChipDayCell(
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
                                  if (lc) Dot(colLocation),
                                  if (bk) Dot(colBooking),
                                  if (sc) Dot(colScheduled),
                                  if (wk) Dot(colWorked),
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
                        DayHeader(
                          date: _selectedDate,
                          isOwner: widget.isOwner,
                          onAssign: () => _showAddEvent(_selectedDate),
                        ),
                        Expanded(
                          child: TimelineView(
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
                            DayHeader(
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
                            DayHeader(
                              date: _selectedDate,
                              isOwner: widget.isOwner,
                              onAssign: () => _showAddEvent(_selectedDate),
                            ),
                            if (dayLocations.isNotEmpty) ...[
                              SectionLabel('Planned Locations', colLocation),
                              ...dayLocations.map((l) => EventTile(
                                    color: colLocation,
                                    time: l.address ?? 'No address',
                                    title: l.title,
                                    subtitle: l.notes,
                                  )),
                            ],
                            if (dayBookings.isNotEmpty) ...[
                              SectionLabel('Bookings', colBooking),
                              ...dayBookings.map((b) => EventTile(
                                    color: colBooking,
                                    time: b.eventTime,
                                    title: b.contactName,
                                    subtitle: b.eventType,
                                  )),
                            ],
                            if (dayScheduled.isNotEmpty) ...[
                              SectionLabel('Scheduled Shifts', colScheduled),
                              ...dayScheduled.map((s) => ScheduledTile(
                                    shift: s,
                                    isOwner: widget.isOwner,
                                    onDelete: widget.isOwner ? () => _confirmDeleteScheduled(s) : null,
                                    onRespond: !widget.isOwner ? (st) => _handleRespond(s, st) : null,
                                  )),
                            ],
                            if (dayWorked.isNotEmpty) ...[
                              SectionLabel('Worked Shifts', colWorked),
                              ...dayWorked.map((s) => WorkedTile(
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

