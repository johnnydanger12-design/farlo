import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../owner_dashboard/providers/subscription_provider.dart';
import '../models/truck_employee.dart';
import '../providers/employees_provider.dart';
import '../../../core/widgets/snackbar_extensions.dart';

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

class _EmployeesList extends ConsumerStatefulWidget {
  const _EmployeesList({required this.truckId, required this.truckName, required this.ownerName});
  final String truckId;
  final String truckName;
  final String ownerName;

  @override
  ConsumerState<_EmployeesList> createState() => _EmployeesListState();
}

class _EmployeesListState extends ConsumerState<_EmployeesList> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _channel = Supabase.instance.client
        .channel('employees-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'truck_employees',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) =>
              ref.invalidate(truckEmployeesProvider(widget.truckId)),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncEmployees = ref.watch(truckEmployeesProvider(widget.truckId));

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
    final sub = ref.read(subscriptionProvider).asData?.value;
    if (sub?.hasAccess != true) {
      context.showError(
        'Employee management requires an active subscription',
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'Upgrade',
          onPressed: () => context.go('/dashboard/subscription'),
        ),
      );
      return;
    }
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isLight = Theme.of(ctx).brightness == Brightness.light;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Container(
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)))),
                  Row(
                    children: [
                      Text('Add Employee', style: AppTextStyles.heading3),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Enter the employee\'s email address.', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Employee email', hintText: 'name@example.com', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () async {
                        final email = ctrl.text.trim();
                        if (email.isEmpty || !email.contains('@')) return;
                        Navigator.pop(ctx);
                        try {
                          final alreadyUser = await ref.read(truckEmployeesProvider(widget.truckId).notifier).invite(email);
                          Supabase.instance.client.functions.invoke('send-employee-invite', body: {
                            'email': email,
                            'truck_id': widget.truckId,
                            'isExistingUser': alreadyUser,
                          }).ignore();
                          if (context.mounted) {
                            context.showSuccess(
                              alreadyUser ? '$email has been added to your team.' : '$email invited — they\'ll get access when they sign up.',
                              backgroundColor: AppColors.openGreen,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            context.showError(sanitizeErrorMessage(e));
                          }
                        }
                      },
                      child: const Text('Add Employee'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, TruckEmployee employee) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Remove employee?'),
        content: Text(
          'Remove ${employee.displayName ?? employee.invitedEmail}? They will lose access to open your business.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(truckEmployeesProvider(widget.truckId).notifier).remove(employee.id);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
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
      ),
    );
  }
}
