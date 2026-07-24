import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../map/models/food_truck.dart';
import '../providers/dashboard_providers.dart';

class DashboardGettingStartedCard extends ConsumerStatefulWidget {
  const DashboardGettingStartedCard({super.key, required this.truck, required this.onGoLive});
  final FoodTruck truck;
  final VoidCallback onGoLive;

  /// Mirrors the `done` conditions of every step below — keep in sync if a
  /// step is added/removed. Lets the dashboard keep showing this card until
  /// every step (not just "has gone live") is actually complete.
  static bool isComplete(FoodTruck truck, bool stripeConnected) {
    return truck.logoUrl != null &&
        truck.menuItems.isNotEmpty &&
        truck.operatingHours.isNotEmpty &&
        stripeConnected &&
        truck.hasEverOpened;
  }

  @override
  ConsumerState<DashboardGettingStartedCard> createState() => _DashboardGettingStartedCardState();
}

class _DashboardGettingStartedCardState extends ConsumerState<DashboardGettingStartedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final stripeConnected = ref.watch(stripeConnectedProvider).asData?.value ?? false;
    final primary = Theme.of(context).colorScheme.primary;

    final steps = [
      (
        title: 'Complete your profile',
        subtitle: 'Add a logo, description, and business type',
        done: widget.truck.logoUrl != null,
        onTap: () => context.go('/dashboard/edit-truck'),
      ),
      (
        title: 'Add your menu',
        subtitle: 'Customers can\'t order until you have at least one item',
        done: widget.truck.menuItems.isNotEmpty,
        onTap: () => context.go('/dashboard/manage-menu'),
      ),
      (
        title: 'Set business hours',
        subtitle: 'Let customers know when you\'re available',
        done: widget.truck.operatingHours.isNotEmpty,
        onTap: () => context.go('/dashboard/manage-hours'),
      ),
      (
        title: 'Connect Stripe',
        subtitle: 'Required to accept orders and payments',
        done: stripeConnected,
        onTap: () => context.go('/dashboard/stripe-connect'),
      ),
      (
        title: 'Open for the first time',
        subtitle: 'Go live and start appearing to customers',
        done: widget.truck.hasEverOpened,
        onTap: widget.onGoLive,
      ),
    ];

    final doneCount = steps.where((s) => s.done).length;

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _expanded ? _buildExpanded(context, steps, doneCount, primary) : _buildCollapsed(context, doneCount, steps.length, primary),
    );
  }

  // ── Collapsed: floating pill ─────────────────────────────────────────────────

  Widget _buildCollapsed(BuildContext context, int done, int total, Color primary) {
    return Center(
      child: Material(
        color: primary,
        borderRadius: BorderRadius.circular(50),
        elevation: 6,
        shadowColor: primary.withValues(alpha: 0.4),
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: done / total,
                    strokeWidth: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'Get Started',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$done/$total',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Expanded: full checklist card ────────────────────────────────────────────

  Widget _buildExpanded(BuildContext context, List<({bool done, String subtitle, String title, VoidCallback onTap})> steps, int doneCount, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: primary.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Get Started', style: AppTextStyles.heading3),
                      const SizedBox(height: 2),
                      Text('$doneCount of ${steps.length} steps complete', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 22),
                  color: AppColors.textHint,
                  tooltip: 'Collapse',
                  onPressed: () => setState(() => _expanded = false),
                ),
              ],
            ),
          ),
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: doneCount / steps.length,
                minHeight: 4,
                backgroundColor: AppColors.divider,
                color: doneCount == steps.length ? AppColors.openGreen : primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Steps
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final step = entry.value;
            final isLast = i == steps.length - 1;
            return Column(
              children: [
                const Divider(height: 1, color: AppColors.divider),
                InkWell(
                  onTap: step.done ? null : step.onTap,
                  borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(16)) : BorderRadius.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: step.done
                                ? AppColors.openGreen.withValues(alpha: 0.12)
                                : AppColors.divider.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step.done ? Icons.check : Icons.circle_outlined,
                            size: 16,
                            color: step.done ? AppColors.openGreen : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: step.done ? AppColors.textSecondary : null,
                                  decoration: step.done ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              Text(step.subtitle, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        if (!step.done)
                          const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
