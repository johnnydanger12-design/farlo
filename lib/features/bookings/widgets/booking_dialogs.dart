import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/booking_request.dart';
import '../screens/booking_chat_screen.dart';
import 'booking_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1372-line booking_requests_screen.dart.

class AddToCalendarDialog extends StatelessWidget {
  const AddToCalendarDialog({super.key, required this.request});
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
          Text(fmtLong(request.eventDate), style: AppTextStyles.bodySmall),
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

class DeclineReasonDialog extends StatefulWidget {
  const DeclineReasonDialog({super.key, required this.contactName});
  final String contactName;

  @override
  State<DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<DeclineReasonDialog> {
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

class CancelMessageDialog extends StatefulWidget {
  const CancelMessageDialog({super.key, required this.contactName});
  final String contactName;

  @override
  State<CancelMessageDialog> createState() => _CancelMessageDialogState();
}

class _CancelMessageDialogState extends State<CancelMessageDialog> {
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

class MessagesRow extends StatelessWidget {
  const MessagesRow({
    super.key,
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
                MsgBadge(count: msgCount),
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
