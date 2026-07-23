import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';

class OrderStatusSheet extends ConsumerStatefulWidget {
  const OrderStatusSheet({
    super.key,
    required this.order,
    required this.isOwner,
  });

  final Order order;
  final bool isOwner;

  @override
  ConsumerState<OrderStatusSheet> createState() => _OrderStatusSheetState();
}

class _OrderStatusSheetState extends ConsumerState<OrderStatusSheet> {
  bool _loading = false;

  Future<void> _ownerAction(String status) async {
    setState(() => _loading = true);
    try {
      await ref.read(ownerOrdersProvider.notifier).updateStatus(widget.order.id, status);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        context.showError(sanitizeErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _consumerCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Your payment will be refunded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await ref.read(myOrdersProvider.notifier).cancel(widget.order.id);
      if (mounted) Navigator.of(context).pop(true);
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
    final order = widget.order;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
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
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.isOwner
                                ? (order.consumerName ?? 'Customer')
                                : (order.truckName ?? 'Order'),
                            style: AppTextStyles.heading3,
                          ),
                        ),
                        _StatusChip(status: order.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(order.createdAt),
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Items
                    Text('Items', style: AppTextStyles.label),
                    const SizedBox(height: AppSpacing.sm),
                    ...order.items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.quantity}×', style: AppTextStyles.caption),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: AppTextStyles.body),
                                    if (item.removedModifiers.isNotEmpty ||
                                        item.addedModifiers.isNotEmpty ||
                                        item.selectedGroupOptions.isNotEmpty)
                                      Text(
                                        [
                                          ...item.removedModifiers.map((m) => 'No $m'),
                                          ...item.addedModifiers.map((m) => '+ ${m.name}'),
                                          ...item.selectedGroupOptions.values.map((m) => m.name),
                                        ].join(', '),
                                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                                      ),
                                    if (item.specialRequest != null && item.specialRequest!.isNotEmpty)
                                      Text(
                                        'Note: ${item.specialRequest}',
                                        style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${item.lineTotal.toStringAsFixed(2)}',
                                style: AppTextStyles.body,
                              ),
                            ],
                          ),
                        )),
                    const Divider(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: AppTextStyles.label),
                        Text(
                          '\$${order.totalPrice.toStringAsFixed(2)}',
                          style: AppTextStyles.label,
                        ),
                      ],
                    ),

                    if (order.pickupNote != null && order.pickupNote!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text('Pickup Note', style: AppTextStyles.label),
                      const SizedBox(height: 4),
                      Text(order.pickupNote!, style: AppTextStyles.body),
                    ],

                    const SizedBox(height: AppSpacing.xl),

                    // Actions
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (widget.isOwner) ...[
                      if (order.isPending) ...[
                        FilledButton(
                          onPressed: () => _ownerAction('accepted'),
                          child: const Text('Start Preparing'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _ownerAction('declined'),
                          child: const Text('Decline & Refund'),
                        ),
                      ] else if (order.status == 'accepted') ...[
                        FilledButton(
                          onPressed: () => _ownerAction('ready'),
                          child: const Text('Mark Ready for Pickup'),
                        ),
                      ] else if (order.status == 'ready') ...[
                        FilledButton(
                          onPressed: () => _ownerAction('completed'),
                          child: const Text('Mark Completed'),
                        ),
                      ],
                    ] else if (!widget.isOwner && order.isPending) ...[
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _consumerCancel,
                        child: const Text('Cancel Order'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('Pending', Colors.orange),
      'accepted' => ('Preparing', Colors.blue),
      'ready' => ('Ready!', Colors.green),
      'completed' => ('Completed', AppColors.textHint),
      'declined' => ('Declined', Colors.red),
      'cancelled' => ('Cancelled', Colors.red),
      _ => (status, AppColors.textHint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
