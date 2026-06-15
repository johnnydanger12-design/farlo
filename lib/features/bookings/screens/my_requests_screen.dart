import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';

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

// Returns true when the event's end time has passed.
// Falls back to end-of-day if duration is missing.
bool _isOver(BookingRequest r) {
  // Parse "4:00 PM" → 24h hour + minute
  final parts = r.eventTime.trim().split(' ');
  final hm = parts.isNotEmpty ? parts[0].split(':') : <String>[];
  int hour = hm.isNotEmpty ? (int.tryParse(hm[0]) ?? 0) : 0;
  final minute = hm.length > 1 ? (int.tryParse(hm[1]) ?? 0) : 0;
  final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
  if (isPm && hour != 12) hour += 12;
  if (!isPm && hour == 12) hour = 0;

  // Parse "1.5 hours" / "1 hour" → Duration
  final durationMinutes = r.duration != null
      ? ((double.tryParse(r.duration!.split(' ').first) ?? 0) * 60).round()
      : 0;

  final end = DateTime(r.eventDate.year, r.eventDate.month, r.eventDate.day, hour, minute)
      .add(Duration(minutes: durationMinutes));
  return end.isBefore(DateTime.now());
}

String _daysLabel(int days) {
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days > 1) return 'in $days days';
  if (days == -1) return '1 day ago';
  return '${days.abs()} days ago';
}

class MyRequestsScreen extends ConsumerStatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  ConsumerState<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends ConsumerState<MyRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authProvider).asData?.value?.id;
      if (userId != null) {
        ref.read(myBookingRequestsProvider.notifier).load(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncRequests = ref.watch(myBookingRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Event Requests', style: AppTextStyles.heading3),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncRequests.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (requests) {
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 52, color: AppColors.textHint),
                  const SizedBox(height: AppSpacing.md),
                  Text('No requests yet', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Request a private event from any truck profile', style: AppTextStyles.caption),
                ],
              ),
            );
          }

          final pending = requests
              .where((r) => r.status == 'pending' && !_isOver(r))
              .toList();
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
                  r.status == 'cancelled' ||
                  (r.status == 'pending' && _isOver(r)))
              .toList()
            ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

          return RefreshIndicator(
            onRefresh: () async {
              final userId = ref.read(authProvider).asData?.value?.id;
              if (userId != null) await ref.read(myBookingRequestsProvider.notifier).load(userId);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
              children: [
                if (pending.isNotEmpty) ...[
                  _SectionHeader(title: 'Awaiting Response', count: pending.length, color: const Color(0xFFB45309)),
                  const SizedBox(height: AppSpacing.sm),
                  ...pending.map((r) => _MyRequestCard(request: r)),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(title: 'Confirmed', count: upcoming.length, color: AppColors.openGreen),
                  const SizedBox(height: AppSpacing.sm),
                  ...upcoming.map((r) => _MyUpcomingCard(request: r)),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (past.isNotEmpty)
                  _CollapsibleSection(
                    key: const ValueKey('past'),
                    title: 'Past Events',
                    count: past.length,
                    children: past.map((r) => _MyCompactTile(request: r)).toList(),
                  ),
                if (closed.isNotEmpty)
                  _CollapsibleSection(
                    key: const ValueKey('closed'),
                    title: 'Declined / Canceled',
                    count: closed.length,
                    accentColor: AppColors.closedRed,
                    initiallyExpanded: true,
                    children: closed.map((r) => _MyCompactTile(request: r)).toList(),
                  ),
              ],
            ),
          );
        },
      ),
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
          child: Text('$count', style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── Pending card ─────────────────────────────────────────────────────────────

class _MyRequestCard extends ConsumerWidget {
  const _MyRequestCard({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const amber = Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: amber, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.truckName ?? 'Food Truck', style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text('${_fmtShort(request.eventDate)}  ·  ${request.eventTime}', style: AppTextStyles.caption),
                Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _confirmCancel(context, ref),
            style: TextButton.styleFrom(foregroundColor: AppColors.closedRed, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Theme.of(context).colorScheme.surface,
        title: const Text('Cancel Request?'),
        content: Text('Cancel your ${request.eventType} request with ${request.truckName ?? 'this truck'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep It')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.closedRed),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(myBookingRequestsProvider.notifier).cancel(request.id);
    }
  }
}

// ─── Confirmed upcoming card ──────────────────────────────────────────────────

class _MyUpcomingCard extends ConsumerWidget {
  const _MyUpcomingCard({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const green = AppColors.openGreen;
    final days = _daysUntil(request.eventDate);
    final dayColor = days == 0 ? AppColors.closedRed : green;

    return Container(
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
                  Text(request.truckName ?? 'Food Truck', style: AppTextStyles.label),
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
                      TextButton.icon(
                        onPressed: () => _confirmCancel(context, ref),
                        icon: const Icon(Icons.cancel_outlined, size: 14),
                        label: const Text('Cancel Event'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.closedRed,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        _daysLabel(days),
                        style: AppTextStyles.caption.copyWith(color: dayColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Theme.of(context).colorScheme.surface,
        title: const Text('Cancel Event?'),
        content: Text(
          'Cancel your confirmed ${request.eventType} with ${request.truckName ?? 'this truck'} on ${_fmtLong(request.eventDate)}? The truck owner will be notified.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep It')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.closedRed),
            child: const Text('Cancel Event'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(myBookingRequestsProvider.notifier).cancel(request.id);
    }
  }
}

// ─── Collapsible section ──────────────────────────────────────────────────────

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
                  child: Text('${widget.count}', style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textHint),
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

// ─── Compact tile ─────────────────────────────────────────────────────────────

class _MyCompactTile extends StatelessWidget {
  const _MyCompactTile({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context) {
    final isExpired = request.status == 'pending' && _isOver(request);
    final isCancelled = request.status == 'cancelled';
    final isDeclined = request.status == 'declined';
    final reason = request.cancellationReason;

    final String? statusLabel;
    if (isExpired) {
      statusLabel = 'No response';
    } else if (isCancelled) {
      statusLabel = request.cancelledBy == 'owner' ? 'Canceled by vendor' : 'Canceled by you';
    } else if (isDeclined) {
      statusLabel = 'Declined';
    } else {
      statusLabel = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.truckName ?? 'Food Truck', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 1),
                    Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmtShort(request.eventDate), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  if (statusLabel != null)
                    Text(statusLabel, style: AppTextStyles.caption.copyWith(color: AppColors.closedRed)),
                ],
              ),
            ],
          ),
          if (isCancelled && reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"$reason"',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
