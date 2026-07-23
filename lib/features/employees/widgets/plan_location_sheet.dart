import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../bookings/widgets/places_autocomplete_field.dart';
import '../models/planned_location.dart';
import '../providers/planned_locations_provider.dart';

class PlanLocationSheet extends ConsumerStatefulWidget {
  const PlanLocationSheet({
    super.key,
    required this.truckId,
    required this.initialDate,
    this.existing,
  });

  final String truckId;
  final DateTime initialDate;
  // When set, the sheet edits this row instead of creating a new one.
  final PlannedLocation? existing;

  @override
  ConsumerState<PlanLocationSheet> createState() => _PlanLocationSheetState();
}

class _PlanLocationSheetState extends ConsumerState<PlanLocationSheet> {
  final _titleCtrl    = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  late DateTime _date;
  double? _lat;
  double? _lng;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _date = existing.eventDate;
      _titleCtrl.text = existing.title;
      _addressCtrl.text = existing.address ?? '';
      _notesCtrl.text = existing.notes ?? '';
      _lat = existing.latitude;
      _lng = existing.longitude;
    } else {
      _date = widget.initialDate;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing != null) {
        // Preserve start/end time untouched — this sheet doesn't collect
        // them (that's the Announce sheet's job), so a plain edit here must
        // never silently wipe times that are already driving auto-hours.
        await ref.read(plannedLocationsRepositoryProvider).update(
              id: existing.id,
              title: _titleCtrl.text,
              address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
              latitude: _lat,
              longitude: _lng,
              notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
              startTime: existing.startTime,
              endTime: existing.endTime,
            );
      } else {
        await ref.read(plannedLocationsRepositoryProvider).create(
              truckId: widget.truckId,
              eventDate: _date,
              title: _titleCtrl.text,
              address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
              latitude: _lat,
              longitude: _lng,
              notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            );
      }
      // Invalidate so calendars refresh
      ref.invalidate(truckPlannedLocationsProvider((widget.truckId, _date.year, _date.month)));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        context.showError('Could not save: ${sanitizeErrorMessage(e)}');
      }
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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(_isEditing ? 'Edit Location' : 'Plan a Location', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Scrollable form content
            Flexible(child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEditing) ...[
                  // The date isn't editable here — moving a location to a
                  // different day isn't supported by the update path, and
                  // silently ignoring a changed date would be worse than not
                  // offering it. Delete and re-add to move a location.
                  Text(_formattedDate(_date), style: AppTextStyles.label),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  CalendarDatePicker(
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    onDateChanged: (d) => setState(() => _date = d),
                  ),
                  const Divider(height: 1),
                ],
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g. Hartsville Farmers Market',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                PlacesAutocompleteField(
                  controller: _addressCtrl,
                  label: 'Location / address (optional)',
                  onCoordinatesSelected: (lat, lng) { _lat = lat; _lng = lng; },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'e.g. Setup at 10am, near the main entrance',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),),),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: _isEditing ? 'Save Changes' : 'Save Location',
              onPressed: _save,
              isLoading: _saving,
              backgroundColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  String _formattedDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
