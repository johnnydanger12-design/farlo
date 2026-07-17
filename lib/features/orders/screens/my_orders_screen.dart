import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../widgets/order_status_sheet.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> with WidgetsBindingObserver {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _channel = Supabase.instance.client
          .channel('consumer-orders-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'consumer_id',
              value: userId,
            ),
            callback: (_) => _load(),
          )
          .subscribe();
    }
  }

  void _load() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      ref.read(myOrdersProvider.notifier).load(userId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _openSheet(Order order) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderStatusSheet(order: order, isOwner: false),
    );
    if (!mounted) return;
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final asyncOrders = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: asyncOrders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
          data: (orders) {
            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
                    const SizedBox(height: AppSpacing.md),
                    Text('No orders yet', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Orders from local businesses will appear here', style: AppTextStyles.caption),
                  ],
                ),
              );
            }

            final active = orders.where((o) => !o.isTerminal).toList();
            final history = orders.where((o) => o.isTerminal).toList();

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Active'),
                  const SizedBox(height: AppSpacing.sm),
                  ...active.map((o) => _OrderCard(order: o, onTap: () => _openSheet(o))),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (history.isNotEmpty) ...[
                  _SectionHeader('History'),
                  const SizedBox(height: AppSpacing.sm),
                  ...history.map((o) => _OrderCard(order: o, onTap: () => _openSheet(o))),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold(0, (sum, i) => sum + i.quantity);
    final (statusLabel, statusColor) = switch (order.status) {
      'pending' => ('Pending', Colors.orange),
      'accepted' => ('Preparing', Colors.blue),
      'ready' => ('Ready for Pickup!', Colors.green),
      'completed' => ('Completed', AppColors.textHint),
      'declined' => ('Declined', Colors.red),
      'cancelled' => ('Cancelled', Colors.red),
      _ => (order.status, AppColors.textHint),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        title: Text(order.truckName ?? 'Business', style: AppTextStyles.label),
        subtitle: Text(
          '$itemCount item${itemCount != 1 ? 's' : ''} · \$${order.totalPrice.toStringAsFixed(2)}',
          style: AppTextStyles.caption,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(statusLabel, style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(_timeAgo(order.createdAt), style: AppTextStyles.caption),
          ],
        ),
      ),
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
