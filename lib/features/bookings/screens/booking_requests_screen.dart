import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _fmtShort(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
String _fmtLong(DateTime d) => '${_weekdays[d.weekday - 1]}, ${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';

class BookingRequestsScreen extends ConsumerWidget {
  const BookingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests', style: AppTextStyles.heading3),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
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

class _BookingRequestsListState extends ConsumerState<_BookingRequestsList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId);
    });
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

        // Group into pending vs others
        final pending = requests.where((r) => r.status == 'pending').toList();
        final others = requests.where((r) => r.status != 'pending').toList();

        return RefreshIndicator(
          onRefresh: () => ref.read(ownerBookingRequestsProvider.notifier).load(widget.truckId),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (pending.isNotEmpty) ...[
                Text('New Requests', style: AppTextStyles.heading3),
                const SizedBox(height: AppSpacing.md),
                ...pending.map((r) => _RequestTile(request: r)),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (others.isNotEmpty) ...[
                Text('Past Requests', style: AppTextStyles.heading3),
                const SizedBox(height: AppSpacing.md),
                ...others.map((r) => _RequestTile(request: r)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = _fmtShort(request.eventDate);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        title: Row(
          children: [
            Expanded(
              child: Text(request.contactName, style: AppTextStyles.label),
            ),
            _StatusBadge(status: request.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$dateStr · ${request.eventTime}', style: AppTextStyles.caption),
              Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: () => _showDetail(context, ref),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _RequestDetailSheet(request: request, ref: ref),
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

class _RequestDetailSheet extends StatelessWidget {
  const _RequestDetailSheet({required this.request, required this.ref});
  final BookingRequest request;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtLong(request.eventDate);

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
                      _StatusBadge(status: request.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DetailSection(
                    title: 'Contact',
                    rows: [
                      ('Name', request.contactName),
                      ('Email', request.contactEmail),
                      if (request.contactPhone != null) ('Phone', request.contactPhone!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DetailSection(
                    title: 'Event',
                    rows: [
                      ('Date', dateStr),
                      ('Time', request.eventTime),
                      ('Type', request.eventType),
                      ('Location', request.eventLocation),
                      if (request.guestCount != null) ('Guests', '${request.guestCount}'),
                    ],
                  ),
                  if (request.notes?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Notes', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(request.notes!, style: AppTextStyles.bodySmall),
                  ],
                  if (request.status == 'pending') ...[
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
                            onPressed: () => _updateStatus(context, 'declined'),
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
                            onPressed: () => _updateStatus(context, 'accepted'),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
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

  void _updateStatus(BuildContext context, String status) {
    ref.read(ownerBookingRequestsProvider.notifier).updateStatus(request.id, status);
    Navigator.of(context).pop();
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
