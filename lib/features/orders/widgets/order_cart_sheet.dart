import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/models/menu_item.dart';
import '../../map/models/food_truck.dart';
import '../models/order_item.dart';
import '../providers/orders_provider.dart';
import '../repositories/orders_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderCartSheet extends ConsumerStatefulWidget {
  const OrderCartSheet({super.key, required this.truck});
  final FoodTruck truck;

  @override
  ConsumerState<OrderCartSheet> createState() => _OrderCartSheetState();
}

class _OrderCartSheetState extends ConsumerState<OrderCartSheet> {
  final _pickupNoteCtrl = TextEditingController();
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    // Clear any stale cart from a previous truck
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _pickupNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final items = cartNotifier.items;
    if (items.isEmpty) return;

    setState(() => _paying = true);
    try {
      final repo = OrdersRepository(Supabase.instance.client);
      final amountCents = (cartNotifier.total * 100).round();

      // 1. Create PaymentIntent server-side
      final (:clientSecret, :paymentIntentId) = await repo.createPaymentIntent(
        truckId: widget.truck.id,
        amountCents: amountCents,
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

      // 3. Payment succeeded — place order in DB
      final order = await repo.placeOrder(
        truckId: widget.truck.id,
        items: items,
        pickupNote: _pickupNoteCtrl.text.trim().isEmpty ? null : _pickupNoteCtrl.text.trim(),
        paymentIntentId: paymentIntentId,
      );

      cartNotifier.clear();

      if (mounted) {
        Navigator.of(context).pop(order);
      }
    } on StripeException catch (e) {
      // User cancelled or card declined — Stripe already showed the error
      if (e.error.code != FailureCode.Canceled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.localizedMessage ?? 'Payment failed'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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

    final availableItems = widget.truck.menuItems.where((i) => i.isAvailable).toList();
    final categories = availableItems.map((i) => i.category).toSet().toList()..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle + title
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Text(
                  'Order from ${widget.truck.name}',
                  style: AppTextStyles.heading3,
                ),
              ),
              const Divider(height: 1),

              // Menu
              Expanded(
                child: availableItems.isEmpty
                    ? Center(
                        child: Text('No menu items available', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 160),
                        children: [
                          for (final category in categories) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                              child: Text(
                                category,
                                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
                              ),
                            ),
                            ...availableItems
                                .where((i) => i.category == category)
                                .map((item) => _MenuItemRow(item: item, cartItem: cart[item.id])),
                          ],

                          // Pickup note
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

              // Sticky bottom bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom,
                ),
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
                            hasItems ? 'Pay \$${total.toStringAsFixed(2)}' : 'Add items to order',
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

class _MenuItemRow extends ConsumerStatefulWidget {
  const _MenuItemRow({required this.item, required this.cartItem});
  final MenuItem item;
  final CartItem? cartItem;

  @override
  ConsumerState<_MenuItemRow> createState() => _MenuItemRowState();
}

class _MenuItemRowState extends ConsumerState<_MenuItemRow> {
  bool _noteExpanded = false;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController(text: widget.cartItem?.specialRequest);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cartItem = widget.cartItem;
    final qty = cartItem?.quantity ?? 0;
    final notifier = ref.read(cartProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(item.name, style: AppTextStyles.label),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.description != null && item.description!.isNotEmpty)
                Text(item.description!, style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(item.priceDisplay, style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          trailing: qty == 0
              ? IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => notifier.add(CartItem(
                    menuItemId: item.id,
                    name: item.name,
                    price: item.price,
                    quantity: 1,
                  )),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        notifier.remove(item.id);
                        if (qty <= 1) setState(() => _noteExpanded = false);
                      },
                    ),
                    Text('$qty', style: AppTextStyles.label),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => notifier.add(CartItem(
                        menuItemId: item.id,
                        name: item.name,
                        price: item.price,
                        quantity: 1,
                      )),
                    ),
                  ],
                ),
        ),

        // Per-item special request
        if (qty > 0) ...[
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => setState(() => _noteExpanded = !_noteExpanded),
              child: Text(
                _noteExpanded ? 'Hide note' : (cartItem?.specialRequest?.isNotEmpty == true ? 'Note: ${cartItem!.specialRequest}' : '+ Add special request'),
                style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
          if (_noteExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. no onions, extra sauce…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) => notifier.setSpecialRequest(item.id, val.trim().isEmpty ? null : val.trim()),
              ),
            ),
        ],
      ],
    );
  }
}
