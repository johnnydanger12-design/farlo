import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../employees/providers/shifts_provider.dart';
import '../../employees/widgets/shift_week_card.dart';

class DashboardCalendarSection extends ConsumerStatefulWidget {
  const DashboardCalendarSection({super.key, required this.truckId, required this.truckName});
  final String truckId;
  final String truckName;

  @override
  ConsumerState<DashboardCalendarSection> createState() =>
      _DashboardCalendarSectionState();
}

class _DashboardCalendarSectionState
    extends ConsumerState<DashboardCalendarSection> {
  RealtimeChannel? _workedChannel;
  RealtimeChannel? _scheduledChannel;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _workedChannel = Supabase.instance.client
        .channel('owner-worked-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'employee_shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) => ref.invalidate(
              truckShiftsProvider((widget.truckId, now.year, now.month))),
        )
        .subscribe();

    _scheduledChannel = Supabase.instance.client
        .channel('owner-scheduled-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'scheduled_shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) {
            // Invalidate current month AND next month so shifts assigned near
            // month-end refresh immediately wherever the calendar is viewing.
            ref.invalidate(truckScheduledShiftsProvider(
                (widget.truckId, now.year, now.month)));
            final next = DateTime(now.year, now.month + 1);
            ref.invalidate(truckScheduledShiftsProvider(
                (widget.truckId, next.year, next.month)));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_workedChannel != null) {
      Supabase.instance.client.removeChannel(_workedChannel!);
    }
    if (_scheduledChannel != null) {
      Supabase.instance.client.removeChannel(_scheduledChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShiftWeekCard(truckId: widget.truckId, truckName: widget.truckName, isOwner: true);
  }
}
