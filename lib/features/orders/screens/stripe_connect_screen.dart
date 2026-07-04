import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/app_button.dart';
import '../repositories/orders_repository.dart';

final _stripeStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;
  final row = await Supabase.instance.client
      .from('profiles')
      .select('stripe_account_id')
      .eq('id', userId)
      .single();
  return (row['stripe_account_id'] as String?) != null;
});

class StripeConnectScreen extends ConsumerStatefulWidget {
  const StripeConnectScreen({super.key});

  @override
  ConsumerState<StripeConnectScreen> createState() => _StripeConnectScreenState();
}

class _StripeConnectScreenState extends ConsumerState<StripeConnectScreen>
    with WidgetsBindingObserver {
  bool _loading = false;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _linkSub = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == 'farlo' && uri.host == 'stripe-connect') {
        ref.invalidate(_stripeStatusProvider);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(_stripeStatusProvider);
    }
  }

  Future<void> _connect() async {
    setState(() => _loading = true);
    try {
      final repo = OrdersRepository(Supabase.instance.client);
      final url = await repo.connectStripeAccount();
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        context.showError(sanitizeErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncStatus = ref.watch(_stripeStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stripe Payments'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncStatus.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e', style: AppTextStyles.bodySmall)),
        data: (isConnected) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _StatusCard(isConnected: isConnected),
            const SizedBox(height: AppSpacing.xl),
            if (!isConnected) ...[
              Text(
                'Connect your Stripe account to accept payments. Stripe processes the payment and deposits directly to your bank — Farlo never touches your funds.',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'After completing setup on Stripe\'s website, return to this app — your status will update automatically.',
                        style: AppTextStyles.caption.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Connect with Stripe',
                onPressed: _loading ? null : _connect,
                isLoading: _loading,
              ),
            ] else ...[
              Text(
                'Your Stripe account is connected. Payments from orders and bookings deposit directly to your bank account.',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(
                onPressed: _loading ? null : _connect,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Open Stripe Dashboard'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => ref.invalidate(_stripeStatusProvider),
              child: const Text('Refresh Status'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isConnected});
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade300 : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            color: isConnected ? Colors.green : AppColors.textHint,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            isConnected ? 'Stripe Connected' : 'Not Connected',
            style: AppTextStyles.label.copyWith(
              color: isConnected ? Colors.green.shade700 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
