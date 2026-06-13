import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/employees_provider.dart';

/// Pinned card on the map — shown when the logged-in user is an employee
/// of one or more trucks. One card per assigned truck.
class EmployeeGoLiveCard extends ConsumerWidget {
  const EmployeeGoLiveCard({super.key, required this.truckId, required this.truckName});

  final String truckId;
  final String truckName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(employeeGoLiveProvider(truckId));

    final isOpen = asyncTruck.asData?.value?.isOpen ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.local_shipping_outlined,
                color: Theme.of(context).colorScheme.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(truckName, style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  isOpen ? 'Live — customers can see you' : 'Offline',
                  style: AppTextStyles.caption.copyWith(
                    color: isOpen ? AppColors.openGreen : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          asyncTruck.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: isOpen,
                  onChanged: (val) => _handleToggle(context, ref, val),
                  activeThumbColor: AppColors.openGreen,
                  activeTrackColor: AppColors.openGreen.withValues(alpha: 0.4),
                ),
        ],
      ),
    );
  }

  Future<void> _handleToggle(BuildContext context, WidgetRef ref, bool isOpen) async {
    final notifier = ref.read(employeeGoLiveProvider(truckId).notifier);
    await handleGoLive(
      isOpen: isOpen,
      setOpenStatus: notifier.setOpenStatus,
      updateLocation: notifier.updateLocation,
      showMessage: (msg, {bool isError = false}) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: isError
                ? AppColors.error
                : isOpen
                    ? AppColors.openGreen
                    : null,
            duration: Duration(seconds: isError ? 4 : 3),
          ),
        );
      },
    );
  }
}
