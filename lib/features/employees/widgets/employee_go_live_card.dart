import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/employees_provider.dart';
import '../screens/employee_dashboard_screen.dart';

class EmployeeGoLiveCard extends ConsumerWidget {
  const EmployeeGoLiveCard({super.key, required this.truckId, required this.truckName});

  final String truckId;
  final String truckName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(employeeGoLiveProvider(truckId));
    final truck = asyncTruck.asData?.value;
    final isOpen = truck?.isOpen ?? false;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnerSession = isOpen &&
        truck?.openedByUserId != null &&
        truck?.openedByUserId != currentUserId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                Text(truckName,
                    style: AppTextStyles.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  isOwnerSession ? 'Owner is Open' : 'Tap to log in',
                  style: AppTextStyles.caption.copyWith(
                    color: isOwnerSession
                        ? AppColors.openGreen
                        : AppColors.textHint,
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
              : FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EmployeeDashboardScreen(
                        truckId: truckId,
                        truckName: truckName,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Dashboard',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
        ],
      ),
    );
  }

}
