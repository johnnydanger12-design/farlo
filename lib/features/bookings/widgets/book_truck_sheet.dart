import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/booking_request.dart';
import '../providers/bookings_provider.dart';

const _durations = [
  '1 hour', '1.5 hours', '2 hours', '2.5 hours', '3 hours',
  '4 hours', '5 hours', '6 hours', '8 hours',
];

String _formatDate(DateTime dt) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

class _ScheduleResult {
  const _ScheduleResult({required this.date, required this.time, required this.duration});
  final DateTime date;
  final TimeOfDay time;
  final String duration;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main booking sheet
// ─────────────────────────────────────────────────────────────────────────────

class BookTruckSheet extends ConsumerStatefulWidget {
  const BookTruckSheet({super.key, required this.truckId, required this.truckName});
  final String truckId;
  final String truckName;

  @override
  ConsumerState<BookTruckSheet> createState() => _BookTruckSheetState();
}

class _BookTruckSheetState extends ConsumerState<BookTruckSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _guestCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime? _eventDate;
  TimeOfDay? _eventTime;
  String? _duration;
  String _eventType = eventTypes.first;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).asData?.value;
    if (user != null) {
      _nameCtrl.text = user.displayName;
      _emailCtrl.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _guestCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _scheduleLabel {
    if (_eventDate == null) return 'Date, start time & duration *';
    final parts = [
      _formatDate(_eventDate!),
      if (_eventTime != null) _fmtTime(_eventTime!),
      ?_duration,
    ];
    return parts.join('  •  ');
  }

  Future<void> _pickSchedule() async {
    final result = await showModalBottomSheet<_ScheduleResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SchedulePickerSheet(
        initialDate: _eventDate,
        initialTime: _eventTime,
        initialDuration: _duration,
      ),
    );
    if (result != null) {
      setState(() {
        _eventDate = result.date;
        _eventTime = result.time;
        _duration = result.duration;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventDate == null || _eventTime == null || _duration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the event schedule.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final user = ref.read(authProvider).asData?.value;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(bookingsRepositoryProvider).submitRequest(
        truckId: widget.truckId,
        requesterId: user.id,
        contactName: _nameCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        eventDate: _eventDate!,
        eventTime: _fmtTime(_eventTime!),
        duration: _duration,
        guestCount: int.tryParse(_guestCtrl.text.trim()),
        eventLocation: _locationCtrl.text.trim(),
        eventType: _eventType,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final scheduleSet = _eventDate != null && _eventTime != null && _duration != null;

    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Request Private Event', style: AppTextStyles.heading3),
                        const SizedBox(height: 2),
                        Text(widget.truckName, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel('Contact Info'),
                      _field(
                        controller: _nameCtrl,
                        label: 'Your name *',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _emailCtrl,
                        label: 'Email address *',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _phoneCtrl,
                        label: 'Phone number (optional)',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)\+]'))],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _sectionLabel('Event Details'),
                      // Combined schedule picker
                      _PickerTile(
                        icon: Icons.event_outlined,
                        label: _scheduleLabel,
                        hasValue: scheduleSet,
                        onTap: _pickSchedule,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _locationCtrl,
                        label: 'Event location / address *',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _guestCtrl,
                        label: 'Estimated guest count *',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        initialValue: _eventType,
                        decoration: const InputDecoration(labelText: 'Event type'),
                        items: eventTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) { if (v != null) setState(() => _eventType = v); },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(controller: _notesCtrl, label: 'Additional details (optional)', maxLines: 3),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                        ),
                        child: _submitting
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Send Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'The truck owner will review your request and reach out to confirm.',
                        style: AppTextStyles.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text.toUpperCase(), style: AppTextStyles.caption),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Combined schedule picker sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SchedulePickerSheet extends StatefulWidget {
  const _SchedulePickerSheet({this.initialDate, this.initialTime, this.initialDuration});
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? initialDuration;

  @override
  State<_SchedulePickerSheet> createState() => _SchedulePickerSheetState();
}

class _SchedulePickerSheetState extends State<_SchedulePickerSheet> {
  late DateTime _date;
  late TimeOfDay _time;
  String? _duration;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now().add(const Duration(days: 7));
    _time = widget.initialTime ?? const TimeOfDay(hour: 12, minute: 0);
    _duration = widget.initialDuration;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primary = Theme.of(context).colorScheme.primary;
    final canConfirm = _duration != null;

    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, 8, 0),
              child: Row(
                children: [
                  Text('Schedule Event', style: AppTextStyles.heading3),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 12),
            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Calendar
                    CalendarDatePicker(
                      initialDate: _date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                      onDateChanged: (d) => setState(() => _date = d),
                    ),
                    const Divider(height: 1),
                    // Start time row
                    InkWell(
                      onTap: _pickTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 16),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_outlined, size: 18, color: primary),
                            const SizedBox(width: 10),
                            Text('Start time', style: AppTextStyles.label),
                            const Spacer(),
                            Text(_fmtTime(_time),
                                style: AppTextStyles.label.copyWith(color: primary)),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 18, color: primary),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // Duration chips
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.hourglass_bottom_outlined, size: 18, color: primary),
                              const SizedBox(width: 10),
                              Text('Duration', style: AppTextStyles.label),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _durations.map((d) {
                              final selected = _duration == d;
                              return ChoiceChip(
                                label: Text(d),
                                selected: selected,
                                onSelected: (_) => setState(() => _duration = d),
                                selectedColor: primary.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  color: selected ? primary : null,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                ),
                                side: BorderSide(
                                  color: selected ? primary : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Done button — sticky at bottom
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, 8, AppSpacing.lg,
                AppSpacing.lg + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: FilledButton(
                onPressed: canConfirm
                    ? () => Navigator.pop(context, _ScheduleResult(date: _date, time: _time, duration: _duration!))
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: primary,
                ),
                child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared picker tile
// ─────────────────────────────────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = hasValue
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: color))),
            Icon(Icons.chevron_right, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
