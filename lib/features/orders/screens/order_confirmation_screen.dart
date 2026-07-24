import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/widgets/truck_display_widgets.dart';
import '../models/order.dart';
import '../models/order_item.dart';

// Shown right after a successful checkout (order_cart_sheet.dart) — a
// dedicated full-screen confirmation rather than just closing the cart sheet,
// so a customer has something concrete to look at (pickup code, what they
// ordered) instead of just landing back on the menu wondering if it worked.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.order});
  final Order order;

  String _itemLabel(OrderItem item) {
    final mods = [
      ...item.removedModifiers.map((m) => 'No $m'),
      ...item.addedModifiers.map((m) => '+ ${m.name}'),
      ...item.selectedGroupOptions.values.map((m) => m.name),
    ];
    final base = item.quantity > 1 ? '${item.quantity}x ${item.name}' : item.name;
    return mods.isEmpty ? base : '$base (${mods.join(', ')})';
  }

  (String, Color) _statusDisplay() => switch (order.status) {
        'pending' => ('We\'ve got it — waiting on the business to confirm', Colors.orange),
        'accepted' => ('Preparing your order', Colors.blue),
        'ready' => ('Ready for pickup!', Colors.green),
        'completed' => ('Completed', AppColors.textHint),
        'declined' => ('Declined', Colors.red),
        'cancelled' => ('Cancelled', Colors.red),
        _ => (order.status, AppColors.textHint),
      };

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final (statusLabel, statusColor) = _statusDisplay();
    final subtotal = order.totalPrice - order.taxPrice;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Placed'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go('/map'),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: order.truckLogoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: order.truckLogoUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const SizedBox(
                            width: 56,
                            height: 56,
                            child: TruckIconPlaceholder(),
                          ),
                        )
                      : const SizedBox(
                          width: 56,
                          height: 56,
                          child: TruckIconPlaceholder(),
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.truckName ?? 'Your order', style: AppTextStyles.heading2),
                      const SizedBox(height: 2),
                      Text(
                        statusLabel,
                        style: AppTextStyles.bodySmall.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Pickup code — the big, shout-across-the-counter identifier.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    'PICKUP CODE',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    order.pickupCode,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 4, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Order #${order.orderNumber}', style: AppTextStyles.caption),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Your Order', style: AppTextStyles.label),
            const SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Column(
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(_itemLabel(item), style: AppTextStyles.bodySmall)),
                          Text('\$${item.lineTotal.toStringAsFixed(2)}', style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  _totalRow('Subtotal', subtotal),
                  _totalRow('Tax', order.taxPrice),
                  const SizedBox(height: 4),
                  _totalRow('Total', order.totalPrice, bold: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (email != null)
              Text(
                'A receipt will be emailed to $email.',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false}) {
    final style = bold
        ? AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)
        : AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('\$${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
