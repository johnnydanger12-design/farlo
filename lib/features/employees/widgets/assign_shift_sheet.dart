import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/push_notification_service.dart';
import '../models/truck_employee.dart';
import '../providers/employees_provider.dart';
import '../providers/shifts_provider.dart';
import '../repositories/employees_repository.dart';

class AssignShiftSheet extends ConsumerStatefulWidget {
  const AssignShiftSheet({
    super.key,
    required this.truckId,
    required this.initialDate,
  });

  final String truckId;
  final DateTime initialDate;

  @override
  ConsumerState<AssignShiftSheet> createState() => _AssignShiftSheetState();
}

class _AssignShiftSheetState extends ConsumerState<AssignShiftSheet> {
  TruckEmployee? _selectedEmployee;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _startTime = const TimeOfDay(hour: 9, minute: 0);
    _endTime = const TimeOfDay(hour: 14, minute: 0);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  bool get _canSave =>
      _selectedEmployee != null &&
      _selectedEmployee!.userId != null &&
      !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null) return;

    final start = _combine(_date, _startTime);
    final end = _combine(_date, _endTime);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time')));
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(employeesRepositoryProvider);
      final shift = await repo.createScheduledShift(
        truckId: widget.truckId,
        employeeId: _selectedEmployee!.userId!,
        scheduledStart: start,
        scheduledEnd: end,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdBy: ownerId,
      );

      // Invalidate owner's scheduled shifts for the affected month
      ref.invalidate(truckScheduledShiftsProvider(
          (widget.truckId, _date.year, _date.month)));

      // Push notification to employee
      await PushNotificationService.sendShiftAssigned(shift.id);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not assign shift: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final asyncEmployees = ref.watch(truckEmployeesProvider(widget.truckId));
    final employees = asyncEmployees.asData?.value
            .where((e) => e.isActive && e.userId != null)
            .toList() ??
        [];

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Assign Shift', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.lg),

          // Employee picker
          Text('Employee', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          if (asyncEmployees.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (employees.isEmpty)
            Text('No active employees on this truck.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary))
          else
            DropdownButtonFormField<TruckEmployee>(
              value: _selectedEmployee,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              hint: const Text('Select employee'),
              items: employees
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.displayName ?? e.invitedEmail),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedEmployee = v),
            ),

          const SizedBox(height: AppSpacing.md),

          // Date
          Text('Date', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_fmtDate(_date), style: AppTextStyles.bodySmall),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Time row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickStartTime,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_fmtTime(_startTime),
                            style: AppTextStyles.bodySmall),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('End',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickEndTime,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_fmtTime(_endTime),
                            style: AppTextStyles.bodySmall),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Notes (optional)
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. Setup starts at 8:45am',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              counterText: '',
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Assign Shift'),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

// ─── Edit worked shift dialog ─────────────────────────────────────────────────

class EditWorkedShiftDialog extends ConsumerStatefulWidget {
  const EditWorkedShiftDialog({super.key, required this.shift, required this.truckId});
  final dynamic shift; // EmployeeShift
  final String truckId;

  @override
  ConsumerState<EditWorkedShiftDialog> createState() =>
      _EditWorkedShiftDialogState();
}

class _EditWorkedShiftDialogState extends ConsumerState<EditWorkedShiftDialog> {
  late TimeOfDay _inTime;
  late TimeOfDay _outTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _inTime = TimeOfDay.fromDateTime(widget.shift.clockedInAt);
    _outTime = widget.shift.clockedOutAt != null
        ? TimeOfDay.fromDateTime(widget.shift.clockedOutAt!)
        : TimeOfDay.now();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final date = widget.shift.clockedInAt;
      final clockedIn = DateTime(date.year, date.month, date.day, _inTime.hour, _inTime.minute);
      final clockedOut = DateTime(date.year, date.month, date.day, _outTime.hour, _outTime.minute);

      if (!clockedOut.isAfter(clockedIn)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clock-out must be after clock-in')));
        setState(() => _saving = false);
        return;
      }

      final repo = EmployeesRepository(Supabase.instance.client);
      await repo.updateWorkedShift(
        shiftId: widget.shift.id,
        clockedInAt: clockedIn,
        clockedOutAt: clockedOut,
      );

      // Invalidate the owner's month view
      ref.invalidate(truckShiftsProvider(
          (widget.truckId, date.year, date.month)));

      // Notify employee
      await PushNotificationService.sendShiftCorrected(widget.shift.id);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update shift: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      title: const Text('Edit Shift Times'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimePicker(
            label: 'Clock In',
            time: _inTime,
            onTap: () async {
              final t = await showTimePicker(
                  context: context, initialTime: _inTime);
              if (t != null) setState(() => _inTime = t);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _TimePicker(
            label: 'Clock Out',
            time: _outTime,
            onTap: () async {
              final t = await showTimePicker(
                  context: context, initialTime: _outTime);
              if (t != null) setState(() => _outTime = t);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Employee will be notified of the change.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _TimePicker extends StatelessWidget {
  const _TimePicker({required this.label, required this.time, required this.onTap});
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final m = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour < 12 ? 'AM' : 'PM';

    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ),
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('$h:$m $ampm', style: AppTextStyles.bodySmall),
        ),
      ],
    );
  }
}
