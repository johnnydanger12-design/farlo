import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/pos_integration.dart';
import '../providers/pos_integration_provider.dart';

class PosIntegrationScreen extends ConsumerStatefulWidget {
  const PosIntegrationScreen({super.key});

  @override
  ConsumerState<PosIntegrationScreen> createState() => _PosIntegrationScreenState();
}

class _PosIntegrationScreenState extends ConsumerState<PosIntegrationScreen> {
  bool _togglingEnabled = false;

  Future<void> _setEnabled(bool enabled) async {
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    setState(() => _togglingEnabled = true);
    try {
      await ref.read(posIntegrationRepositoryProvider).setEnabled(truck.id, enabled);
      ref.invalidate(posIntegrationProvider);
    } catch (e) {
      if (mounted) context.showError('Could not update: ${sanitizeErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _togglingEnabled = false);
    }
  }

  Future<void> _showRequestPosDialog() async {
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Don't See Your POS?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Which POS do you use?'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit')),
        ],
      ),
    );
    if (submitted != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(posIntegrationRepositoryProvider).submitPosRequest(
            truck.id,
            requestedProvider: nameCtrl.text.trim(),
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
      if (mounted) context.showSuccess('Thanks! We\'ll let you know if we add support for it.');
    } catch (e) {
      if (mounted) context.showError('Could not submit: ${sanitizeErrorMessage(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncIntegration = ref.watch(posIntegrationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Point of Sale'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncIntegration.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (integration) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Connect your POS to automatically send Farlo orders to it for printing and fulfillment.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (integration != null) ...[
              _StatusCard(integration: integration),
              if (integration.environment != 'sandbox') ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'We recommend placing one small real test order to confirm it reaches your ${integration.providerLabel} account and prints correctly.',
                          style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                value: integration.enabled,
                onChanged: _togglingEnabled ? null : _setEnabled,
                title: const Text('POS Integration Enabled'),
                subtitle: Text('Merchant ID: ${integration.externalMerchantId}', style: AppTextStyles.caption),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () => context.push(
                  '/owner-account/pos-integration/connect-${integration.provider}',
                ),
                child: Text('Reconnect ${integration.providerLabel}'),
              ),
            ] else ...[
              AppButton(
                label: 'Connect Clover',
                onPressed: () => context.push('/owner-account/pos-integration/connect-clover'),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Connect Square',
                isOutlined: true,
                onPressed: () => context.push('/owner-account/pos-integration/connect-square'),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: TextButton(
                onPressed: _showRequestPosDialog,
                child: const Text("Don't see your POS? Request it"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.integration});
  final PosIntegration integration;

  @override
  Widget build(BuildContext context) {
    // Sandbox is Square/Clover's own fake-testing environment — a real
    // connection there never receives real orders. Flagging it here (rather
    // than only in fine print elsewhere) avoids a business owner mistakenly
    // believing they're live when they're not.
    final isSandbox = integration.environment == 'sandbox';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (isSandbox ? Colors.orange : Colors.green).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSandbox ? Colors.orange.shade300 : Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(
            isSandbox ? Icons.warning_amber_outlined : Icons.check_circle_outline,
            color: isSandbox ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isSandbox
                  ? '${integration.providerLabel} Connected (Sandbox — test mode, not receiving real orders)'
                  : '${integration.providerLabel} Connected',
              style: AppTextStyles.label.copyWith(
                color: isSandbox ? Colors.orange.shade700 : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
