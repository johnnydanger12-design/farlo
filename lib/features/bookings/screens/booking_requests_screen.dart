import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/tab_reselect_provider.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import '../widgets/book_truck_sheet.dart';
import '../widgets/booking_list_tiles.dart';
import '../widgets/booking_shared.dart';

String? _closedSublabel(BookingRequest r) {
  if (r.status == 'declined') return 'Declined';
  if (r.status == 'expired') return 'Expired — no response';
  if (r.status == 'cancelled') {
    return r.cancelledBy == 'consumer' ? 'Canceled by customer' : 'Canceled by you';
  }
  if (r.status == 'pending') return 'Expired';
  return null;
}

class BookingRequestsScreen extends ConsumerWidget {
  const BookingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TabReselectEvent?>(tabReselectProvider, (prev, next) {
      if (next != null && next.index == 1 && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ref.invalidate(ownerBookingRequestsProvider);
      }
    });
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
                showTabAwareModalBottomSheet(
                  context: context,
                  tabIndex: 1,
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
          if (truck == null) return const Center(child: Text('No business found.'));
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

        final pending = requests.where((r) => r.status == 'pending' && !isOver(r)).toList();
        final upcoming = requests
            .where((r) => r.status == 'accepted' && !isOver(r))
            .toList()
          ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
        final past = requests
            .where((r) => r.status == 'accepted' && isOver(r))
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
        final closed = requests
            .where((r) =>
                r.status == 'declined' ||
                r.status == 'expired' ||
                r.status == 'cancelled' ||
                (r.status == 'pending' && isOver(r)))
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

        return RefreshIndicator(
          onRefresh: () => ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            children: [
              if (pending.isNotEmpty) ...[
                SectionHeader(title: 'Action Needed', count: pending.length, color: const Color(0xFFB45309)),
                const SizedBox(height: AppSpacing.sm),
                ...pending.map((r) => PendingTile(request: r)),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (upcoming.isNotEmpty) ...[
                SectionHeader(title: 'Upcoming', count: upcoming.length, color: AppColors.openGreen),
                const SizedBox(height: AppSpacing.sm),
                ...upcoming.map((r) => UpcomingCard(request: r)),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (past.isNotEmpty)
                CollapsibleSection(
                  key: const ValueKey('past'),
                  title: 'Past Events',
                  count: past.length,
                  children: past.map((r) => CompactTile(request: r)).toList(),
                ),
              if (closed.isNotEmpty)
                CollapsibleSection(
                  key: const ValueKey('closed'),
                  title: 'Declined / Canceled',
                  count: closed.length,
                  accentColor: AppColors.closedRed,
                  initiallyExpanded: true,
                  children: closed.map((r) => CompactTile(request: r, sublabel: _closedSublabel(r))).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}

