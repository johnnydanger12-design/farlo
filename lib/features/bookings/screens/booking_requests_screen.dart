import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import '../screens/booking_chat_screen.dart';
import '../widgets/book_truck_sheet.dart';
import '../widgets/request_deposit_sheet.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../widgets/send_estimate_sheet.dart';
import '../widgets/send_invoice_sheet.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _fmtShort(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
String _fmtLong(DateTime d) => '${_weekdays[d.weekday - 1]}, ${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';

int _daysUntil(DateTime eventDate) {
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final day = DateTime(eventDate.year, eventDate.month, eventDate.day);
  return day.difference(today).inDays;
}

bool _isOver(BookingRequest r) {
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

String? _closedSublabel(BookingRequest r) {
  if (r.status == 'declined') return 'Declined';
  if (r.status == 'expired') return 'Expired — no response';
  if (r.status == 'cancelled') {
    return r.cancelledBy == 'consumer' ? 'Canceled by customer' : 'Canceled by you';
  }
  if (r.status == 'pending') return 'Expired';
  return null;
}

String _daysLabel(int days) {
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days > 1) return 'in $days days';
  if (days == -1) return '1 day ago';
  return '${days.abs()} days ago';
}

class BookingRequestsScreen extends ConsumerWidget {
  const BookingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    final truck = asyncTruck.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests', style: AppTextStyles.heading3),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: truck != null
          ? FloatingActionButton(
              tooltip: 'Add manual booking',
              onPressed: () {
                final topPadding = MediaQuery.of(context).viewPadding.top;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ManualBookingSheet(
                    truckId: truck.id,
                    truckName: truck.name,
                    topPadding: topPadding,
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) return const Center(child: Text('No truck found.'));
          return _BookingRequestsList(truckId: truck.id);
        },
      ),
    );
  }
}

class _BookingRequestsList extends ConsumerStatefulWidget {
  const _BookingRequestsList({required this.truckId});
  final String truckId;

  @override
  ConsumerState<_BookingRequestsList> createState() => _BookingRequestsListState();
}

