import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/parsed_menu_item.dart';

const List<String> _defaultCategories = [
  'Mains', 'Sides', 'Drinks', 'Desserts', 'Specials',
];
const String _otherOption = 'Other…';

// A single editable draft row — mutable state (not a widget), matching the
// category dropdown/custom-text pattern already used in manage_menu_screen's
// _MenuItemSheet, so a parsed category the owner is used to editing behaves
// identically here.
class _DraftRow {
  _DraftRow(ParsedMenuItem item)
      : nameCtrl = TextEditingController(text: item.name),
        descCtrl = TextEditingController(text: item.description ?? ''),
        priceCtrl = TextEditingController(text: item.price > 0 ? item.price.toStringAsFixed(2) : ''),
        isCustomCategory = !_defaultCategories.contains(item.category) {
    dropdownCategory = isCustomCategory ? _otherOption : item.category;
    customCategoryCtrl = TextEditingController(text: isCustomCategory ? item.category : '');
  }

  _DraftRow.blank()
      : nameCtrl = TextEditingController(),
        descCtrl = TextEditingController(),
        priceCtrl = TextEditingController(),
        isCustomCategory = false {
    dropdownCategory = 'Mains';
    customCategoryCtrl = TextEditingController();
  }

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController priceCtrl;
  late String dropdownCategory;
  late final TextEditingController customCategoryCtrl;
  bool isCustomCategory;

  String get effectiveCategory => isCustomCategory ? customCategoryCtrl.text.trim() : dropdownCategory;

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    customCategoryCtrl.dispose();
  }
}

class MenuImportReviewScreen extends ConsumerStatefulWidget {
  const MenuImportReviewScreen({super.key, required this.truckId, required this.parsedItems});

  final String truckId;
  final List<ParsedMenuItem> parsedItems;

  @override
  ConsumerState<MenuImportReviewScreen> createState() => _MenuImportReviewScreenState();
}

class _MenuImportReviewScreenState extends ConsumerState<MenuImportReviewScreen> {
  late List<_DraftRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.parsedItems.map((i) => _DraftRow(i)).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  void _addBlankRow() {
    setState(() => _rows.add(_DraftRow.blank()));
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;

    // Manual validation across the whole (dynamically-sized) list rather than
    // a Form widget — rows are added/removed freely, which doesn't play well
    // with a single Form's key-based validation lifecycle.
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (row.nameCtrl.text.trim().isEmpty) {
        context.showError('Item ${i + 1} needs a name.');
        return;
      }
      if (double.tryParse(row.priceCtrl.text.trim()) == null) {
        context.showError('Item ${i + 1} needs a valid price.');
        return;
      }
      if (row.effectiveCategory.isEmpty) {
        context.showError('Item ${i + 1} needs a category.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final truck = ref.read(ownerTruckProvider).asData?.value;
      if (truck == null) throw Exception('No business found.');

      final startingSortOrder = truck.menuItems.length;
      final items = [
        for (var i = 0; i < _rows.length; i++)
          (
            name: _rows[i].nameCtrl.text.trim(),
            description: _rows[i].descCtrl.text.trim().isEmpty ? null : _rows[i].descCtrl.text.trim(),
            price: double.parse(_rows[i].priceCtrl.text.trim()),
            category: _rows[i].effectiveCategory,
            sortOrder: startingSortOrder + i,
          ),
      ];

      final repo = ref.read(foodTruckRepositoryProvider);
      await repo.bulkAddMenuItems(widget.truckId, items);

      // One ensureCategoryExists call per distinct new category, not per item.
      final distinctCategories = items.map((i) => i.category).toSet();
      var nextCategorySlot = truck.orderedCategoryNames.length;
      for (final category in distinctCategories) {
        await repo.ensureCategoryExists(widget.truckId, category, fallbackSortOrder: nextCategorySlot);
        nextCategorySlot++;
      }

      await ref.read(ownerTruckProvider.notifier).refresh();

      if (mounted) {
        context.showSuccess(
          'Added ${items.length} item${items.length == 1 ? '' : 's'} to your menu',
          backgroundColor: AppColors.openGreen,
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) context.showError('Could not save menu items: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Imported Menu'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(
              'Check each item before saving — edit or remove anything that looks wrong, or add one Claude missed.',
              style: AppTextStyles.caption,
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text('Nothing left to save.', style: AppTextStyles.bodySmall),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _DraftRowCard(row: _rows[i], onRemove: () => _removeRow(i)),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: TextButton.icon(
              onPressed: _addBlankRow,
              icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
              label: Text('Add item manually', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, MediaQuery.of(context).padding.bottom + AppSpacing.md),
            child: AppButton(
              label: 'Save ${_rows.length} item${_rows.length == 1 ? '' : 's'}',
              onPressed: (_saving || _rows.isEmpty) ? null : _save,
              isLoading: _saving,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftRowCard extends StatefulWidget {
  const _DraftRowCard({required this.row, required this.onRemove});

  final _DraftRow row;
  final VoidCallback onRemove;

  @override
  State<_DraftRowCard> createState() => _DraftRowCardState();
}

class _DraftRowCardState extends State<_DraftRowCard> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.nameCtrl,
                  decoration: _decoration('Item Name', context),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.error,
                tooltip: 'Remove this item',
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: row.descCtrl,
            decoration: _decoration('Description (optional)', context),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.priceCtrl,
                  decoration: _decoration('Price', context),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.dropdownCategory,
                  decoration: _decoration('Category', context),
                  items: [
                    ..._defaultCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    const DropdownMenuItem(value: _otherOption, child: Text(_otherOption)),
                  ],
                  onChanged: (v) => setState(() {
                    row.dropdownCategory = v ?? row.dropdownCategory;
                    row.isCustomCategory = v == _otherOption;
                  }),
                ),
              ),
            ],
          ),
          if (row.isCustomCategory) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: row.customCategoryCtrl,
              decoration: _decoration('Category name', context),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, BuildContext context) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
