import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/sign_in_prompt_sheet.dart';
import '../../../services/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/models/food_truck.dart';
import '../../orders/models/order_item.dart';
import '../../orders/providers/orders_provider.dart';
import '../../orders/widgets/order_cart_sheet.dart';
import '../models/menu_item.dart';

// ARCH-4 (code-quality.md): extracted out of the 1425-line truck_profile_screen.dart.

bool tryAddToCart(BuildContext context, WidgetRef ref, CartItem item) {
  if (ref.read(authProvider).asData?.value == null) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignInPromptSheet(),
    );
    return false;
  }
  ref.read(cartProvider.notifier).add(item);
  return true;
}

// Items with no customization options add straight to cart as before. Items
// with any (removable defaults or paid add-ons) go through CustomizeItemSheet
// first — returns whether it was actually added (false if cancelled, or if
// the sign-in prompt was shown instead).
Future<bool> addItemOrCustomize(BuildContext context, WidgetRef ref, MenuItem item) async {
  if (item.modifiers.isEmpty) {
    return tryAddToCart(context, ref, CartItem(
      menuItemId: item.id,
      name: item.name,
      price: item.price,
      quantity: 1,
    ));
  }
  final cartItem = await showModalBottomSheet<CartItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CustomizeItemSheet(item: item),
  );
  if (cartItem == null || !context.mounted) return false;
  return tryAddToCart(context, ref, cartItem);
}

class MenuGrid extends StatefulWidget {
  const MenuGrid({super.key, required this.items, required this.canOrder, this.categoryOrder = const []});
  final List<MenuItem> items;
  final bool canOrder;
  // Owner-defined category order (FoodTruck.orderedCategoryNames) — shares
  // the same source of truth as the owner's manage-menu screen so the two
  // never disagree on category order. Falls back to first-appearance order
  // (via LinkedHashMap insertion order) for any category not included here.
  final List<String> categoryOrder;

  @override
  State<MenuGrid> createState() => _MenuGridState();
}

class _MenuGridState extends State<MenuGrid> {
  late Map<String, bool> _expanded;

  Map<String, List<MenuItem>> _buildCategories() {
    final map = <String, List<MenuItem>>{};
    for (final item in widget.items.where((i) => i.isAvailable)) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    final ordered = <String, List<MenuItem>>{};
    for (final name in widget.categoryOrder) {
      if (map.containsKey(name)) ordered[name] = map[name]!;
    }
    for (final entry in map.entries) {
      ordered.putIfAbsent(entry.key, () => entry.value);
    }
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _expanded = {for (final k in _buildCategories().keys) k: false};
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: categories.entries.map((entry) {
        final isExpanded = _expanded[entry.key] ?? true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CategoryHeader(
              name: entry.key,
              itemCount: entry.value.length,
              isExpanded: isExpanded,
              onTap: () => setState(() => _expanded[entry.key] = !isExpanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: entry.value.length,
                          itemBuilder: (_, i) =>
                              MenuItemCard(item: entry.value[i], canOrder: widget.canOrder),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      }).toList(),
    );
  }
}

class CategoryHeader extends StatelessWidget {
  const CategoryHeader({
    super.key,
    required this.name,
    required this.itemCount,
    required this.isExpanded,
    required this.onTap,
  });
  final String name;
  final int itemCount;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(name, style: AppTextStyles.label.copyWith(color: primary)),
            ),
            if (!isExpanded)
              Text('$itemCount item${itemCount == 1 ? '' : 's'}',
                  style: AppTextStyles.caption.copyWith(color: primary)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: isExpanded ? 0 : -0.5,
              duration: const Duration(milliseconds: 220),
              child: Icon(Icons.keyboard_arrow_up, color: primary, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuItemCard extends ConsumerWidget {
  const MenuItemCard({super.key, required this.item, required this.canOrder});
  final MenuItem item;
  final bool canOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cartProvider); // rebuild on cart changes
    final qty = canOrder ? ref.read(cartProvider.notifier).quantityForMenuItem(item.id) : 0;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ItemDetailSheet(item: item, canOrder: canOrder),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: item.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: transformedImageUrl(item.imageUrl!, width: 400),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, _, _) => const NoPhotoPlaceholder(),
                      )
                    : const NoPhotoPlaceholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.priceDisplay,
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                      if (canOrder)
                        AddButton(item: item, qty: qty),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoPhotoPlaceholder extends StatelessWidget {
  const NoPhotoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      child: const Center(child: Icon(Icons.restaurant_menu_outlined, color: AppColors.textHint, size: 32)),
    );
  }
}

