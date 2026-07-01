import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart' show subscriptionProvider, subscriptionPricesProvider;

const _tosUrl = 'https://farlo.app/terms';
const _privacyUrl = 'https://farlo.app/privacy';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSub = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
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
  bool _isAnnual = true;
  String? _errorMessage;

  SubscriptionStatus get _status => widget.sub?.status ?? SubscriptionStatus.trialing;

  Future<void> _purchase() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ref.read(subscriptionProvider.notifier).purchase(annual: _isAnnual);
    } on PurchasesErrorCode catch (e) {
      if (e != PurchasesErrorCode.purchaseCancelledError) {
        setState(() => _errorMessage = _rcErrorMessage(e));
      }
    } catch (e) {
      debugPrint('Purchase error: $e');
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
        if (_status == SubscriptionStatus.active)
          _ActivePlanCard(sub: widget.sub)
        else
          _PricingToggle(
            isAnnual: _isAnnual,
            status: _status,
            onChanged: (v) => setState(() => _isAnnual = v),
          ),
        const SizedBox(height: AppSpacing.lg),
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
        if (_status == SubscriptionStatus.trialing) ...[
          const SizedBox(height: AppSpacing.sm),
          () {
            final daysLeft = widget.sub?.currentPeriodEnd?.difference(DateTime.now()).inDays;
            final msg = daysLeft == null
                ? 'Subscribe to unlock all features.'
                : daysLeft == 0
                    ? 'Your trial expires today.'
                    : 'Your trial ends in $daysLeft day${daysLeft == 1 ? '' : 's'}.';
            return Text(
              '$msg Subscribe now to keep full access.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            );
          }(),
          const SizedBox(height: AppSpacing.sm),
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
            'Subscription auto-renews ${_isAnnual ? 'annually' : 'monthly'}. Cancel anytime in ${Platform.isIOS ? 'App Store' : 'Google Play'} settings.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _LegalLinksRow(),
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
          Text(
            'To cancel, go to ${Platform.isIOS ? 'App Store' : 'Google Play'} Settings → Subscriptions.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _LegalLinksRow extends StatelessWidget {
  const _LegalLinksRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(_tosUrl), mode: LaunchMode.externalApplication),
          child: Text('Terms of Use', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('·', style: AppTextStyles.caption),
        ),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
          child: Text('Privacy Policy', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
        ),
      ],
    );
  }
}

const _features = [
  (Icons.map_outlined, 'Open for business — appear on the customer map'),
  (Icons.shopping_bag_outlined, 'Online ordering for customers'),
  (Icons.event_note_outlined, 'Private event booking requests with messaging'),
  (Icons.campaign_outlined, 'Send announcements to your followers'),
  (Icons.people_outline, 'Employee management & shift scheduling'),
];

class _ActivePlanCard extends ConsumerWidget {
  const _ActivePlanCard({required this.sub});
  final Subscription? sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricesAsync = ref.watch(subscriptionPricesProvider);
    final prices = pricesAsync.asData?.value;
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;

    final isAnnual = sub?.productIdentifier?.contains('yearly') ?? false;
    final planLabel = isAnnual ? 'Annual Plan' : 'Monthly Plan';
    final priceLabel = isAnnual
        ? '${prices?.annualLabel ?? r'$300.00'} / year'
        : '${prices?.monthlyLabel ?? r'$29.99'} / month';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.check_circle_outline, color: primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(planLabel, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(priceLabel, style: AppTextStyles.bodySmall.copyWith(color: primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingToggle extends ConsumerWidget {
  const _PricingToggle({
    required this.isAnnual,
    required this.status,
    required this.onChanged,
  });
  final bool isAnnual;
  final SubscriptionStatus status;
  final ValueChanged<bool> onChanged;

  // Fallback labels shown before App Store products are created in RC.
  // Replaced automatically once real offerings are returned.
  static const _fallbackMonthly = r'$30.00';
  static const _fallbackAnnual = r'$300.00';
  static const _fallbackMonthlyRaw = 30.0;
  static const _fallbackAnnualRaw = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricesAsync = ref.watch(subscriptionPricesProvider);
    final prices = pricesAsync.asData?.value;
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // Use real prices when available, fall back to hardcoded values.
    final monthlyLabel = prices?.monthlyLabel ?? _fallbackMonthly;
    final annualLabel = prices?.annualLabel ?? _fallbackAnnual;
    final mRaw = prices?.monthlyRaw ?? _fallbackMonthlyRaw;
    final aRaw = prices?.annualRaw ?? _fallbackAnnualRaw;

    // Savings % calculated from raw prices (e.g. $30/mo × 12 vs $300/yr = 17%)
    final savingsPct = mRaw > 0
        ? ((mRaw * 12 - aRaw) / (mRaw * 12) * 100).round()
        : 0;

    // Current price label to display large
    final priceLabel = isAnnual
        ? '$annualLabel / year'
        : '$monthlyLabel / month';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Toggle
          Container(
            decoration: BoxDecoration(
              color: isLight ? Colors.grey.shade100 : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _ToggleTab(
                  label: 'Monthly',
                  selected: !isAnnual,
                  onTap: () => onChanged(false),
                ),
                _ToggleTab(
                  label: 'Annual',
                  badge: savingsPct > 0 ? 'Save $savingsPct%' : null,
                  selected: isAnnual,
                  onTap: () => onChanged(true),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Price display
          Text(
            priceLabel,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? (isLight ? Colors.white : Colors.grey.shade700) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected && isLight
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? primary : AppColors.textSecondary,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
      SubscriptionStatus.trialing => () {
          final daysLeft = periodEnd?.difference(DateTime.now()).inDays;
          final sub = daysLeft == null
              ? 'Subscribe to open for business on the map'
              : daysLeft == 0
                  ? 'Your trial expires today — subscribe to keep access'
                  : '$daysLeft day${daysLeft == 1 ? '' : 's'} left in your free trial';
          return (
            'Free Trial',
            Theme.of(context).colorScheme.primary,
            Icons.hourglass_bottom_outlined,
            sub,
          );
        }(),
      SubscriptionStatus.pastDue => (
          'Payment Issue',
          AppColors.error,
          Icons.warning_amber_outlined,
          'Update your payment to stay open on the map',
        ),
      SubscriptionStatus.canceled => (
          'Canceled',
          AppColors.textSecondary,
          Icons.cancel_outlined,
          'Resubscribe to open on the map',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
