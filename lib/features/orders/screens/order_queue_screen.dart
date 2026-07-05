import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../widgets/order_status_sheet.dart';

class OrderQueueScreen extends ConsumerWidget {
  const OrderQueueScreen({super.key, this.truckId});

  // When provided (e.g. by an employee), skips the ownerTruckProvider lookup.
  final String? truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (truckId != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Order Queue'),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: _OrderQueueList(truckId: truckId!),
      );
    }
    final asyncTruck = ref.watch(ownerTruckProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Queue'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) return const Center(child: Text('No truck found.'));
          return _OrderQueueList(truckId: truck.id);
        },
      ),
    );
  }
}

class _OrderQueueList extends ConsumerStatefulWidget {
  const _OrderQueueList({required this.truckId});
  final String truckId;

  @override
  ConsumerState<_OrderQueueList> createState() => _OrderQueueListState();
}

class _OrderQueueListState extends ConsumerState<_OrderQueueList> with WidgetsBindingObserver {
  RealtimeChannel? _channel;
  bool _doneExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerOrdersProvider.notifier).load(widget.truckId);
    });
    _channel = Supabase.instance.client
        .channel('owner-orders-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) => ref.read(ownerOrdersProvider.notifier).load(widget.truckId),
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(ownerOrdersProvider.notifier).load(widget.truckId);
    }
  }

  void _openSheet(Order order) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderStatusSheet(order: order, isOwner: true),
    );
    if (!mounted) return;
    if (result == true) {
      ref.read(ownerOrdersProvider.notifier).load(widget.truckId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncOrders = ref.watch(ownerOrdersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.read(ownerOrdersProvider.notifier).load(widget.truckId),
      child: asyncOrders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (orders) {
          final incoming = orders.where((o) => o.status == 'pending').toList();
          final inProgress = orders.where((o) => o.status == 'accepted' || o.status == 'ready').toList();
          final done = orders.where((o) => o.isTerminal).toList();

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
                  const SizedBox(height: AppSpacing.md),
                  Text('No orders yet', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Orders will appear here in real time', style: AppTextStyles.caption),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (incoming.isNotEmpty) ...[
                _SectionHeader('Incoming (${incoming.length})'),
                const SizedBox(height: AppSpacing.sm),
                ...incoming.map((o) => _OrderCard(order: o, onTap: () => _openSheet(o))),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (inProgress.isNotEmpty) ...[
                _SectionHeader('In Progress (${inProgress.length})'),
                const SizedBox(height: AppSpacing.sm),
                ...inProgress.map((o) => _OrderCard(order: o, onTap: () => _openSheet(o))),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (done.isNotEmpty) ...[
                Semantics(
                  label: _doneExpanded ? 'Collapse Done section' : 'Expand Done section',
                  button: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _doneExpanded = !_doneExpanded),
                    child: Row(
                      children: [
                        _SectionHeader('Done (${done.length})'),
                        const Spacer(),
                        Icon(
                          _doneExpanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_doneExpanded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ...done.map((o) => _OrderCard(order: o, onTap: () => _openSheet(o))),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8));
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold(0, (sum, i) => sum + i.quantity);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        title: Text(order.consumerName ?? 'Customer', style: AppTextStyles.label),
        subtitle: Text(
          '$itemCount item${itemCount != 1 ? 's' : ''} · \$${order.totalPrice.toStringAsFixed(2)}',
          style: AppTextStyles.caption,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusDot(status: order.status),
            const SizedBox(height: 4),
            Text(_timeAgo(order.createdAt), style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' => Colors.orange,
      'accepted' => Colors.blue,
      'ready' => Colors.green,
      'completed' => AppColors.textHint,
      _ => Colors.red,
    };
    return Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
