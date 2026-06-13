import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/models/operating_hours.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class ManageHoursScreen extends ConsumerStatefulWidget {
  const ManageHoursScreen({super.key});

  @override
  ConsumerState<ManageHoursScreen> createState() => _ManageHoursScreenState();
}

class _ManageHoursScreenState extends ConsumerState<ManageHoursScreen> {
  // Working copy of hours indexed by dayOfWeek
  final Map<int, _HourEntry> _entries = {};
  bool _initialized = false;
  bool _saving = false;

  void _init(List<OperatingHours> existing) {
    if (_initialized) return;
    for (int d = 0; d < 7; d++) {
      final found = existing.where((h) => h.dayOfWeek == d).firstOrNull;
      _entries[d] = _HourEntry(
        isClosed: found?.isClosed ?? (d == 0 || d == 6), // default Sun/Sat closed
        openTime: found?.openTime ?? '09:00',
        closeTime: found?.closeTime ?? '17:00',
      );
    }
    _initialized = true;
  }

  Future<void> _save() async {
    final truck = ref.read(ownerTruckProvider).asData?.value;
    if (truck == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(foodTruckRepositoryProvider);
      for (final entry in _entries.entries) {
        await repo.upsertOperatingHours(
          truck.id,
          entry.key,
          isClosed: entry.value.isClosed,
          openTime: entry.value.openTime,
          closeTime: entry.value.closeTime,
        );
      }
      await ref.read(ownerTruckProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hours saved!'),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return asyncTruck.when(
      loading: () => Scaffold(
        body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (truck) {
        if (truck != null) _init(truck.operatingHours);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Operating Hours'),
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/dashboard'),
            ),
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                      )
                    : Text('Save', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: 7,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, day) => _DayRow(
              day: day,
              entry: _entries[day] ?? _HourEntry(isClosed: false, openTime: '09:00', closeTime: '17:00'),
              onChanged: (e) => setState(() => _entries[day] = e),
            ),
          ),
        );
      },
    );
  }
}

class _HourEntry {
  _HourEntry({required this.isClosed, required this.openTime, required this.closeTime});
  bool isClosed;
  String openTime;
  String closeTime;

  _HourEntry copyWith({bool? isClosed, String? openTime, String? closeTime}) =>
      _HourEntry(
        isClosed: isClosed ?? this.isClosed,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
      );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.entry, required this.onChanged});

  final int day;
  final _HourEntry entry;
  final ValueChanged<_HourEntry> onChanged;

  static const List<String> _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  Future<void> _pickTime(BuildContext context, bool isOpen) async {
    final parts = (isOpen ? entry.openTime : entry.closeTime).split(':');
    final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChanged(isOpen ? entry.copyWith(openTime: formatted) : entry.copyWith(closeTime: formatted));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(_dayNames[day], style: AppTextStyles.label),
          ),
          if (entry.isClosed)
            Expanded(
              child: Text('Closed', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
            )
          else
            Expanded(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickTime(context, true),
                    child: _TimeChip(time: entry.openTime),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('–', style: AppTextStyles.bodySmall),
                  ),
                  GestureDetector(
                    onTap: () => _pickTime(context, false),
                    child: _TimeChip(time: entry.closeTime),
                  ),
                ],
              ),
            ),
          Switch(
            value: !entry.isClosed,
            onChanged: (val) => onChanged(entry.copyWith(isClosed: !val)),
            activeThumbColor: AppColors.openGreen,
            activeTrackColor: AppColors.openGreen.withValues(alpha: 0.4),
          ),
        ],
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
