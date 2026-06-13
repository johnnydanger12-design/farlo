import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../models/truck_employee.dart';
import '../providers/employees_provider.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees', style: AppTextStyles.heading3),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) {
            return const Center(child: Text('No truck found.'));
          }
          final ownerName = ref.read(authProvider).asData?.value?.displayName ?? '';
          return _EmployeesList(truckId: truck.id, truckName: truck.name, ownerName: ownerName);
        },
      ),
    );
  }
}

class _EmployeesList extends ConsumerWidget {
  const _EmployeesList({required this.truckId, required this.truckName, required this.ownerName});
  final String truckId;
  final String truckName;
  final String ownerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEmployees = ref.watch(truckEmployeesProvider(truckId));

    return asyncEmployees.when(
      loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
      data: (employees) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'If the employee already has an account they\'ll be added instantly. If not, they\'ll get access as soon as they sign up with that email.',
                    style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Team', style: AppTextStyles.heading3),
              TextButton.icon(
                onPressed: () => _showAddDialog(context, ref),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (employees.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text('No employees yet. Add one above.', style: AppTextStyles.bodySmall),
              ),
            )
          else
            ...employees.map((e) => _EmployeeTile(
                  employee: e,
                  onRemove: () => _confirmRemove(context, ref, e),
                )),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Add Employee'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Employee email',
            hintText: 'name@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              Navigator.pop(dialogContext);
              try {
                final alreadyUser = await ref.read(truckEmployeesProvider(truckId).notifier).invite(email);
                Supabase.instance.client.functions.invoke(
                  'send-employee-invite',
                  body: {
                    'email': email,
                    'truckName': truckName,
                    'ownerName': ownerName,
                    'isExistingUser': alreadyUser,
                  },
                ).ignore();
                if (context.mounted) {
                  final message = alreadyUser
                      ? '$email has been added to your team.'
                      : '$email invited — they\'ll get access when they sign up.';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor: AppColors.openGreen,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, TruckEmployee employee) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Remove employee?'),
        content: Text(
          'Remove ${employee.displayName ?? employee.invitedEmail}? They will lose access to go live for your truck.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(truckEmployeesProvider(truckId).notifier).remove(employee.id);
            },
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({required this.employee, required this.onRemove});
  final TruckEmployee employee;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isPending = employee.isPending;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Text(
            (employee.displayName ?? employee.invitedEmail)[0].toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          employee.displayName ?? employee.invitedEmail,
          style: AppTextStyles.label,
        ),
        subtitle: Text(
          isPending ? 'Pending — waiting for sign-up' : employee.invitedEmail,
          style: AppTextStyles.caption.copyWith(
            color: isPending ? AppColors.textHint : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Pending', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.openGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Active', style: TextStyle(fontSize: 11, color: AppColors.openGreen)),
              ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