class _BookingRequestsListState extends ConsumerState<_BookingRequestsList> with WidgetsBindingObserver {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(bookingsRepositoryProvider).expirePendingBookings(widget.truckId);
      ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        ref.read(notificationsRepositoryProvider).markBookingNotificationsRead(userId);
      }
    });
    _channel = Supabase.instance.client
        .channel('owner-bookings-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_booking_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) => ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId),
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncRequests = ref.watch(ownerBookingRequestsProvider);

    return asyncRequests.when(
      loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 48, color: AppColors.textHint),
                const SizedBox(height: AppSpacing.md),
                Text('No booking requests yet', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Requests from customers will appear here', style: AppTextStyles.caption),
              ],
            ),
          );
        }

        final pending = requests.where((r) => r.status == 'pending' && !_isOver(r)).toList();
        final upcoming = requests
            .where((r) => r.status == 'accepted' && !_isOver(r))
            .toList()
          ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
        final past = requests
            .where((r) => r.status == 'accepted' && _isOver(r))
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
        final closed = requests
            .where((r) =>
                r.status == 'declined' ||
                r.status == 'expired' ||
                r.status == 'cancelled' ||
                (r.status == 'pending' && _isOver(r)))
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

        return RefreshIndicator(
          onRefresh: () => ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            children: [
              if (pending.isNotEmpty) ...[
                _SectionHeader(title: 'Action Needed', count: pending.length, color: const Color(0xFFB45309)),
                const SizedBox(height: AppSpacing.sm),
                ...pending.map((r) => _PendingTile(request: r)),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (upcoming.isNotEmpty) ...[
                _SectionHeader(title: 'Upcoming', count: upcoming.length, color: AppColors.openGreen),
                const SizedBox(height: AppSpacing.sm),
                ...upcoming.map((r) => _UpcomingCard(request: r)),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (past.isNotEmpty)
                _CollapsibleSection(
                  key: const ValueKey('past'),
                  title: 'Past Events',
                  count: past.length,
                  children: past.map((r) => _CompactTile(request: r)).toList(),
                ),
              if (closed.isNotEmpty)
                _CollapsibleSection(
                  key: const ValueKey('closed'),
                  title: 'Declined / Canceled',
                  count: closed.length,
                  accentColor: AppColors.closedRed,
                  initiallyExpanded: true,
                  children: closed.map((r) => _CompactTile(request: r, sublabel: _closedSublabel(r))).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.color});
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppTextStyles.heading3),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ─── Message count badge ──────────────────────────────────────────────────────

class _MsgBadge extends StatelessWidget {
  const _MsgBadge({required this.count});
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

// ─── Pending tile ─────────────────────────────────────────────────────────────

class _PendingTile extends ConsumerWidget {
  const _PendingTile({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const amber = Color(0xFFB45309);
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;
    return GestureDetector(
      onTap: () async {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _RequestDetailSheet(request: request),
        );
        if (context.mounted) ref.invalidate(bookingMessageCountProvider((request.id, userId)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border(left: BorderSide(color: amber, width: 3)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.contactName, style: AppTextStyles.label),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtShort(request.eventDate)}  ·  ${request.eventTime}',
                      style: AppTextStyles.caption,
                    ),
                    Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (msgCount > 0) ...[
                _MsgBadge(count: msgCount),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Review', style: AppTextStyles.caption.copyWith(color: amber, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

}

// ─── Upcoming card ────────────────────────────────────────────────────────────

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const green = AppColors.openGreen;
    final days = _daysUntil(request.eventDate);
    final dayColor = days == 0 ? AppColors.closedRed : green;
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;

    return GestureDetector(
      onTap: () async {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _RequestDetailSheet(request: request),
        );
        if (context.mounted) ref.invalidate(bookingMessageCountProvider((request.id, userId)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border(left: BorderSide(color: green, width: 3)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date badge
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      _months[request.eventDate.month - 1].toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: green),
                    ),
                    Text(
                      '${request.eventDate.day}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: green, height: 1.1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.contactName, style: AppTextStyles.label),
                    const SizedBox(height: 1),
                    Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                      [request.eventTime, request.duration].nonNulls.join('  ·  '),
                      style: AppTextStyles.caption,
                    ),
                    Text(
                      request.eventLocation,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (msgCount > 0) _MsgBadge(count: msgCount) else const SizedBox.shrink(),
                        Text(
                          _daysLabel(days),
                          style: AppTextStyles.caption.copyWith(color: dayColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

}

// ─── Collapsible section (Past / Declined) ────────────────────────────────────

class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.accentColor,
    this.initiallyExpanded = false,
  });
  final String title;
  final int count;
  final List<Widget> children;
  final Color? accentColor;
  final bool initiallyExpanded;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text(widget.title, style: AppTextStyles.heading3),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          ...widget.children,
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

// ─── Compact tile (past / declined) ──────────────────────────────────────────

class _CompactTile extends StatelessWidget {
  const _CompactTile({required this.request, this.sublabel});
  final BookingRequest request;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RequestDetailSheet(request: request),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.contactName, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_fmtShort(request.eventDate), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                if (sublabel != null)
                  Text(sublabel!, style: AppTextStyles.caption.copyWith(color: AppColors.closedRed)),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'accepted' => ('Accepted', AppColors.openGreen.withValues(alpha: 0.12), AppColors.openGreen),
      'declined' => ('Declined', AppColors.closedRed.withValues(alpha: 0.12), AppColors.closedRed),
      'cancelled' => ('Canceled', AppColors.closedRed.withValues(alpha: 0.12), AppColors.closedRed),
      _ => ('Pending', AppColors.starGold.withValues(alpha: 0.18), const Color(0xFFB45309)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _RequestDetailSheet extends ConsumerStatefulWidget {
  const _RequestDetailSheet({required this.request});
  final BookingRequest request;

  @override
  ConsumerState<_RequestDetailSheet> createState() => _RequestDetailSheetState();
}

class _RequestDetailSheetState extends ConsumerState<_RequestDetailSheet> {
  bool _updating = false;

  Future<void> _updateStatus(String status, {String? cancellationReason}) async {
    setState(() => _updating = true);
    try {
      await ref.read(ownerBookingRequestsProvider.notifier).updateStatus(
        widget.request.id, status, cancellationReason: cancellationReason);
    } catch (e) {
      debugPrint('updateStatus failed: $e');
      if (mounted) setState(() => _updating = false);
      return;
    }

    bool addCalendar = false;
    if (status == 'accepted' && mounted) {
      final add = await showDialog<bool>(
        context: context,
        builder: (_) => _AddToCalendarDialog(request: widget.request),
      );
      addCalendar = add == true;
    }

    if (mounted) Navigator.of(context).pop();

    if (addCalendar) _addToCalendar(widget.request);
  }

  Future<void> _declinePending() async {
    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => _DeclineReasonDialog(contactName: widget.request.contactName),
    );
    if (result?.$1 == true) await _updateStatus('declined', cancellationReason: result?.$2);
  }

  Future<void> _cancelAccepted() async {
    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => _CancelMessageDialog(contactName: widget.request.contactName),
    );
    if (result?.$1 == true) await _updateStatus('cancelled', cancellationReason: result?.$2);
  }

  // Opens the native iOS/Android event editor pre-filled with booking details.
  // No permission request needed — the system handles it through its own UI.
  void _addToCalendar(BookingRequest request) {
    final start = _parseStart(request.eventDate, request.eventTime);
    final end = _parseEnd(start, request.duration);
    Add2Calendar.addEvent2Cal(
      Event(
        title: '${request.eventType} — ${request.contactName}',
        description: [
          'Contact: ${request.contactEmail}',
          if (request.contactPhone != null) 'Phone: ${request.contactPhone}',
          if (request.notes?.isNotEmpty ?? false) '\n${request.notes}',
        ].join('\n'),
        location: request.eventLocation,
        startDate: start,
        endDate: end,
        allDay: false,
      ),
    );
  }

  static DateTime _parseStart(DateTime date, String timeStr) {
    final parts = timeStr.trim().split(' ');
    final hm = parts[0].split(':');
    int hour = int.parse(hm[0]);
    final minute = int.parse(hm[1]);
    if (parts.length > 1) {
      if (parts[1].toUpperCase() == 'PM' && hour != 12) hour += 12;
      if (parts[1].toUpperCase() == 'AM' && hour == 12) hour = 0;
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static DateTime _parseEnd(DateTime start, String? duration) {
    if (duration == null) return start.add(const Duration(hours: 2));
    final hours = double.tryParse(duration.split(' ')[0]) ?? 2.0;
    return start.add(Duration(minutes: (hours * 60).round()));
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtLong(widget.request.eventDate);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Booking Request', style: AppTextStyles.heading3)),
                      _StatusBadge(status: widget.request.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DetailSection(
                    title: 'Requester',
                    rows: [
                      ('Name', widget.request.contactName),
                      ('Email', widget.request.contactEmail),
                      if (widget.request.contactPhone != null) ('Phone', widget.request.contactPhone!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DetailSection(
                    title: 'Event',
                    rows: [
                      ('Date', dateStr),
                      ('Time', widget.request.eventTime),
                      if (widget.request.duration != null) ('Duration', widget.request.duration!),
                      ('Type', widget.request.eventType),
                      ('Location', widget.request.eventLocation),
                      if (widget.request.guestCount != null) ('Guests', '${widget.request.guestCount}'),
                      if (widget.request.otherTrucksPresent == true)
                        ('Other trucks', widget.request.otherTrucksCount != null
                            ? 'Yes (${widget.request.otherTrucksCount})'
                            : 'Yes'),
                    ],
                  ),
                  if (widget.request.notes?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Notes', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(widget.request.notes!, style: AppTextStyles.bodySmall),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _MessagesRow(
                    bookingId: widget.request.id,
                    contactName: widget.request.contactName,
                    subtitle: '${widget.request.eventType}  ·  ${_fmtShort(widget.request.eventDate)}',
                    msgCount: ref.watch(bookingMessageCountProvider((
                      widget.request.id,
                      ref.watch(authProvider).asData?.value?.id ?? '',
                    ))).asData?.value ?? 0,
                    onChatReturned: () => ref.invalidate(bookingMessageCountProvider((
                      widget.request.id,
                      ref.read(authProvider).asData?.value?.id ?? '',
                    ))),
                  ),
                  if (widget.request.status == 'accepted') ...[
                    const SizedBox(height: AppSpacing.lg),
                    _OwnerFinancialSection(request: widget.request),
                  ],
                  if (widget.request.status == 'pending') ...[
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.closedRed,
                              side: const BorderSide(color: AppColors.closedRed),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _updating ? null : _declinePending,
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.openGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _updating ? null : () => _updateStatus('accepted'),
                            child: _updating
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.request.status == 'accepted' && !_isOver(widget.request)) ...[
                    const SizedBox(height: AppSpacing.xl),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.closedRed,
                        side: const BorderSide(color: AppColors.closedRed),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _updating ? null : _cancelAccepted,
                      child: _updating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.closedRed))
                          : const Text('Cancel Event'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Owner financial section ──────────────────────────────────────────────────

class _OwnerFinancialSection extends ConsumerStatefulWidget {
  const _OwnerFinancialSection({required this.request});
  final BookingRequest request;

  @override
  ConsumerState<_OwnerFinancialSection> createState() => _OwnerFinancialSectionState();
}

class _OwnerFinancialSectionState extends ConsumerState<_OwnerFinancialSection> {
  bool _generatingPdf = false;
  final _pdfButtonKey = GlobalKey();

  Future<void> _sharePdf() async {
    // Capture position and size before any await.
    final box = _pdfButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    final shareRect = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: Offset(screenSize.width / 2, screenSize.height * 0.75),
            width: 1,
            height: 1,
          );

    setState(() => _generatingPdf = true);
    try {
      final result = await ref.read(bookingsRepositoryProvider).generateInvoicePdf(widget.request.id);
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/${result.filename.replaceAll(' ', '_')}');
      await tmpFile.writeAsBytes(result.bytes);
      await Share.shareXFiles(
        [XFile(tmpFile.path, mimeType: 'application/pdf')],
        sharePositionOrigin: shareRect,
      );
    } catch (e) {
      if (mounted) {
        context.showError('Could not generate PDF: ${sanitizeErrorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _openEstimateSheet() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SendEstimateSheet(bookingId: widget.request.id),
    );
    ref.invalidate(bookingQuotesProvider(widget.request.id));
  }

  Future<void> _openDepositSheet() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => RequestDepositSheet(bookingId: widget.request.id),
    );
    ref.invalidate(bookingDepositProvider(widget.request.id));
  }

  Future<void> _openInvoiceSheet(BookingQuote? estimate, BookingDeposit? deposit) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SendInvoiceSheet(bookingId: widget.request.id, estimate: estimate, deposit: deposit),
    );
    ref.invalidate(bookingQuotesProvider(widget.request.id));
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(bookingQuotesProvider(widget.request.id));
    final depositAsync = ref.watch(bookingDepositProvider(widget.request.id));
    final quotes = quotesAsync.asData?.value ?? [];
    final deposit = depositAsync.asData?.value;

    final estimate = quotes.where((q) => q.type == QuoteType.estimate).lastOrNull;
    final invoice = quotes.where((q) => q.type == QuoteType.invoice).lastOrNull;
    final eventOver = _isOver(widget.request);
    final hasSomethingToShare = estimate != null || invoice != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Financials', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))),
            if (hasSomethingToShare)
              _generatingPdf
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      key: _pdfButtonKey,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      color: AppColors.textSecondary,
                      tooltip: 'Share invoice PDF',
                      onPressed: _sharePdf,
                    ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Estimate ────────────────────────────────────────────────────────
        if (estimate == null)
          OutlinedButton.icon(
            onPressed: _openEstimateSheet,
            icon: const Icon(Icons.request_quote_outlined, size: 16),
            label: const Text('Send Estimate'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          )
        else ...[
          _FinancialStatusRow(
            label: 'Estimate',
            amount: estimate.amount,
            status: switch (estimate.status) {
              QuoteStatus.sent => 'Awaiting response',
              QuoteStatus.accepted => 'Accepted',
              QuoteStatus.declined => 'Declined',
              QuoteStatus.paid => 'Paid',
            },
            color: switch (estimate.status) {
              QuoteStatus.accepted => AppColors.openGreen,
              QuoteStatus.declined => AppColors.closedRed,
              _ => AppColors.textSecondary,
            },
          ),
          if (estimate.status == QuoteStatus.declined) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _openEstimateSheet,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Resend Estimate'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ],

        // ── Deposit ─────────────────────────────────────────────────────────
        if (estimate?.status == QuoteStatus.accepted) ...[
          const SizedBox(height: AppSpacing.sm),
          if (deposit == null)
            OutlinedButton.icon(
              onPressed: _openDepositSheet,
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: const Text('Request Deposit'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            )
          else
            _FinancialStatusRow(
              label: 'Deposit',
              amount: deposit.amount,
              status: switch (deposit.status) {
                DepositStatus.requested => 'Awaiting payment',
                DepositStatus.paid => 'Paid',
                DepositStatus.refunded => 'Refunded',
              },
              color: deposit.status == DepositStatus.paid ? AppColors.openGreen : AppColors.textSecondary,
            ),
        ],

        // ── Invoice ─────────────────────────────────────────────────────────
        if (eventOver) ...[
          const SizedBox(height: AppSpacing.sm),
          if (invoice == null)
            OutlinedButton.icon(
              onPressed: () => _openInvoiceSheet(estimate, deposit),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Send Invoice'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            )
          else
            _FinancialStatusRow(
              label: 'Invoice',
              amount: invoice.amount,
              status: switch (invoice.status) {
                QuoteStatus.sent => 'Awaiting payment',
                QuoteStatus.paid => 'Paid',
                _ => '',
              },
              color: invoice.status == QuoteStatus.paid ? AppColors.openGreen : AppColors.textSecondary,
            ),
        ],
      ],
    );
  }
}

class _FinancialStatusRow extends StatelessWidget {
  const _FinancialStatusRow({required this.label, required this.amount, required this.status, required this.color});
  final String label;
  final double amount;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.label),
          ),
          Text('\$${amount.toStringAsFixed(2)}', style: AppTextStyles.label),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _AddToCalendarDialog extends StatelessWidget {
  const _AddToCalendarDialog({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      title: const Text('Add to Calendar?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${request.eventType} — ${request.contactName}',
              style: AppTextStyles.label),
          const SizedBox(height: 6),
          Text(_fmtLong(request.eventDate), style: AppTextStyles.bodySmall),
          Text(
            '${request.eventTime}${request.duration != null ? '  ·  ${request.duration}' : ''}',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(request.eventLocation,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add to Calendar'),
        ),
      ],
    );
  }
}

class _DeclineReasonDialog extends StatefulWidget {
  const _DeclineReasonDialog({required this.contactName});
  final String contactName;

  @override
  State<_DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<_DeclineReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      title: const Text('Decline Request?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.contactName} will be notified. You can add a short note to let them know why.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLines: 3,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. We\'re already booked for that date…',
              hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              counterStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (false, null)),
          child: const Text('Go Back'),
        ),
        TextButton(
          onPressed: () {
            final reason = _controller.text.trim();
            Navigator.pop(context, (true, reason.isEmpty ? null : reason));
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.closedRed),
          child: const Text('Decline'),
        ),
      ],
    );
  }
}

class _CancelMessageDialog extends StatefulWidget {
  const _CancelMessageDialog({required this.contactName});
  final String contactName;

  @override
  State<_CancelMessageDialog> createState() => _CancelMessageDialogState();
}

class _CancelMessageDialogState extends State<_CancelMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      title: const Text('Cancel Event?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.contactName} will be notified. Add a personal message so they know what happened.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLines: 3,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. We had an unexpected conflict come up for that day…',
              hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              counterStyle: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (false, null)),
          child: const Text('Keep It'),
        ),
        TextButton(
          onPressed: () {
            final reason = _controller.text.trim();
            Navigator.pop(context, (true, reason.isEmpty ? null : reason));
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.closedRed),
          child: const Text('Cancel Event'),
        ),
      ],
    );
  }
}

class _MessagesRow extends StatelessWidget {
  const _MessagesRow({
    required this.bookingId,
    required this.contactName,
    required this.subtitle,
    required this.msgCount,
    this.onChatReturned,
  });
  final String bookingId;
  final String contactName;
  final String subtitle;
  final int msgCount;
  final VoidCallback? onChatReturned;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingChatScreen(
                bookingId: bookingId,
                title: contactName,
                subtitle: subtitle,
              ),
            ),
          );
          onChatReturned?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Messages', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (msgCount > 0) ...[
                _MsgBadge(count: msgCount),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(rows[i].$1, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                      ),
                      Expanded(child: Text(rows[i].$2, style: AppTextStyles.bodySmall)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
