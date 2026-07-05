import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../orders/repositories/orders_repository.dart';
import '../providers/dashboard_providers.dart';

class DashboardStripeStatusCard extends ConsumerStatefulWidget {
  const DashboardStripeStatusCard({super.key});

  @override
  ConsumerState<DashboardStripeStatusCard> createState() => _DashboardStripeStatusCardState();
}

class _DashboardStripeStatusCardState extends ConsumerState<DashboardStripeStatusCard> {
  bool _launching = false;

  Future<void> _openStripe(bool isConnected) async {
    if (!isConnected) {
      context.go('/dashboard/stripe-connect');
      return;
    }
    setState(() => _launching = true);
    try {
      final url = await OrdersRepository(Supabase.instance.client)
          .connectStripeAccount();
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) context.go('/dashboard/stripe-connect');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncStatus = ref.watch(stripeConnectedProvider);
    final isConnected = asyncStatus.asData?.value ?? false;
    final isLoading = asyncStatus.isLoading || _launching;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isConnected
                    ? AppColors.openGreen.withValues(alpha: 0.12)
                    : Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isConnected
                    ? Icons.check_circle_outline
                    : Icons.account_balance_outlined,
                size: 20,
                color: isConnected
                    ? AppColors.openGreen
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected ? 'Stripe Connected' : 'Payments Not Set Up',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isConnected
                          ? AppColors.openGreen
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    isConnected
                        ? 'Tap to manage your Stripe account'
                        : 'Required for orders and booking payments',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Semantics(
                label: isConnected ? 'Open Stripe payout dashboard' : 'Set up Stripe payouts',
                button: true,
                child: TextButton(
                  onPressed: () => _openStripe(isConnected),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Text(
                    isConnected ? 'Dashboard →' : 'Set Up →',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isConnected
                          ? AppColors.openGreen
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
