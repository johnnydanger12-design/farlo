import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/orders_provider.dart';
import 'order_confirmation_screen.dart';

// Landing spot for the receipt email's "View Your Order" deep link
// (farlo://order/<id>, see app_shell.dart's link listener) — fetches the
// order by id (RLS-scoped: only resolves for the order's own consumer or
// the truck's owner/employee) and hands off to the same confirmation
// screen shown right after checkout, rather than building a second display
// for what's functionally the same "here's your order" view.
class OrderLookupScreen extends ConsumerWidget {
  const OrderLookupScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(ordersRepositoryProvider);
    return FutureBuilder(
      future: repo.fetchOrderById(orderId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final order = snapshot.data;
        if (order == null) {
          return Scaffold(
            appBar: AppBar(elevation: 0, surfaceTintColor: Colors.transparent),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Order not found',
                      style: AppTextStyles.heading3,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'This order doesn\'t exist, or isn\'t associated with the account you\'re signed in with.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return OrderConfirmationScreen(order: order);
      },
    );
  }
}
