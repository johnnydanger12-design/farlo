import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../food_trucks/models/menu_item.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class ManageMenuScreen extends ConsumerWidget {
  const ManageMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => asyncTruck.asData?.value != null
                ? _showAddSheet(context, ref, asyncTruck.asData!.value!.id,
                    asyncTruck.asData!.value!.menuItems.length)
                : null,
          ),
        ],
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (truck) {
          if (truck == null) return const Center(child: Text('No truck found.'));
          if (truck.menuItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.restaurant_menu_outlined, size: 56, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text('No menu items yet', style: AppTextStyles.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  TextButton.icon(
                    onPressed: () => _showAddSheet(context, ref, truck.id, 0),
                    icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                    label: Text('Add your first item',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: truck.menuItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _MenuItemTile(
              item: truck.menuItems[i],
              onEdit: () => _showEditSheet(context, ref, truck.menuItems[i]),
              onDelete: () => _confirmDelete(context, ref, truck.menuItems[i].id),
            ),
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref, String truckId, int nextSort) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MenuItemSheet(
        truckId: truckId,
        nextSortOrder: nextSort,
        onSave: (name, desc, price, category) async {
          await ref.read(foodTruckRepositoryProvider).addMenuItem(
            truckId,
            name: name,
            description: desc.isEmpty ? null : desc,
            price: price,
            category: category,
            sortOrder: nextSort,
          );
          await ref.read(ownerTruckProvider.notifier).refresh();
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, MenuItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MenuItemSheet(
        truckId: item.truckId,
        nextSortOrder: item.sortOrder,
        existing: item,
        onSave: (name, desc, price, category) async {
          await ref.read(foodTruckRepositoryProvider).updateMenuItem(item.id, {
            'name': name,
            'description': desc.isEmpty ? null : desc,
            'price': price,
            'category': category,
          });
          await ref.read(ownerTruckProvider.notifier).refresh();
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, String itemId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(foodTruckRepositoryProvider).deleteMenuItem(itemId);
      await ref.read(ownerTruckProvider.notifier).refresh();
    }
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.onEdit, required this.onDelete});

  final MenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
        title: Text(item.name, style: AppTextStyles.label),
        subtitle: Text(
          '${item.category} · ${item.priceDisplay}',
          style: AppTextStyles.caption,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppColors.textSecondary,
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemSheet extends StatefulWidget {
  const _MenuItemSheet({
    required this.truckId,
    required this.nextSortOrder,
    required this.onSave,
    this.existing,
  });

  final String truckId;
  final int nextSortOrder;
  final MenuItem? existing;
  final Future<void> Function(String name, String desc, double price, String category) onSave;

  @override
  State<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<_MenuItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  String _category = 'Mains';
  bool _saving = false;

  static const List<String> _categories = [
    'Mains', 'Sides', 'Drinks', 'Desserts', 'Specials',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _priceCtrl = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.price.toStringAsFixed(2)
          : '',
    );
    _category = widget.existing?.category ?? 'Mains';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _nameCtrl.text.trim(),
        _descCtrl.text.trim(),
        double.parse(_priceCtrl.text.trim()),
        _category,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null ? 'Add Menu Item' : 'Edit Menu Item',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration('Item Name', context),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDecoration('Description (optional)', context),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      decoration: _inputDecoration('Price', context),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Invalid price';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: _inputDecoration('Category', context),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v ?? _category),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: widget.existing == null ? 'Add Item' : 'Save Changes',
                onPressed: _saving ? null : _submit,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, BuildContext context) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
