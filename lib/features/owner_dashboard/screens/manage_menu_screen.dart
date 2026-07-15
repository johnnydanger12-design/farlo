import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../services/storage_service.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/models/menu_item.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../repositories/menu_import_repository.dart';
import 'menu_import_review_screen.dart';

class ManageMenuScreen extends ConsumerWidget {
  const ManageMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
            tooltip: 'Add menu item',
            enabled: asyncTruck.asData?.value != null,
            onSelected: (choice) {
              final truck = asyncTruck.asData?.value;
              if (truck == null) return;
              if (choice == 'manual') {
                _showAddSheet(context, ref, truck.id, truck.menuItems.length);
              } else {
                _showImportOptions(context, ref, truck.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manual', child: Text('Add item manually')),
              PopupMenuItem(value: 'import', child: Text('Import from photo or PDF')),
            ],
          ),
        ],
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (truck) {
          if (truck == null) return const Center(child: Text('No business found.'));
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
                  TextButton.icon(
                    onPressed: () => _showImportOptions(context, ref, truck.id),
                    icon: Icon(Icons.document_scanner_outlined, color: Theme.of(context).colorScheme.primary),
                    label: Text('Import from photo or PDF',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            );
          }
          final grouped = <String, List<MenuItem>>{};
          for (final item in truck.menuItems) {
            grouped.putIfAbsent(item.category, () => []).add(item);
          }
          // Category order comes from the truck's explicit menu_categories
          // order (falling back to first-appearance order for any category
          // not yet registered there), not from grouped's insertion order.
          final orderedCategories = truck.orderedCategoryNames.where((c) => grouped.containsKey(c)).toList();
          final List<Object> rows = [];
          for (final category in orderedCategories) {
            rows.add(category);
            rows.addAll(grouped[category]!);
          }

          Future<void> moveCategory(String category, int delta) async {
            final from = orderedCategories.indexOf(category);
            final to = from + delta;
            if (to < 0 || to >= orderedCategories.length) return;
            final reordered = [...orderedCategories];
            reordered.removeAt(from);
            reordered.insert(to, category);
            await ref.read(foodTruckRepositoryProvider).reorderMenuCategories(truck.id, reordered);
            await ref.read(ownerTruckProvider.notifier).refresh();
          }

          // Items within a category are already ordered by the existing
          // global sort_order integer (menu items across every category share
          // one counter) — moving one up/down just swaps that value with its
          // neighbor *within this category's slice*, no new column needed.
          Future<void> moveItem(MenuItem item, int delta) async {
            final categoryItems = grouped[item.category]!;
            final from = categoryItems.indexOf(item);
            final to = from + delta;
            if (to < 0 || to >= categoryItems.length) return;
            final other = categoryItems[to];
            final repo = ref.read(foodTruckRepositoryProvider);
            await repo.updateMenuItem(item.id, {'sort_order': other.sortOrder});
            await repo.updateMenuItem(other.id, {'sort_order': item.sortOrder});
            await ref.read(ownerTruckProvider.notifier).refresh();
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl,
            ),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final row = rows[i];
              if (row is String) {
                final index = orderedCategories.indexOf(row);
                return _CategoryHeader(
                  category: row,
                  count: grouped[row]!.length,
                  onMoveUp: index > 0 ? () => moveCategory(row, -1) : null,
                  onMoveDown: index < orderedCategories.length - 1 ? () => moveCategory(row, 1) : null,
                );
              }
              final item = row as MenuItem;
              final categoryItems = grouped[item.category]!;
              final itemIndex = categoryItems.indexOf(item);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _MenuItemTile(
                  item: item,
                  onEdit: () => _showEditSheet(context, ref, item),
                  onDelete: () => _confirmDelete(context, ref, item.id),
                  onToggleAvailable: (val) {
                    ref.read(foodTruckRepositoryProvider)
                        .updateMenuItem(item.id, {'is_available': val})
                        .then((_) => ref.read(ownerTruckProvider.notifier).refresh());
                  },
                  onMoveUp: itemIndex > 0 ? () => moveItem(item, -1) : null,
                  onMoveDown: itemIndex < categoryItems.length - 1 ? () => moveItem(item, 1) : null,
                ),
              );
            },
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
        onSave: (name, desc, price, category, imageUrl) async {
          await ref.read(foodTruckRepositoryProvider).addMenuItem(
            truckId,
            name: name,
            description: desc.isEmpty ? null : desc,
            price: price,
            category: category,
            sortOrder: nextSort,
            imageUrl: imageUrl,
          );
          await _registerCategoryIfNew(ref, truckId, category);
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
        onSave: (name, desc, price, category, imageUrl) async {
          await ref.read(foodTruckRepositoryProvider).updateMenuItem(item.id, {
            'name': name,
            'description': desc.isEmpty ? null : desc,
            'price': price,
            'category': category,
            'image_url': imageUrl,
          });
          await _registerCategoryIfNew(ref, item.truckId, category);
          await ref.read(ownerTruckProvider.notifier).refresh();
        },
      ),
    );
  }

  void _showImportOptions(BuildContext context, WidgetRef ref, String truckId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import Menu', style: AppTextStyles.heading3),
            const SizedBox(height: AppSpacing.xs),
            Text('Claude will read the file and draft your menu items — you review and edit before anything is saved.',
                style: AppTextStyles.caption),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.photo_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Choose a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhotoAndImport(context, ref, truckId);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.picture_as_pdf_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Choose a PDF file'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPdfAndImport(context, ref, truckId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotoAndImport(BuildContext context, WidgetRef ref, String truckId) async {
    XFile? xfile;
    try {
      xfile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    } catch (_) {
      // Backing out of the system picker (e.g. a back gesture rather than its
      // own Cancel button) can throw on some platforms instead of cleanly
      // resolving to null — treat any picker-level failure as a cancel.
      return;
    }
    if (xfile == null) return;
    if (context.mounted) await _uploadAndReview(context, ref, truckId, File(xfile.path));
  }

  Future<void> _pickPdfAndImport(BuildContext context, WidgetRef ref, String truckId) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    } catch (_) {
      return;
    }
    final path = result?.files.single.path;
    if (path == null) return;
    if (context.mounted) await _uploadAndReview(context, ref, truckId, File(path));
  }

  Future<void> _uploadAndReview(BuildContext context, WidgetRef ref, String truckId, File file) async {
    // Captured once, before the async gap below — popping/pushing via this
    // stable NavigatorState (rather than repeated Navigator.pop(context)/
    // Navigator.push(context, ...) calls after an await) is what actually
    // guarantees we dismiss the exact loading-dialog route showDialog just
    // pushed, regardless of anything else that happens to `context` while
    // the parse call is in flight.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        // Also blocks the Android hardware back button — otherwise a user
        // backing out of this early would let a later navigator.pop() (once
        // the parse finishes) pop the wrong route instead of this dialog.
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Reading your menu… this can take a minute for longer files.')),
            ],
          ),
        ),
      ),
    );

    try {
      final items = await ref.read(menuImportRepositoryProvider).uploadAndParse(truckId, file);
      if (navigator.canPop()) navigator.pop(); // dismiss loading dialog
      if (!context.mounted) return;

      if (items.isEmpty) {
        context.showError("Couldn't read any items from that file. Try a clearer photo or a higher-resolution scan.");
        return;
      }

      await navigator.push(
        MaterialPageRoute(builder: (_) => MenuImportReviewScreen(truckId: truckId, parsedItems: items)),
      );
    } catch (e) {
      if (navigator.canPop()) navigator.pop(); // dismiss loading dialog
      if (context.mounted) {
        context.showError('Could not import menu: ${sanitizeErrorMessage(e)}');
      }
    }
  }

  // Gives a brand-new (or newly-retyped) category an explicit sort position
  // the first time it's used, appended after whatever categories already
  // exist — a no-op if the category is already registered (ensureCategoryExists
  // ignores conflicts, so an existing category's position is never reset).
  Future<void> _registerCategoryIfNew(WidgetRef ref, String truckId, String category) async {
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    await ref.read(foodTruckRepositoryProvider).ensureCategoryExists(
          truckId,
          category,
          fallbackSortOrder: truck.orderedCategoryNames.length,
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

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.count,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final String category;
  final int count;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(category, style: AppTextStyles.label),
          const SizedBox(width: 6),
          Text(
            '$count ${count == 1 ? 'item' : 'items'}',
            style: AppTextStyles.caption,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            tooltip: 'Move $category up',
            onPressed: onMoveUp,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            tooltip: 'Move $category down',
            onPressed: onMoveDown,
          ),
        ],
      ),
    );
  }
}

