import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

String _formatRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

class OrdersPaymentsScreen extends ConsumerStatefulWidget {
  const OrdersPaymentsScreen({super.key});

  @override
  ConsumerState<OrdersPaymentsScreen> createState() => _OrdersPaymentsScreenState();
}

class _OrdersPaymentsScreenState extends ConsumerState<OrdersPaymentsScreen> {
  late final TextEditingController _taxRateCtrl;
  late final TextEditingController _autoMarkReadyDelayCtrl;
  late final TextEditingController _autoMarkCompleteDelayCtrl;

  bool _ordersEnabled = false;
  bool _autoAcceptOrders = false;
  bool _autoMarkReady = false;
  bool _autoMarkComplete = false;
  bool _loading = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _taxRateCtrl = TextEditingController();
    _autoMarkReadyDelayCtrl = TextEditingController();
    _autoMarkCompleteDelayCtrl = TextEditingController();
    // Rebuilds so the toggle's own subtitle reflects the delay live as it's
    // typed, rather than only being visible in the text field below it.
    _autoMarkReadyDelayCtrl.addListener(() => setState(() {}));
    _autoMarkCompleteDelayCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _taxRateCtrl.dispose();
    _autoMarkReadyDelayCtrl.dispose();
    _autoMarkCompleteDelayCtrl.dispose();
    super.dispose();
  }

  // Each delay is measured from when the order entered the PRIOR stage, not
  // from placement or acceptance — so with both delays set, they add up
  // sequentially (e.g. ready 5 min after accepted, then completed 20 min
  // after THAT, not 20 min after accepted). The "from" clause makes that
  // explicit so it's never ambiguous whether these fire in parallel.
  String _readyDelaySubtitle(TextEditingController delayCtrl) {
    final minutes = int.tryParse(delayCtrl.text.trim()) ?? 0;
    return minutes > 0 ? 'Ready $minutes min after being accepted' : 'Ready immediately after being accepted';
  }

  String _completeDelaySubtitle(TextEditingController delayCtrl) {
    final minutes = int.tryParse(delayCtrl.text.trim()) ?? 0;
    return minutes > 0 ? 'Completed $minutes min after being marked ready' : 'Completed immediately after being marked ready';
  }

  void _initFromTruck() {
    if (_initialized) return;
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    _taxRateCtrl.text = truck.taxRatePercent == null ? '' : _formatRate(truck.taxRatePercent!);
    _ordersEnabled = truck.ordersEnabled;
    _autoAcceptOrders = truck.autoAcceptOrders;
    _autoMarkReady = truck.autoMarkReady;
    _autoMarkReadyDelayCtrl.text = truck.autoMarkReadyDelayMinutes.toString();
    _autoMarkComplete = truck.autoMarkComplete;
    _autoMarkCompleteDelayCtrl.text = truck.autoMarkCompleteDelayMinutes.toString();
    _initialized = true;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final fields = <String, dynamic>{
        'orders_enabled': _ordersEnabled,
        'tax_rate_percent': _taxRateCtrl.text.trim().isEmpty ? null : double.tryParse(_taxRateCtrl.text.trim()),
        'auto_accept_orders': _autoAcceptOrders,
        'auto_mark_ready': _autoMarkReady,
        'auto_mark_ready_delay_minutes': int.tryParse(_autoMarkReadyDelayCtrl.text.trim()) ?? 0,
        'auto_mark_complete': _autoMarkComplete,
        'auto_mark_complete_delay_minutes': int.tryParse(_autoMarkCompleteDelayCtrl.text.trim()) ?? 0,
      };
      await ref.read(ownerTruckProvider.notifier).updateProfile(fields);
      if (mounted) {
        context.showSuccess('Saved!', duration: const Duration(seconds: 2), backgroundColor: AppColors.openGreen);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Could not save: ${sanitizeErrorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTruck = ref.watch(ownerTruckProvider);
    _initFromTruck();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders & Payments'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Ahead toggle
              Text('Order Ahead', style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text('Let customers order and pay directly. Requires an active subscription and a connected Stripe account.', style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _ordersEnabled,
                onChanged: (val) => setState(() => _ordersEnabled = val),
                title: const Text('Accept orders'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Order automation — independent toggles for each stage of
              // pending -> Preparing -> ready -> completed, plus a master
              // switch that's just a convenience for setting all three at
              // once (an owner can still fine-tune afterward). For a
              // Clover-integrated business, "accept" gates on a successful
              // print rather than firing the instant the order is placed.
              Text('Order Automation', style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text(
                'Automatically move orders through your queue instead of tapping through each step yourself.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _autoAcceptOrders && _autoMarkReady && _autoMarkComplete,
                onChanged: (val) => setState(() {
                  _autoAcceptOrders = val;
                  _autoMarkReady = val;
                  _autoMarkComplete = val;
                }),
                title: const Text('Automate my whole order flow'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _autoAcceptOrders,
                onChanged: (val) => setState(() => _autoAcceptOrders = val),
                title: const Text('Auto-accept new orders'),
                subtitle: const Text('Starts preparing automatically instead of tapping "Start Preparing"'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _autoMarkReady,
                onChanged: (val) => setState(() => _autoMarkReady = val),
                title: const Text('Auto-mark ready for pickup'),
                subtitle: _autoMarkReady ? Text(_readyDelaySubtitle(_autoMarkReadyDelayCtrl)) : null,
                contentPadding: EdgeInsets.zero,
              ),
              if (_autoMarkReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppTextField(
                    controller: _autoMarkReadyDelayCtrl,
                    label: 'Delay (minutes)',
                    hint: '0 = immediately',
                    keyboardType: TextInputType.number,
                  ),
                ),
              SwitchListTile(
                value: _autoMarkComplete,
                onChanged: (val) => setState(() => _autoMarkComplete = val),
                title: const Text('Auto-mark completed'),
                subtitle: _autoMarkComplete ? Text(_completeDelaySubtitle(_autoMarkCompleteDelayCtrl)) : null,
                contentPadding: EdgeInsets.zero,
              ),
              if (_autoMarkComplete)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppTextField(
                    controller: _autoMarkCompleteDelayCtrl,
                    label: 'Delay (minutes)',
                    hint: '0 = immediately',
                    keyboardType: TextInputType.number,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),

              // Sales tax
              Text('Sales Tax', style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text('Your own local rate — added on top of item prices and charged to the customer at checkout. Leave blank for no tax.', style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _taxRateCtrl,
                label: 'Tax rate (%)',
                hint: 'e.g. 8.5',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.xl),

              AppButton(
                label: 'Save Changes',
                onPressed: _loading ? null : _save,
                isLoading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
