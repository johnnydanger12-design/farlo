import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../food_trucks/models/category_purchase_window.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

// Lets an owner restrict when a menu category can actually be *purchased* —
// browsing is never affected. A category with no windows at all (the
// default) stays purchasable whenever the truck itself is open. A window
// covers one or more days at one start/end time; the owner picks days once
// (e.g. Mon-Fri) rather than re-entering the same time five times — each
// selected day expands into its own row under the hood
// (FoodTruckRepository.createCategoryWindow), mirroring how operating_hours
// already stores one row per day.
class PurchaseWindowsSheet extends ConsumerStatefulWidget {
  const PurchaseWindowsSheet({super.key, required this.truckId, required this.categoryName});
  final String truckId;
  final String categoryName;

  @override
  ConsumerState<PurchaseWindowsSheet> createState() => _PurchaseWindowsSheetState();
}

class _WindowGroup {
  _WindowGroup({required this.days, required this.startTime, required this.endTime});
  final Set<int> days;
  final String startTime;
  final String endTime;
}

class _PurchaseWindowsSheetState extends ConsumerState<PurchaseWindowsSheet> {
  List<_WindowGroup>? _groups;
  bool _loading = true;
  bool _adding = false;
  bool _saving = false;

  // Working state for the "Add Window" sub-form.
  final Set<int> _newDays = {};
  String _newStart = '11:00';
  String _newEnd = '14:00';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref
        .read(foodTruckRepositoryProvider)
        .fetchCategoryWindows(widget.truckId, widget.categoryName);
    final byWindow = <String, _WindowGroup>{};
    for (final row in rows) {
      final key = '${row.startTime}|${row.endTime}';
      byWindow.putIfAbsent(key, () => _WindowGroup(days: {}, startTime: row.startTime, endTime: row.endTime));
      byWindow[key]!.days.add(row.dayOfWeek);
    }
    if (!mounted) return;
    setState(() {
      _groups = byWindow.values.toList();
      _loading = false;
    });
  }

  // Collapses a set of day-of-week ints into a compact label, e.g.
  // {1,2,3,4,5} -> "Mon–Fri", {0,6} -> "Sun, Sat".
  String _daysLabel(Set<int> days) {
    if (days.length == 7) return 'Every day';
    final sorted = days.toList()..sort();
    final ranges = <String>[];
    int start = sorted.first;
    int prev = sorted.first;
    for (final d in sorted.skip(1)) {
      if (d == prev + 1) {
        prev = d;
        continue;
      }
      ranges.add(start == prev
          ? CategoryPurchaseWindow.dayAbbrevs[start]
          : '${CategoryPurchaseWindow.dayAbbrevs[start]}–${CategoryPurchaseWindow.dayAbbrevs[prev]}');
      start = prev = d;
    }
    ranges.add(start == prev
        ? CategoryPurchaseWindow.dayAbbrevs[start]
        : '${CategoryPurchaseWindow.dayAbbrevs[start]}–${CategoryPurchaseWindow.dayAbbrevs[prev]}');
    return ranges.join(', ');
  }

  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _newStart : _newEnd;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isStart) {
        _newStart = formatted;
      } else {
        _newEnd = formatted;
      }
    });
  }

  Future<void> _saveNewWindow() async {
    if (_newDays.isEmpty) {
      context.showError('Pick at least one day');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(foodTruckRepositoryProvider).createCategoryWindow(
            truckId: widget.truckId,
            categoryName: widget.categoryName,
            daysOfWeek: _newDays.toList(),
            startTime: _newStart,
            endTime: _newEnd,
          );
      _newDays.clear();
      setState(() => _adding = false);
      await _load();
    } catch (e) {
      if (mounted) context.showError('Could not save: ${sanitizeErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteGroup(_WindowGroup group) async {
    setState(() => _saving = true);
    try {
      await ref.read(foodTruckRepositoryProvider).deleteCategoryWindowGroup(
            truckId: widget.truckId,
            categoryName: widget.categoryName,
            startTime: group.startTime,
            endTime: group.endTime,
          );
      await _load();
    } catch (e) {
      if (mounted) context.showError('Could not delete: ${sanitizeErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Purchase Windows — ${widget.categoryName}', style: AppTextStyles.heading3),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Customers can always browse this category. Add a window to also require the times you set below to actually order from it — leave empty to keep it purchasable anytime you\'re open.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                for (final group in _groups!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_daysLabel(group.days)}, ${CategoryPurchaseWindow.formatTime(group.startTime)} – ${CategoryPurchaseWindow.formatTime(group.endTime)}',
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                          onPressed: _saving ? null : () => _deleteGroup(group),
                        ),
                      ],
                    ),
                  ),
                if (_groups!.isEmpty && !_adding)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('No windows set — always purchasable while you\'re open.',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                  ),
                if (_adding) ...[
                  const Divider(height: 24),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (int d = 0; d < 7; d++)
                        ChoiceChip(
                          label: Text(CategoryPurchaseWindow.dayAbbrevs[d]),
                          selected: _newDays.contains(d),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _newDays.add(d);
                            } else {
                              _newDays.remove(d);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _pickTime(true),
                        child: _TimeChip(time: _newStart),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('–'),
                      ),
                      GestureDetector(
                        onTap: () => _pickTime(false),
                        child: _TimeChip(time: _newEnd),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => setState(() => _adding = false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _saveNewWindow,
                          child: _saving
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save Window'),
                        ),
                      ),
                    ],
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _adding = true),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Window'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.time});
  final String time;

  String get _display {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final min = parts[1];
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(_display, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
