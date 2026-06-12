import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSub = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncSub.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load subscription', style: AppTextStyles.bodySmall),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => ref.read(subscriptionProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (sub) => _SubscriptionBody(sub: sub),
      ),
    );
  }
}

class _SubscriptionBody extends ConsumerStatefulWidget {
  const _SubscriptionBody({required this.sub});
  final Subscription? sub;

  @override
  ConsumerState<_SubscriptionBody> createState() => _SubscriptionBodyState();
}

class _SubscriptionBodyState extends ConsumerState<_SubscriptionBody> {
  bool _isLoading = false;
  String? _errorMessage;

  SubscriptionStatus get _status => widget.sub?.status ?? SubscriptionStatus.trialing;

  Future<void> _purchase() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ref.read(subscriptionProvider.notifier).purchase();
    } on PurchasesErrorCode catch (e) {
      if (e != PurchasesErrorCode.purchaseCancelledError) {
        setState(() => _errorMessage = _rcErrorMessage(e));
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ref.read(subscriptionProvider.notifier).restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored successfully')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'No purchases found to restore.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _rcErrorMessage(PurchasesErrorCode code) => switch (code) {
        PurchasesErrorCode.networkError => 'Network error. Check your connection and try again.',
        PurchasesErrorCode.storeProblemError => 'There was a problem with the App Store. Try again later.',
        PurchasesErrorCode.purchaseNotAllowedError => 'Purchases are not allowed on this device.',
        _ => 'Purchase failed. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _StatusCard(status: _status, periodEnd: widget.sub?.currentPeriodEnd),
        const SizedBox(height: AppSpacing.xl),
        Text('What\'s included', style: AppTextStyles.heading3),
        const SizedBox(height: AppSpacing.md),
        ..._features.map((f) => _FeatureRow(icon: f.$1, label: f.$2)),
        const SizedBox(height: AppSpacing.xl),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_status == SubscriptionStatus.trialing || _status == SubscriptionStatus.canceled) ...[
          FilledButton(
            onPressed: _isLoading ? null : _purchase,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: primary,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    _status == SubscriptionStatus.trialing ? 'Activate Subscription' : 'Resubscribe',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: _isLoading ? null : _restore,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Restore Purchases'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Subscription auto-renews monthly. Cancel anytime in App Store settings.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
        if (_status == SubscriptionStatus.pastDue) ...[
          FilledButton(
            onPressed: _isLoading ? null : _purchase,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.error,
            ),
            child: const Text('Update Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
        if (_status == SubscriptionStatus.active) ...[
          OutlinedButton(
            onPressed: _isLoading ? null : _restore,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Restore Purchases'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'To cancel, go to App Store Settings → Subscriptions.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

const _features = [
  (Icons.map_outlined, 'Live location on the consumer map'),
  (Icons.restaurant_menu_outlined, 'Full menu management'),
  (Icons.schedule_outlined, 'Operating hours display'),
  (Icons.photo_library_outlined, 'Logo and photo gallery'),
  (Icons.star_outline, 'Reviews and ratings'),
  (Icons.analytics_outlined, 'Customer analytics (coming soon)'),
];

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, this.periodEnd});
  final SubscriptionStatus status;
  final DateTime? periodEnd;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon, subtitle) = switch (status) {
      SubscriptionStatus.active => (
          'Active',
          AppColors.openGreen,
          Icons.check_circle_outline,
          periodEnd != null ? 'Renews ${_formatDate(periodEnd!)}' : 'Subscription active',
        ),
      SubscriptionStatus.trialing => (
          'Free Trial',
          Theme.of(context).colorScheme.primary,
          Icons.hourglass_bottom_outlined,
          periodEnd != null ? 'Trial ends ${_formatDate(periodEnd!)}' : 'Activate to publish your truck',
        ),
      SubscriptionStatus.pastDue => (
          'Payment Issue',
          AppColors.error,
          Icons.warning_amber_outlined,
          'Update your payment to stay live on the map',
        ),
      SubscriptionStatus.canceled => (
          'Canceled',
          AppColors.textSecondary,
          Icons.cancel_outlined,
          'Resubscribe to appear on the map',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(label, style: AppTextStyles.label.copyWith(color: color, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}
