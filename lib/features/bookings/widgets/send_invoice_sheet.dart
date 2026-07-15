import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
import '../providers/bookings_provider.dart';

class SendInvoiceSheet extends ConsumerStatefulWidget {
  const SendInvoiceSheet({
    super.key,
    required this.bookingId,
    this.estimate,
    this.deposit,
  });
  final String bookingId;
  final BookingQuote? estimate;
  final BookingDeposit? deposit;

  @override
  ConsumerState<SendInvoiceSheet> createState() => _SendInvoiceSheetState();
}

class _SendInvoiceSheetState extends ConsumerState<SendInvoiceSheet> {
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with remaining balance: estimate minus paid deposit
    final estimate = widget.estimate?.amount ?? 0.0;
    final depositPaid = (widget.deposit?.status == DepositStatus.paid)
        ? (widget.deposit?.amount ?? 0.0)
        : 0.0;
    final suggested = estimate > 0 ? (estimate - depositPaid) : 0.0;
    _amountCtrl = TextEditingController(
      text: suggested > 0 ? suggested.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    // Card payments have a hard $0.50 minimum (Stripe) — anything less would be
    // accepted here but silently fail when the customer tries to pay it.
    if (amount < 0.50) {
      setState(() => _error = 'Invoice must be at least \$0.50.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(bookingsRepositoryProvider).sendInvoice(
        widget.bookingId,
        amount,
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      ref.invalidate(bookingQuotesProvider(widget.bookingId));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to send invoice. Please try again.'; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final depositPaid = widget.deposit?.status == DepositStatus.paid;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send Invoice', style: AppTextStyles.heading3, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text('Request final payment for the event.', style: AppTextStyles.caption, textAlign: TextAlign.center),
              if (depositPaid && widget.deposit != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Deposit of \$${widget.deposit!.amount.toStringAsFixed(2)} already paid — pre-filled with remaining balance.',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                decoration: const InputDecoration(
                  labelText: 'Invoice amount',
                  prefixText: '\$ ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. Thank you for a great event!',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _submitting ? null : _send,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
