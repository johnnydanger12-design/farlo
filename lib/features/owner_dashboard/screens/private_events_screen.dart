import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class PrivateEventsScreen extends ConsumerStatefulWidget {
  const PrivateEventsScreen({super.key});

  @override
  ConsumerState<PrivateEventsScreen> createState() => _PrivateEventsScreenState();
}

class _PrivateEventsScreenState extends ConsumerState<PrivateEventsScreen> {
  bool _privateEventsEnabled = true;
  int? _cancellationPolicyHours;
  bool _loading = false;
  bool _initialized = false;

  void _initFromTruck() {
    if (_initialized) return;
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    _privateEventsEnabled = truck.privateEventsEnabled;
    _cancellationPolicyHours = truck.cancellationPolicyHours;
    _initialized = true;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final fields = <String, dynamic>{
        'private_events_enabled': _privateEventsEnabled,
        'cancellation_policy_hours': _cancellationPolicyHours,
      };
      await ref.read(ownerTruckProvider.notifier).updateProfile(fields);
      if (mounted) {
        context.showSuccess('Saved!', duration: const Duration(seconds: 2), backgroundColor: AppColors.openGreen);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        context.showError('Could not save: ${sanitizeErrorMessage(e)}');
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
      appBar: AppBar(
        title: const Text('Private Events & Catering'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accept Private Event Requests', style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text(
                'When off, customers won\'t see a "Request Private Event" button on your public profile at all.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _privateEventsEnabled,
                onChanged: (val) => setState(() => _privateEventsEnabled = val),
                title: const Text('Show "Request Private Event" on my profile'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('Cancellation Policy', style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text('Blocks online cancellation inside this window. Informational only — no automatic charge.', style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.sm),
              _CancellationPolicyDropdown(
                value: _cancellationPolicyHours,
                onChanged: (val) => setState(() => _cancellationPolicyHours = val),
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
    );
  }
}

class _CancellationPolicyDropdown extends StatelessWidget {
  const _CancellationPolicyDropdown({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _options = <int?>[null, 24, 48, 72, 168, 336];

  static String _label(int? hours) {
    if (hours == null) return 'No cancellation policy';
    if (hours < 24) return '$hours hours';
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
      items: _options.map((h) => DropdownMenuItem(value: h, child: Text(_label(h)))).toList(),
      onChanged: onChanged,
    );
  }
}