class AddButton extends ConsumerWidget {
  const AddButton({super.key, required this.item, required this.qty});
  final MenuItem item;
  final int qty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      label: qty == 0 ? 'Add ${item.name} to order' : 'Add another ${item.name}, $qty in order',
      button: true,
      child: GestureDetector(
        onTap: () => addItemOrCustomize(context, ref, item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: qty == 0
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: qty == 0
              ? const Icon(Icons.add, size: 14, color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text('$qty',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}

class ItemDetailSheet extends StatelessWidget {
  const ItemDetailSheet({super.key, required this.item, required this.canOrder});
  final MenuItem item;
  final bool canOrder;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: CachedNetworkImage(
                imageUrl: transformedImageUrl(item.imageUrl!, height: 400),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(item.name, style: AppTextStyles.heading3)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(item.priceDisplay,
                        style: AppTextStyles.heading3.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(item.description!, style: AppTextStyles.body),
                ],
                if (canOrder) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Consumer(
                    builder: (context, ref, _) {
                      ref.watch(cartProvider); // rebuild on cart changes
                      final qty = ref.read(cartProvider.notifier).quantityForMenuItem(item.id);
                      return FilledButton.icon(
                        onPressed: () async {
                          final added = await addItemOrCustomize(context, ref, item);
                          if (added && context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                        label: Text(qty == 0 ? 'Add to Bag' : 'Add One More'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      );
                    },
                  ),
                ],
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + AppSpacing.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloatingCartBar extends ConsumerWidget {
  const FloatingCartBar({super.key, required this.truck});
  final FoodTruck truck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(cartProvider.notifier);
    final total = notifier.total;
    final count = notifier.totalQuantity;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
        child: FilledButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => OrderCartSheet(truck: truck),
            );
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$count',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const Text('View Bag',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              Text('\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

// Shown before adding an item that has any customization options — lets a
// customer remove one of the dish's default ingredients (free) or add one of
// its optional paid extras, then adds exactly one of that customization to
// the cart (matching the app's existing one-tap-per-add convention; tapping
// "Add" again for the same dish opens this sheet fresh rather than assuming
// the same customization is wanted twice).
class CustomizeItemSheet extends StatefulWidget {
  const CustomizeItemSheet({super.key, required this.item});
  final MenuItem item;

  @override
  State<CustomizeItemSheet> createState() => _CustomizeItemSheetState();
}

class _CustomizeItemSheetState extends State<CustomizeItemSheet> {
  final Set<String> _removedNames = {};
  final Set<String> _addedIds = {};

  double get _total {
    final addedTotal = widget.item.paidAddOns
        .where((m) => _addedIds.contains(m.id))
        .fold(0.0, (sum, m) => sum + m.priceDelta);
    return widget.item.price + addedTotal;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(widget.item.name, style: AppTextStyles.heading3)),
                  Text(
                    '\$${_total.toStringAsFixed(2)}',
                    style: AppTextStyles.heading3.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
              if (widget.item.removableDefaults.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Comes with', style: AppTextStyles.label),
                for (final modifier in widget.item.removableDefaults)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(modifier.name),
                    value: !_removedNames.contains(modifier.name),
                    onChanged: (checked) => setState(() {
                      if (checked ?? true) {
                        _removedNames.remove(modifier.name);
                      } else {
                        _removedNames.add(modifier.name);
                      }
                    }),
                  ),
              ],
              if (widget.item.paidAddOns.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Add extras', style: AppTextStyles.label),
                for (final modifier in widget.item.paidAddOns)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${modifier.name} (+\$${modifier.priceDelta.toStringAsFixed(2)})'),
                    value: _addedIds.contains(modifier.id),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _addedIds.add(modifier.id);
                      } else {
                        _addedIds.remove(modifier.id);
                      }
                    }),
                  ),
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    final addedModifiers = widget.item.paidAddOns
                        .where((m) => _addedIds.contains(m.id))
                        .map((m) => SelectedModifier(id: m.id, name: m.name, priceDelta: m.priceDelta))
                        .toList();
                    Navigator.pop(
                      context,
                      CartItem(
                        menuItemId: widget.item.id,
                        name: widget.item.name,
                        price: widget.item.price,
                        quantity: 1,
                        removedModifiers: _removedNames.toList(),
                        addedModifiers: addedModifiers,
                      ),
                    );
                  },
                  child: const Text('Add to Bag'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
