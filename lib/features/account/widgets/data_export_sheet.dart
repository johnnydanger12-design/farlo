import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../models/data_export_request.dart';
import '../providers/data_export_provider.dart';
import '../repositories/data_export_repository.dart';
import 'account_shared.dart';

/// GDPR/CCPA right-to-portability: lets the user request a copy of their own
/// Farlo data. Requesting only ever queues a request — request-data-export
/// returns immediately, and a cron-triggered background worker
/// (process-data-exports) does the actual compilation, so this sheet's job
/// is entirely reflecting the live status of that async request, not
/// performing the export itself.
class DataExportSheet extends ConsumerWidget {
  const DataExportSheet({super.key});

  Future<void> _requestExport(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(dataExportRepositoryProvider).requestExport();
      if (context.mounted) {
        context.showSuccess("We're preparing your data export — you'll be notified when it's ready.");
      }
    } on DataExportAlreadyInProgressException {
      if (context.mounted) {
        context.showInfo('An export is already in progress.');
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Could not request an export. Please try again.');
      }
    }
  }

  Future<void> _openDownload(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      context.showError('Could not open the download link.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRequest = ref.watch(latestDataExportRequestProvider);

    return buildSheetContainer(
      context: context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Download Your Data', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Get a copy of your Farlo account data — profile, orders, reviews, bookings, and (if you own a business) its menu and booking history.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            asyncRequest.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
              error: (_, _) => Text('Could not load export status.', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              data: (request) => _StatusView(
                request: request,
                onRequest: () => _requestExport(context, ref),
                onDownload: (url) => _openDownload(context, url),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.request, required this.onRequest, required this.onDownload});

  final DataExportRequest? request;
  final VoidCallback onRequest;
  final void Function(String url) onDownload;

  @override
  Widget build(BuildContext context) {
    if (request == null) {
      return AppButton(label: 'Request My Data', onPressed: onRequest);
    }

    switch (request!.status) {
      case DataExportStatus.pending:
      case DataExportStatus.processing:
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  "We're preparing your export. You'll get a notification and an email when it's ready.",
                  style: AppTextStyles.bodySmall,
                ),
              ),
            ],
          ),
        );
      case DataExportStatus.completed:
        if (!request!.isReady) {
          return AppButton(label: 'Request My Data', onPressed: onRequest);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.openGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                request!.expiresAt != null
                    ? 'Ready. This link expires ${_formatDate(request!.expiresAt!)}.'
                    : 'Ready to download.',
                style: AppTextStyles.caption.copyWith(color: AppColors.openGreen),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Download', onPressed: () => onDownload(request!.downloadUrl!)),
          ],
        );
      case DataExportStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The last export attempt failed. Please try again.', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Try Again', onPressed: onRequest),
          ],
        );
      case DataExportStatus.expired:
        return AppButton(label: 'Request My Data', onPressed: onRequest);
    }
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
}