class _ReorderArrows extends StatelessWidget {
  const _ReorderArrows({required this.onMoveUp, required this.onMoveDown});

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowButton(icon: Icons.keyboard_arrow_up, onPressed: onMoveUp, tooltip: 'Move up'),
        _ArrowButton(icon: Icons.keyboard_arrow_down, onPressed: onMoveDown, tooltip: 'Move down'),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed, required this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: 16),
        color: AppColors.textSecondary,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAvailable,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final MenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleAvailable;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.isAvailable ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReorderArrows(onMoveUp: onMoveUp, onMoveDown: onMoveDown),
              const SizedBox(width: 4),
              if (item.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: transformedImageUrl(item.imageUrl!, width: 96, height: 96),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox(width: 48, height: 48),
                  ),
                ),
            ],
          ),
          title: Text(item.name, style: AppTextStyles.label),
          subtitle: Text(
            item.description != null && item.description!.isNotEmpty
                ? '${item.priceDisplay} · ${item.description}'
                : item.priceDisplay,
            style: AppTextStyles.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '${item.name} available',
                toggled: item.isAvailable,
                child: Switch(
                  value: item.isAvailable,
                  onChanged: onToggleAvailable,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AppColors.textSecondary,
                onPressed: onEdit,
                tooltip: 'Edit ${item.name}',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                onPressed: onDelete,
                tooltip: 'Delete ${item.name}',
              ),
            ],
          ),
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
  final Future<void> Function(String name, String desc, double price, String category, String? imageUrl) onSave;

  @override
  State<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<_MenuItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _customCategoryCtrl;
  String _dropdownCategory = 'Mains';
  bool _isCustomCategory = false;
  bool _saving = false;
  File? _pickedImage;
  String? _existingImageUrl;
  bool _removeImage = false;

  static const List<String> _defaultCategories = [
    'Mains', 'Sides', 'Drinks', 'Desserts', 'Specials',
  ];
  static const String _otherOption = 'Other…';

  String get _effectiveCategory =>
      _isCustomCategory ? _customCategoryCtrl.text.trim() : _dropdownCategory;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _priceCtrl = TextEditingController(
      text: widget.existing != null ? widget.existing!.price.toStringAsFixed(2) : '',
    );
    final existingCat = widget.existing?.category ?? 'Mains';
    _isCustomCategory = !_defaultCategories.contains(existingCat);
    _dropdownCategory = _isCustomCategory ? _otherOption : existingCat;
    _customCategoryCtrl = TextEditingController(text: _isCustomCategory ? existingCat : '');
    _existingImageUrl = widget.existing?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: uploadImageMaxDimension,
      maxHeight: uploadImageMaxDimension,
      imageQuality: 80,
    );
    if (xfile != null) setState(() { _pickedImage = File(xfile.path); _removeImage = false; });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? imageUrl = _existingImageUrl;

      if (_removeImage || (_pickedImage != null && _existingImageUrl != null)) {
        await storageServiceInstance.deleteByUrl(
            SupabaseConstants.menuItemPhotosBucket, _existingImageUrl!);
        imageUrl = null;
      }
      if (_pickedImage != null) {
        imageUrl = await storageServiceInstance.uploadImage(
          SupabaseConstants.menuItemPhotosBucket,
          _pickedImage!,
          ownerId: widget.truckId,
        );
      }
      if (_removeImage && _pickedImage == null) imageUrl = null;

      await widget.onSave(
        _nameCtrl.text.trim(),
        _descCtrl.text.trim(),
        double.parse(_priceCtrl.text.trim()),
        _effectiveCategory,
        imageUrl,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        context.showError('Could not save menu item: ${sanitizeErrorMessage(e)}');
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null ? 'Add Menu Item' : 'Edit Menu Item',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Photo picker ─────────────────────────────────────────────
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Builder(builder: (_) {
                    final showPicked = _pickedImage != null;
                    final showExisting = !showPicked && _existingImageUrl != null && !_removeImage;
                    if (showPicked) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_pickedImage!, fit: BoxFit.cover, width: double.infinity),
                      );
                    }
                    if (showExisting) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(imageUrl: transformedImageUrl(_existingImageUrl!, width: 800), fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 6, right: 6,
                            child: Semantics(
                              label: 'Remove menu item photo',
                              button: true,
                              child: GestureDetector(
                                onTap: () => setState(() => _removeImage = true),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: AppColors.textHint, size: 32),
                        const SizedBox(height: 6),
                        Text('Add photo (optional)', style: AppTextStyles.caption),
                      ],
                    );
                  }),
                ),
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
                      initialValue: _dropdownCategory,
                      decoration: _inputDecoration('Category', context),
                      items: [
                        ..._defaultCategories.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                        const DropdownMenuItem(
                          value: _otherOption,
                          child: Text(_otherOption),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _dropdownCategory = v ?? _dropdownCategory;
                        _isCustomCategory = v == _otherOption;
                      }),
                    ),
                  ),
                ],
              ),
              if (_isCustomCategory) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _customCategoryCtrl,
                  decoration: _inputDecoration('Category name', context),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
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
      ),
    );
  }

  InputDecoration _inputDecoration(String label, BuildContext context) => InputDecoration(
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
