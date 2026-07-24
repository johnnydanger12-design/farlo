import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../orders/models/order.dart';
import '../../orders/models/order_item.dart';
import '../../orders/providers/orders_provider.dart';
import '../models/menu_item.dart';
import '../models/menu_item_modifier.dart';

// Re-adds a past order's items to the cart using the CURRENT menu — price,
// modifier ids, and availability are always read fresh (never the historical
// snapshot), since a menu can change between orders. A menu item deleted
// since is simply skipped (counted in the return value so the caller can
// tell the customer); a required-choice group that can't be matched back to
// the old selection (renamed/removed option, or a group that's new since)
// falls back to that group's own current default, exactly like opening
// CustomizeItemSheet fresh and touching nothing.
int reorderPastOrder(WidgetRef ref, Order order, List<MenuItem> currentMenuItems) {
  final menuById = {for (final m in currentMenuItems) m.id: m};
  var skipped = 0;
  for (final oldItem in order.items) {
    final menuItem = oldItem.menuItemId == null ? null : menuById[oldItem.menuItemId];
    if (menuItem == null) {
      skipped++;
      continue;
    }

    final removed = oldItem.removedModifiers
        .where((name) => menuItem.removableDefaults.any((m) => m.name == name))
        .toList();

    final added = [
      for (final old in oldItem.addedModifiers)
        if (menuItem.paidAddOns.where((m) => m.name == old.name).firstOrNull case final m?)
          SelectedModifier(id: m.id, name: m.name, priceDelta: m.priceDelta),
    ];

    final selectedGroups = <String, SelectedModifier>{
      for (final group in menuItem.groupedModifiers.entries)
        group.key: _resolveGroupChoice(group.value, oldItem.selectedGroupOptions[group.key]),
    };

    for (var i = 0; i < oldItem.quantity; i++) {
      ref.read(cartProvider.notifier).add(CartItem(
            menuItemId: menuItem.id,
            name: menuItem.name,
            price: menuItem.price,
            quantity: 1,
            removedModifiers: removed,
            addedModifiers: added,
            selectedGroupOptions: selectedGroups,
          ));
    }
  }
  return skipped;
}

SelectedModifier _resolveGroupChoice(
  List<MenuItemModifier> currentOptions,
  SelectedModifier? oldChoice,
) {
  final matched = oldChoice == null
      ? null
      : currentOptions.where((m) => m.name == oldChoice.name).firstOrNull;
  final chosen = matched ??
      currentOptions.firstWhere((m) => m.includedByDefault, orElse: () => currentOptions.first);
  return SelectedModifier(id: chosen.id, name: chosen.name, priceDelta: chosen.priceDelta);
}

// Caller (truck_profile_screen.dart) decides whether to mount this at all —
// same convention as MenuGrid taking pre-fetched categoryAvailability rather
// than watching its own provider — so an empty order history never leaves a
// bare "Order Again" section title with nothing underneath it.
class OrderAgainSection extends StatelessWidget {
  const OrderAgainSection({
    super.key,
    required this.orders,
    required this.currentMenuItems,
    required this.truckId,
  });
  final List<Order> orders;
  final List<MenuItem> currentMenuItems;
  final String truckId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => _OrderAgainCard(
          order: orders[i],
          currentMenuItems: currentMenuItems,
          truckId: truckId,
        ),
      ),
    );
  }
}

class _OrderAgainCard extends ConsumerWidget {
  const _OrderAgainCard({required this.order, required this.currentMenuItems, required this.truckId});
  final Order order;
  final List<MenuItem> currentMenuItems;
  final String truckId;

  // Matches the "+ X" / "No X" summary convention already used on the cart
  // sheet and order status sheet — without the customization, two past
  // orders of the same base item (different cheese, say) would look
  // identical on this card.
  String _itemLabel(OrderItem item) {
    final mods = [
      ...item.removedModifiers.map((m) => 'No $m'),
      ...item.addedModifiers.map((m) => '+ ${m.name}'),
      ...item.selectedGroupOptions.values.map((m) => m.name),
    ];
    return mods.isEmpty ? item.name : '${item.name} (${mods.join(', ')})';
  }

  String get _itemsSummary {
    final labels = order.items.map(_itemLabel).toList();
    if (labels.length <= 2) return labels.join(', ');
    return '${labels.take(2).join(', ')} +${labels.length - 2} more';
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    // Optimistic-feeling: the shelf refetches right after, so the card is
    // just gone rather than needing its own local removal animation.
    try {
      await ref.read(ordersRepositoryProvider).hideFromOrderAgain(order.id);
      ref.invalidate(recentOrdersAtTruckProvider(truckId));
    } catch (_) {
      if (context.mounted) context.showError('Couldn\'t remove that — try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // Room for the dismiss button so it never overlaps the text.
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: Text(
                  _itemsSummary,
                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('\$${order.totalPrice.toStringAsFixed(2)}', style: AppTextStyles.caption),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      final skipped = reorderPastOrder(ref, order, currentMenuItems);
                      if (skipped == order.items.length) {
                        context.showInfo('Those items are no longer on the menu');
                      } else if (skipped > 0) {
                        context.showSuccess('Added to bag — $skipped item(s) no longer available');
                      } else {
                        context.showSuccess('Added to bag');
                      }
                    },
                    child: const Text('Reorder'),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove from Order Again',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              color: AppColors.textSecondary,
              onPressed: () => _dismiss(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
