import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import '../screens/booking_chat_screen.dart';

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

bool _withinCancellationWindow(BookingRequest r) {
  final hours = r.truckCancellationPolicyHours;
  if (hours == null) return false;
  final eventStart = DateTime(r.eventDate.year, r.eventDate.month, r.eventDate.day);
  return eventStart.difference(DateTime.now()).inHours < hours;
}

String _policyLabel(int hours) {
  if (hours < 24) return '$hours hours';
  final days = hours ~/ 24;
  return days == 1 ? '1 day' : '$days days';
}

Future<void> _openChat(BuildContext context, BookingRequest request) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BookingChatScreen(
        bookingId: request.id,
        title: request.truckName ?? 'Business',
        subtitle: '${request.eventType}  ·  ${_fmtShort(request.eventDate)}',
      ),
    ),
  );
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
                  Text('Request a private event from any business profile', style: AppTextStyles.caption),
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
                  r.status == 'expired' ||
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

// ─── Message badge ────────────────────────────────────────────────────────────

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

// ─── Pending card ─────────────────────────────────────────────────────────────

class _MyRequestCard extends ConsumerWidget {
  const _MyRequestCard({required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const amber = Color(0xFFB45309);
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;

    return GestureDetector(
      onTap: () async {
        await _openChat(context, request);
        if (context.mounted) ref.invalidate(bookingMessageCountProvider((request.id, userId)));
      },
      child: Container(
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
                  Text(request.truckName ?? 'Business', style: AppTextStyles.label),
                  const SizedBox(height: 2),
                  Text('${_fmtShort(request.eventDate)}  ·  ${request.eventTime}', style: AppTextStyles.caption),
                  Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (msgCount > 0) ...[
              _MsgBadge(count: msgCount),
              const SizedBox(width: 6),
            ],
            TextButton(
              onPressed: () => _confirmCancel(context, ref),
              style: TextButton.styleFrom(foregroundColor: AppColors.closedRed, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Cancel'),
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
        title: const Text('Cancel Request?'),
        content: Text('Cancel your ${request.eventType} request with ${request.truckName ?? 'this business'}?'),
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
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;

    return GestureDetector(
      onTap: () async {
        await _openChat(context, request);
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
                    Text(request.truckName ?? 'Business', style: AppTextStyles.label),
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
                        Semantics(
                          label: 'Cancel event booking',
                          button: true,
                          child: TextButton.icon(
                            onPressed: () => _confirmCancel(context, ref),
                            icon: const Icon(Icons.cancel_outlined, size: 14),
                            label: const Text('Cancel Event'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.closedRed,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (msgCount > 0) ...[
                              _MsgBadge(count: msgCount),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              _daysLabel(days),
                              style: AppTextStyles.caption.copyWith(color: dayColor, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    _ConsumerFinancialSection(request: request),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final bgColor = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Theme.of(context).colorScheme.surface;

    if (_withinCancellationWindow(request)) {
      final hours = request.truckCancellationPolicyHours!;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: bgColor,
          title: const Text('Can\'t Cancel Online'),
          content: Text(
            '${request.truckName ?? 'This business'} requires cancellations at least ${_policyLabel(hours)} before the event. Contact them directly to discuss cancellation.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: bgColor,
        title: const Text('Cancel Event?'),
        content: Text(
          'Cancel your confirmed ${request.eventType} with ${request.truckName ?? 'this business'} on ${_fmtLong(request.eventDate)}? The business owner will be notified.',
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
    final isExpired = request.status == 'expired' || (request.status == 'pending' && _isOver(request));
    final isCancelled = request.status == 'cancelled';
    final isDeclined = request.status == 'declined';
    final isPastAccepted = request.status == 'accepted' && _isOver(request);
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

    return GestureDetector(
      onTap: () => _openChat(context, request),
      child: Container(
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
                      Text(request.truckName ?? 'Business', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
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
            if ((isCancelled || isDeclined) && reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '"$reason"',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (isPastAccepted)
              _ConsumerFinancialSection(request: request),
          ],
        ),
      ),
    );
  }
}

// ─── Consumer financial section ───────────────────────────────────────────────

class _ConsumerFinancialSection extends ConsumerStatefulWidget {
  const _ConsumerFinancialSection({required this.request});
  final BookingRequest request;

  @override
  ConsumerState<_ConsumerFinancialSection> createState() => _ConsumerFinancialSectionState();
}

class _ConsumerFinancialSectionState extends ConsumerState<_ConsumerFinancialSection> {
  bool _paying = false;
  String? _error;
  bool _depositJustPaid = false;
  bool _invoiceJustPaid = false;

  // One key per distinct payment target (deposit vs. invoice), generated once
  // and reused across retries of that same payment attempt so a network-blip
  // retry reuses the same Stripe PaymentIntent instead of charging twice.
  final _idempotencyKeys = <String, String>{};

  String _idempotencyKeyFor(String type, String recordId) {
    final cacheKey = '$type:$recordId';
    return _idempotencyKeys.putIfAbsent(cacheKey, () {
      final rand = Random.secure();
      return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
    });
  }

  Future<void> _pay({required String type, required String recordId}) async {
    setState(() { _paying = true; _error = null; });
    try {
      final result = await ref.read(bookingsRepositoryProvider).createBookingPaymentIntent(
        type: type,
        recordId: recordId,
        bookingId: widget.request.id,
        idempotencyKey: _idempotencyKeyFor(type, recordId),
      );
      // The PaymentIntent is a direct charge living on the business's own
      // connected Stripe account, not the platform's — the SDK has to be
      // told that account before it can confirm/present it. Reset in the
      // finally block below so it never leaks into some other Stripe SDK
      // use elsewhere in the app.
      Stripe.stripeAccountId = result['stripe_account_id'] as String;
      await Stripe.instance.applySettings();
      if (!mounted) return;
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: result['client_secret'] as String,
          merchantDisplayName: 'Farlo',
          // Apple Pay merchant ID registered 2026-07-23 (Stripe.merchantIdentifier
          // set once in main.dart). No Google Pay merchant setup yet.
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      // PaymentSheet succeeded — payment is confirmed on Stripe's side.
      // Optimistically mark as paid locally so the UI reflects it immediately
      // while the webhook asynchronously updates the DB.
      if (mounted) {
        setState(() {
          if (type == 'deposit') _depositJustPaid = true;
          if (type == 'invoice') _invoiceJustPaid = true;
        });
      }
      ref.invalidate(bookingQuotesProvider(widget.request.id));
      ref.invalidate(bookingDepositProvider(widget.request.id));
    } on StripeException catch (e) {
      if (e.error.code != FailureCode.Canceled && mounted) {
        setState(() => _error = e.error.localizedMessage ?? 'Payment failed.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyPaymentError(e));
    } finally {
      // Always clear this back out, win or lose — it's a global SDK setting,
      // not scoped to this checkout, so it must never leak into whatever the
      // next Stripe SDK interaction anywhere in the app happens to be.
      Stripe.stripeAccountId = null;
      await Stripe.instance.applySettings();
      if (mounted) setState(() => _paying = false);
    }
  }

  String _friendlyPaymentError(Object e) {
    final message = e.toString().replaceFirst('Exception: ', '');
    return switch (message) {
      'amount is below the minimum chargeable amount' =>
        'This amount is too small to charge — card payments require at least \$0.50.',
      'deposit_already_paid' || 'invoice_already_paid' => 'This has already been paid.',
      'deposit_not_found' || 'invoice_not_found' => 'This request is no longer available. Please refresh and try again.',
      'truck_subscription_inactive' => 'This business\'s account is temporarily inactive. Please contact them directly.',
      'owner_stripe_not_connected' => 'This business hasn\'t finished setting up payments yet. Please contact them directly.',
      _ => 'Payment failed. Please try again.',
    };
  }

  Future<void> _respondEstimate(String quoteId, bool accepted) async {
    try {
      await ref.read(bookingsRepositoryProvider).respondToEstimate(quoteId, widget.request.id, accepted);
      ref.invalidate(bookingQuotesProvider(widget.request.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final quotes = ref.watch(bookingQuotesProvider(widget.request.id)).asData?.value ?? [];
    final deposit = ref.watch(bookingDepositProvider(widget.request.id)).asData?.value;

    final estimate = quotes.where((q) => q.type == QuoteType.estimate).lastOrNull;
    final invoice = quotes.where((q) => q.type == QuoteType.invoice).lastOrNull;

    if (estimate == null && deposit == null && invoice == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),

        // ── Estimate ─────────────────────────────────────────────────────────
        if (estimate != null) ...[
          if (estimate.status == QuoteStatus.sent) ...[
            _QuoteRow(label: 'Estimate', amount: estimate.amount, notes: estimate.notes),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _paying ? null : () => _respondEstimate(estimate.id, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.closedRed,
                      side: const BorderSide(color: AppColors.closedRed),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _paying ? null : () => _respondEstimate(estimate.id, true),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else
            _ConsumerStatusRow(
              label: 'Estimate',
              amount: estimate.amount,
              status: switch (estimate.status) {
                QuoteStatus.accepted => 'Accepted',
                QuoteStatus.declined => 'Declined',
                QuoteStatus.paid => 'Paid',
                _ => '',
              },
              color: switch (estimate.status) {
                QuoteStatus.accepted || QuoteStatus.paid => AppColors.openGreen,
                QuoteStatus.declined => AppColors.closedRed,
                _ => AppColors.textSecondary,
              },
            ),
        ],

        // ── Deposit ───────────────────────────────────────────────────────────
        if (deposit != null) ...[
          const SizedBox(height: AppSpacing.sm),
          if (deposit.status == DepositStatus.requested && !_depositJustPaid)
            FilledButton.icon(
              onPressed: _paying ? null : () => _pay(type: 'deposit', recordId: deposit.id),
              icon: _paying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline, size: 14),
              label: Text('Pay Deposit · \$${deposit.amount.toStringAsFixed(2)}'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            )
          else
            _ConsumerStatusRow(
              label: 'Deposit',
              amount: deposit.amount,
              status: (deposit.status == DepositStatus.paid || _depositJustPaid) ? 'Paid' : 'Refunded',
              color: (deposit.status == DepositStatus.paid || _depositJustPaid) ? AppColors.openGreen : AppColors.textSecondary,
            ),
        ],

        // ── Invoice ───────────────────────────────────────────────────────────
        if (invoice != null) ...[
          const SizedBox(height: AppSpacing.sm),
          if (invoice.status == QuoteStatus.sent && !_invoiceJustPaid)
            FilledButton.icon(
              onPressed: _paying ? null : () => _pay(type: 'invoice', recordId: invoice.id),
              icon: _paying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.receipt_outlined, size: 14),
              label: Text('Pay Invoice · \$${invoice.amount.toStringAsFixed(2)}'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            )
          else
            _ConsumerStatusRow(
              label: 'Invoice',
              amount: invoice.amount,
              status: 'Paid',
              color: AppColors.openGreen,
            ),
        ],

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.label, required this.amount, this.notes});
  final String label;
  final double amount;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.label),
            Text('\$${amount.toStringAsFixed(2)}', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        if (notes != null && notes!.isNotEmpty)
          Text(notes!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _ConsumerStatusRow extends StatelessWidget {
  const _ConsumerStatusRow({required this.label, required this.amount, required this.status, required this.color});
  final String label;
  final double amount;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label · \$${amount.toStringAsFixed(2)}', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(status, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
