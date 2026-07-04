import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../map/models/food_truck.dart';
import '../models/order_item.dart';
import '../providers/orders_provider.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../repositories/orders_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A random per-attempt key, not a cryptographic identifier — only needs to
/// be unique enough to scope one checkout attempt to Stripe. Avoids adding a
/// `uuid` package dependency for this one use.
String _generateIdempotencyKey() {
  final rand = Random.secure();
  return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
}

class OrderCartSheet extends ConsumerStatefulWidget {
  const OrderCartSheet({super.key, required this.truck});
  final FoodTruck truck;

  @override
  ConsumerState<OrderCartSheet> createState() => _OrderCartSheetState();
}

class _OrderCartSheetState extends ConsumerState<OrderCartSheet> {
  final _pickupNoteCtrl = TextEditingController();
  bool _paying = false;

  // Generated once per checkout attempt and reused across retries of that
  // same attempt (network blip, user re-tapping Pay after an error) so the
  // server can recognize a retry and avoid double-charging (bugs.md
  // Executive Summary #3). Reset only after a successful order placement.
  String? _idempotencyKey;

  @override
  void dispose() {
    _pickupNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final items = cartNotifier.items;
    if (items.isEmpty) return;

    // Captured before the (potentially long, 3DS-involving) Stripe flow
    // rather than re-read from auth.currentUser afterward, so a session
    // hiccup during that flow can't throw a null-check crash right after a
    // successful charge (bugs.md's stranded-charge root cause).
    final consumerId = Supabase.instance.client.auth.currentUser?.id;
    if (consumerId == null) {
      context.showError('Please sign in again to complete this order.');
      return;
    }

    _idempotencyKey ??= _generateIdempotencyKey();

    setState(() => _paying = true);
    try {
      final repo = OrdersRepository(Supabase.instance.client);

      // 1. Create PaymentIntent server-side (amount is recomputed from real
      // menu prices there, not trusted from the client cart total)
      final (:clientSecret, :paymentIntentId) = await repo.createPaymentIntent(
        truckId: widget.truck.id,
        items: items,
        idempotencyKey: _idempotencyKey!,
      );

      // 2. Init + present Stripe PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Farlo',
          style: Theme.of(context).brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // 3. Payment succeeded — place order in DB. Idempotent by
      // paymentIntentId, so if this step is what fails and the user retries,
      // step 1 returns the same PaymentIntent (same idempotency key) and this
      // step recognizes the already-charged intent instead of erroring or
      // double-booking.
      final order = await repo.placeOrder(
        truckId: widget.truck.id,
        consumerId: consumerId,
        items: items,
        pickupNote: _pickupNoteCtrl.text.trim().isEmpty ? null : _pickupNoteCtrl.text.trim(),
        paymentIntentId: paymentIntentId,
      );

      cartNotifier.clear();
      _idempotencyKey = null;

      if (mounted) {
        Navigator.of(context).pop(order);
      }
    } on StripeException catch (e) {
      // User cancelled or card declined — Stripe already showed the error
      if (e.error.code != FailureCode.Canceled && mounted) {
        context.showError(e.error.localizedMessage ?? 'Payment failed');
      }
    } catch (e) {
      if (mounted) {
        context.showError(
          'Your payment may have gone through, but we couldn\'t confirm your order. '
          'Please check "My Orders" before trying again, or contact support if this repeats.',
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final total = cartNotifier.total;
    final hasItems = cart.isNotEmpty;
    final cartItems = cart.values.toList();
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(child: Text('Your Bag', style: AppTextStyles.heading3)),
                    Text(widget.truck.name, style: AppTextStyles.caption),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: !hasItems
                    ? Center(child: Text('Your bag is empty', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)))
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 120),
                        children: [
                          ...cartItems.map((ci) => _CartItemRow(cartItem: ci)),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: TextField(
                              controller: _pickupNoteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Pickup note (optional)',
                                hintText: 'e.g. allergies, extra napkins…',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md + bottomPad),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: (!hasItems || _paying) ? null : _pay,
                    child: _paying
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            hasItems ? 'Place Order · \$${total.toStringAsFixed(2)}' : 'Add items to order',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartItemRow extends ConsumerWidget {
  const _CartItemRow({required this.cartItem});
  final CartItem cartItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => notifier.remove(cartItem.menuItemId),
            child: Icon(
              cartItem.quantity == 1 ? Icons.delete_outline : Icons.remove_circle_outline,
              size: 20,
              color: cartItem.quantity == 1 ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Text('${cartItem.quantity}', style: AppTextStyles.label),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => notifier.add(cartItem),
            child: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(cartItem.name, style: AppTextStyles.bodySmall)),
          Text('\$${cartItem.lineTotal.toStringAsFixed(2)}',
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

