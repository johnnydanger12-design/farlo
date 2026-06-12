import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class EditTruckScreen extends ConsumerStatefulWidget {
  const EditTruckScreen({super.key});

  @override
  ConsumerState<EditTruckScreen> createState() => _EditTruckScreenState();
}

class _EditTruckScreenState extends ConsumerState<EditTruckScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cuisineCtrl;
  late final TextEditingController _descCtrl;
  bool _loading = false;
  bool _initialized = false;

  static const List<String> _cuisineOptions = [
    'American', 'Mexican', 'Asian', 'BBQ', 'Pizza', 'Burgers',
    'Sandwiches', 'Seafood', 'Mediterranean', 'Indian',
    'Thai', 'Korean', 'Vegan', 'Desserts', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _cuisineCtrl = TextEditingController();
    _descCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cuisineCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _initFromTruck() {
    if (_initialized) return;
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    _nameCtrl.text = truck.name;
    _cuisineCtrl.text = truck.cuisineType;
    _descCtrl.text = truck.description ?? '';
    _initialized = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(ownerTruckProvider.notifier).updateProfile({
        'name': _nameCtrl.text.trim(),
        'cuisine_type': _cuisineCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: AppColors.openGreen,
            duration: Duration(seconds: 2),
          ),
        );
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTruck = ref.watch(ownerTruckProvider);
    _initFromTruck();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _nameCtrl,
                  label: 'Truck Name',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                _CuisineDropdown(
                  value: _cuisineCtrl.text.isEmpty ? 'Other' : _cuisineCtrl.text,
                  options: _cuisineOptions,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _cuisineCtrl.text = val);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _descCtrl,
                  label: 'Description (optional)',
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Save Changes',
                  onPressed: _loading ? null : _save,
                  isLoading: _loading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CuisineDropdown extends StatelessWidget {
  const _CuisineDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value) ? value : options.last;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      decoration: InputDecoration(
        labelText: 'Cuisine Type',
        labelStyle: AppTextStyles.bodySmall,
        filled: true,
        fillColor: AppColors.surface,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
