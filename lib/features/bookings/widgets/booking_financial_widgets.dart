import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';
import '../widgets/request_deposit_sheet.dart';
import '../widgets/send_estimate_sheet.dart';
import '../widgets/send_invoice_sheet.dart';
import 'booking_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1372-line booking_requests_screen.dart.

class OwnerFinancialSection extends ConsumerStatefulWidget {
  const OwnerFinancialSection({super.key, required this.request});
  final BookingRequest request;

  @override
  ConsumerState<OwnerFinancialSection> createState() => _OwnerFinancialSectionState();
}

class _OwnerFinancialSectionState extends ConsumerState<OwnerFinancialSection> {
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
    await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 1,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SendEstimateSheet(bookingId: widget.request.id),
    );
    ref.invalidate(bookingQuotesProvider(widget.request.id));
  }

  Future<void> _openDepositSheet() async {
    await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 1,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => RequestDepositSheet(bookingId: widget.request.id),
    );
    ref.invalidate(bookingDepositProvider(widget.request.id));
  }

  Future<void> _openInvoiceSheet(BookingQuote? estimate, BookingDeposit? deposit) async {
    await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 1,
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
    final eventOver = isOver(widget.request);
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
          FinancialStatusRow(
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
            FinancialStatusRow(
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
            FinancialStatusRow(
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

class FinancialStatusRow extends StatelessWidget {
  const FinancialStatusRow({super.key, required this.label, required this.amount, required this.status, required this.color});
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
