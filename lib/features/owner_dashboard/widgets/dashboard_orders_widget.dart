import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../orders/models/order.dart';
import '../providers/dashboard_providers.dart';

class DashboardOrdersWidget extends ConsumerStatefulWidget {
  const DashboardOrdersWidget({super.key, required this.truckId});
  final String truckId;

  @override
  ConsumerState<DashboardOrdersWidget> createState() => _DashboardOrdersWidgetState();
}

class _DashboardOrdersWidgetState extends ConsumerState<DashboardOrdersWidget> {
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _ordersChannel = Supabase.instance.client
        .channel('dashboard-orders-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) =>
              ref.invalidate(activeOrdersProvider(widget.truckId)),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_ordersChannel != null) {
      Supabase.instance.client.removeChannel(_ordersChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(activeOrdersProvider(widget.truckId));
    final orders = ordersAsync.asData?.value ?? [];
    final incoming = orders.where((o) => o.status == 'pending').toList();
    final inProgress = orders
        .where((o) => o.status == 'accepted' || o.status == 'ready')
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — tappable to go to orders screen
          GestureDetector(
            onTap: () => context.go('/dashboard/orders'),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Orders', style: AppTextStyles.label)),
                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                ],
              ),
            ),
          ),
          // Order rows
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: ordersAsync.isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : orders.isEmpty
                    ? Text('No active orders', style: AppTextStyles.bodySmall)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (incoming.isNotEmpty) ...[
                            _OrderSectionLabel(
                                'Incoming (${incoming.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...incoming.map((o) => _DashboardOrderRow(
                                order: o,
                                onTap: () =>
                                    context.go('/dashboard/orders'))),
                          ],
                          if (inProgress.isNotEmpty) ...[
                            if (incoming.isNotEmpty)
                              const SizedBox(height: AppSpacing.md),
                            _OrderSectionLabel(
                                'In Progress (${inProgress.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...inProgress.map((o) => _DashboardOrderRow(
                                order: o,
                                onTap: () =>
                                    context.go('/dashboard/orders'))),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _OrderSectionLabel extends StatelessWidget {
  const _OrderSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}

class _DashboardOrderRow extends StatelessWidget {
  const _DashboardOrderRow({required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold(0, (sum, i) => sum + i.quantity);
    final statusColor = switch (order.status) {
      'pending' => Colors.orange,
      'accepted' => AppColors.primary,
      'ready' => AppColors.openGreen,
      _ => AppColors.textHint,
    };
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$itemCount item${itemCount != 1 ? 's' : ''} · \$${order.totalPrice.toStringAsFixed(2)}',
                style: AppTextStyles.bodySmall,
              ),
            ),
            Text(
              switch (order.status) {
                'pending' => 'New',
                'accepted' => 'Accepted',
                'ready' => 'Ready',
                _ => order.status,
              },
              style: AppTextStyles.caption
                  .copyWith(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
