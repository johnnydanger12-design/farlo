import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import 'booking_dialogs.dart';
import 'booking_financial_widgets.dart';
import 'booking_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1372-line booking_requests_screen.dart.

class RequestDetailSheet extends ConsumerStatefulWidget {
  const RequestDetailSheet({super.key, required this.request});
  final BookingRequest request;

  @override
  ConsumerState<RequestDetailSheet> createState() => _RequestDetailSheetState();
}

class _RequestDetailSheetState extends ConsumerState<RequestDetailSheet> {
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
        builder: (_) => AddToCalendarDialog(request: widget.request),
      );
      addCalendar = add == true;
    }

    if (mounted) Navigator.of(context).pop();

    if (addCalendar) _addToCalendar(widget.request);
  }

  Future<void> _declinePending() async {
    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => DeclineReasonDialog(contactName: widget.request.contactName),
    );
    if (result?.$1 == true) await _updateStatus('declined', cancellationReason: result?.$2);
  }

  Future<void> _cancelAccepted() async {
    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => CancelMessageDialog(contactName: widget.request.contactName),
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
    final dateStr = fmtLong(widget.request.eventDate);

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
                      StatusBadge(status: widget.request.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DetailSection(
                    title: 'Requester',
                    rows: [
                      ('Name', widget.request.contactName),
                      ('Email', widget.request.contactEmail),
                      if (widget.request.contactPhone != null) ('Phone', widget.request.contactPhone!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DetailSection(
                    title: 'Event',
                    rows: [
                      ('Date', dateStr),
                      ('Time', widget.request.eventTime),
                      if (widget.request.duration != null) ('Duration', widget.request.duration!),
                      ('Type', widget.request.eventType),
                      ('Location', widget.request.eventLocation),
                      if (widget.request.guestCount != null) ('Guests', '${widget.request.guestCount}'),
                      if (widget.request.otherTrucksPresent == true)
                        ('Other businesses', widget.request.otherTrucksCount != null
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
                  MessagesRow(
                    bookingId: widget.request.id,
                    contactName: widget.request.contactName,
                    subtitle: '${widget.request.eventType}  ·  ${fmtShort(widget.request.eventDate)}',
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
                    OwnerFinancialSection(request: widget.request),
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
                  if (widget.request.status == 'accepted' && !isOver(widget.request)) ...[
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

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
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

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.rows});
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
