import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import 'booking_detail_sheet.dart';
import 'booking_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1372-line booking_requests_screen.dart.

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.count, required this.color});
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

class PendingTile extends ConsumerWidget {
  const PendingTile({super.key, required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const amber = Color(0xFFB45309);
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;
    return GestureDetector(
      onTap: () async {
        await showTabAwareModalBottomSheet(
          context: context,
          tabIndex: 1,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => RequestDetailSheet(request: request),
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
                      '${fmtShort(request.eventDate)}  ·  ${request.eventTime}',
                      style: AppTextStyles.caption,
                    ),
                    Text(request.eventType, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (msgCount > 0) ...[
                MsgBadge(count: msgCount),
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

String _daysLabel(int days) {
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days > 1) return 'in $days days';
  if (days == -1) return '1 day ago';
  return '${days.abs()} days ago';
}

class UpcomingCard extends ConsumerWidget {
  const UpcomingCard({super.key, required this.request});
  final BookingRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const green = AppColors.openGreen;
    final days = daysUntil(request.eventDate);
    final dayColor = days == 0 ? AppColors.closedRed : green;
    final userId = ref.watch(authProvider).asData?.value?.id ?? '';
    final msgCount = ref.watch(bookingMessageCountProvider((request.id, userId))).asData?.value ?? 0;

    return GestureDetector(
      onTap: () async {
        await showTabAwareModalBottomSheet(
          context: context,
          tabIndex: 1,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => RequestDetailSheet(request: request),
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
                      months[request.eventDate.month - 1].toUpperCase(),
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
                        if (msgCount > 0) MsgBadge(count: msgCount) else const SizedBox.shrink(),
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

class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
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
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
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

class CompactTile extends StatelessWidget {
  const CompactTile({super.key, required this.request, this.sublabel});
  final BookingRequest request;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showTabAwareModalBottomSheet(
        context: context,
        tabIndex: 1,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RequestDetailSheet(request: request),
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
                Text(fmtShort(request.eventDate), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
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
