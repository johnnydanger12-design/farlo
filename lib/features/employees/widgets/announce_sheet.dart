import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../services/storage_service.dart';
import '../../bookings/widgets/places_autocomplete_field.dart';
import '../models/planned_location.dart';
import '../models/weekly_special.dart';
import '../providers/planned_locations_provider.dart';
import '../providers/weekly_specials_provider.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _DayLocationEntry {
  final titleCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  double? lat;
  double? lng;
  // "HH:MM", same convention as OperatingHours. Not consumed by anything yet
  // — captured now so the future mobile auto-open/close feature has real
  // data to read once it's built, instead of retrofitting this form later.
  String? startTime;
  String? endTime;

  void dispose() {
    titleCtrl.dispose();
    addressCtrl.dispose();
  }
}

String? _formatTimeOfDay(TimeOfDay? t) => t == null
    ? null
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _displayTime(String? hhmm) {
  if (hhmm == null) return 'Set time';
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final minute = parts[1];
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return minute == '00'
      ? '$displayHour $period'
      : '$displayHour:$minute $period';
}

// One general "Announce" composer covering all 3 announcement shapes an owner
// sends to followers: a plain announcement (new item, discount, etc.), this
// week's locations, and this week's specials — any combination at once,
// since these often go out together. Replaces the old locations-only
// AnnounceWeekSheet. Locations entered here are saved as real
// planned_locations rows (create-or-update by date, not duplicated on
// resend) — the same table the calendar reads from, and the one the
// upcoming mobile auto-hours feature will read from too. Specials are
// broadcast-only text; they don't represent an operating commitment, so
// they never touch the calendar.
class AnnounceSheet extends ConsumerStatefulWidget {
  const AnnounceSheet({
    super.key,
    required this.truckId,
    required this.truckName,
    required this.weekMonday,
  });

  final String truckId;
  final String truckName;
  final DateTime weekMonday;

  @override
  ConsumerState<AnnounceSheet> createState() => _AnnounceSheetState();
}

class _AnnounceSheetState extends ConsumerState<AnnounceSheet> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final List<_DayLocationEntry> _locationDays = List.generate(
    7,
    (_) => _DayLocationEntry(),
  );
  final List<TextEditingController> _specialsDays = List.generate(
    7,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _specialsPriceDays = List.generate(
    7,
    (_) => TextEditingController(),
  );

  bool _includeLocations = false;
  bool _includeSpecials = false;
  File? _photo;
  bool _sending = false;
  late DateTime _weekMonday;
  DateTime? _locationsPrefilledFor;
  DateTime? _specialsPrefilledFor;

  List<DateTime> get _weekDates =>
      List.generate(7, (i) => _weekMonday.add(Duration(days: i)));

  @override
  void initState() {
    super.initState();
    _weekMonday = widget.weekMonday;
    // Every field that feeds the preview/Send-enabled state needs to trigger
    // a rebuild on its own — otherwise typing into e.g. a specials-only day
    // never refreshes the preview until some unrelated setState happens to
    // fire (a toggle flip, adding a photo), which reads as "not working."
    for (final d in _locationDays) {
      d.titleCtrl.addListener(_rebuild);
      d.addressCtrl.addListener(_rebuild);
    }
    for (final c in _specialsDays) {
      c.addListener(_rebuild);
    }
    for (final c in _specialsPriceDays) {
      c.addListener(_rebuild);
    }
  }

  // Lets an owner composing on e.g. a Saturday advance to the *next* week
  // instead of being stuck entering into a week that's already mostly over —
  // clears unsaved typing from the previous week so it can't bleed into the
  // new one, and lets the prefill methods below repopulate real data for
  // whichever week is now selected.
  void _shiftWeek(int days) {
    setState(() {
      _weekMonday = _weekMonday.add(Duration(days: days));
      for (final d in _locationDays) {
        d.titleCtrl.clear();
        d.addressCtrl.clear();
        d.lat = null;
        d.lng = null;
        d.startTime = null;
        d.endTime = null;
      }
      for (final c in _specialsDays) {
        c.clear();
      }
      for (final c in _specialsPriceDays) {
        c.clear();
      }
      _locationsPrefilledFor = null;
      _specialsPrefilledFor = null;
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    for (final d in _locationDays) {
      d.dispose();
    }
    for (final c in _specialsDays) {
      c.dispose();
    }
    for (final c in _specialsPriceDays) {
      c.dispose();
    }
    super.dispose();
  }

  // Prefills the locations section from any planned_locations already on the
  // calendar for this week, so re-opening this sheet to tweak/resend doesn't
  // start blank. Tracked per-week (not a plain bool) so navigating to a
  // different week via _shiftWeek re-triggers a fresh prefill for it.
  void _prefillLocationsFromExisting(List<PlannedLocation> existing) {
    if (_locationsPrefilledFor == _weekMonday) return;
    final weekDates = _weekDates;
    for (int i = 0; i < 7; i++) {
      final date = weekDates[i];
      final match = existing.where(
        (l) =>
            l.eventDate.year == date.year &&
            l.eventDate.month == date.month &&
            l.eventDate.day == date.day,
      );
      if (match.isNotEmpty) {
        final loc = match.first;
        _locationDays[i].titleCtrl.text = loc.title;
        _locationDays[i].addressCtrl.text = loc.address ?? '';
        _locationDays[i].lat = loc.latitude;
        _locationDays[i].lng = loc.longitude;
        _locationDays[i].startTime = loc.startTime;
        _locationDays[i].endTime = loc.endTime;
        _includeLocations = true;
      }
    }
    _locationsPrefilledFor = _weekMonday;
  }

  void _prefillSpecialsFromExisting(List<WeeklySpecial> existing) {
    if (_specialsPrefilledFor == _weekMonday) return;
    final weekDates = _weekDates;
    for (int i = 0; i < 7; i++) {
      final date = weekDates[i];
      final match = existing.where(
        (s) =>
            s.eventDate.year == date.year &&
            s.eventDate.month == date.month &&
            s.eventDate.day == date.day,
      );
      if (match.isNotEmpty) {
        final special = match.first;
        _specialsDays[i].text = special.title;
        _specialsPriceDays[i].text = special.price == null
            ? ''
            : _formatPrice(special.price!);
        _includeSpecials = true;
      }
    }
    _specialsPrefilledFor = _weekMonday;
  }

  String _formatPrice(double price) => price == price.roundToDouble()
      ? price.toStringAsFixed(0)
      : price.toStringAsFixed(2);

  // Fans this day's special out across the following days through a picked
  // end day — solves "runs until a certain date" without a schema change:
  // it just fills the same title/price into each of those existing day
  // fields. The profile/announcement text then collapses the identical run
  // back into a single range (see collapseConsecutiveSpecials) so it never
  // reads as several coincidentally-matching daily specials.
  Future<void> _copySpecialThrough(int fromIndex) async {
    final title = _specialsDays[fromIndex].text.trim();
    if (title.isEmpty) {
      context.showError('Enter this day\'s special first.');
      return;
    }
    final endIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Copy through…'),
        children: [
          for (int d = fromIndex + 1; d < 7; d++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(_dayNames[d]),
            ),
        ],
      ),
    );
    if (endIndex == null) return;
    final price = _specialsPriceDays[fromIndex].text.trim();
    setState(() {
      for (int d = fromIndex + 1; d <= endIndex; d++) {
        _specialsDays[d].text = title;
        _specialsPriceDays[d].text = price;
      }
    });
  }

  Future<void> _pickLocationTime(int dayIndex, {required bool isStart}) async {
    final entry = _locationDays[dayIndex];
    final current = isStart ? entry.startTime : entry.endTime;
    final initial = current == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(
            hour: int.parse(current.split(':')[0]),
            minute: int.parse(current.split(':')[1]),
          );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        entry.startTime = _formatTimeOfDay(picked);
      } else {
        entry.endTime = _formatTimeOfDay(picked);
      }
    });
  }

  Future<void> _pickPhoto() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: uploadImageMaxDimension,
      maxHeight: uploadImageMaxDimension,
      imageQuality: 85,
    );
    if (xfile != null) setState(() => _photo = File(xfile.path));
  }

  String _buildMessage() {
    final weekDates = _weekDates;
    final locationLines = <String>[];
    final specialsLines = <String>[];

    if (_includeLocations) {
      for (int i = 0; i < 7; i++) {
        final title = _locationDays[i].titleCtrl.text.trim();
        if (title.isEmpty) continue;
        final address = _locationDays[i].addressCtrl.text.trim();
        final date = weekDates[i];
        var locStr = address.isEmpty ? title : '$title ($address)';
        final start = _locationDays[i].startTime;
        final end = _locationDays[i].endTime;
        if (start != null && end != null) {
          locStr = '$locStr, ${_displayTime(start)}–${_displayTime(end)}';
        }
        locationLines.add(
          '${_dayNames[i]} ${_monthNames[date.month - 1]} ${date.day} — $locStr',
        );
      }
    }

    if (_includeSpecials) {
      // Collapse consecutive identical days (same title+price) into a range
      // — e.g. "Mon–Fri: Chicken Plate — $8.99" instead of the same line
      // repeated 5 times, which is what "Copy through…" fanning the same
      // entry across several days would otherwise read like.
      int? runStart;
      String? runTitle;
      double? runPrice;
      void flushRun(int endIndex) {
        if (runStart == null) return;
        final priceStr = runPrice == null
            ? ''
            : ' — \$${_formatPrice(runPrice)}';
        final label = runStart == endIndex
            ? _dayNames[runStart]
            : '${_dayNames[runStart]}–${_dayNames[endIndex]}';
        specialsLines.add('$label: $runTitle$priceStr');
      }

      for (int i = 0; i < 7; i++) {
        final special = _specialsDays[i].text.trim();
        final price = double.tryParse(_specialsPriceDays[i].text.trim());
        final matchesRun =
            special.isNotEmpty && special == runTitle && price == runPrice;
        if (matchesRun) continue;
        if (runStart != null) flushRun(i - 1);
        if (special.isEmpty) {
          runStart = null;
        } else {
          runStart = i;
          runTitle = special;
          runPrice = price;
        }
      }
      if (runStart != null) flushRun(6);
    }

    final note = _noteCtrl.text.trim();
    // Specials lines are day-name-only ("Mon: ..."), no date — without a
    // week range up top, a reader coming back to this later (or a location
    // line, which is dated, but read out of context) has no way to tell
    // which Monday is meant.
    final weekRange =
        '${_monthNames[weekDates.first.month - 1]} ${weekDates.first.day} – '
        '${_monthNames[weekDates.last.month - 1]} ${weekDates.last.day}';
    final parts = <String>[
      if (locationLines.isNotEmpty || specialsLines.isNotEmpty)
        'Week of $weekRange',
      if (locationLines.isNotEmpty) 'Locations:\n${locationLines.join('\n')}',
      if (specialsLines.isNotEmpty) 'Specials:\n${specialsLines.join('\n')}',
      if (note.isNotEmpty) note,
    ];
    return parts.join('\n\n');
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _buildMessage();
    if (title.isEmpty) {
      context.showError('Give your announcement a title.');
      return;
    }
    if (message.isEmpty) {
      context.showError('Add locations, specials, or a note first.');
      return;
    }

    setState(() => _sending = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // Save/update real calendar entries for any filled-in location day —
      // create-or-update by date so re-sending the same week never
      // duplicates a row.
      if (_includeLocations) {
        final existing =
            ref
                .read(
                  truckPlannedLocationsWeekProvider((
                    widget.truckId,
                    _weekMonday,
                  )),
                )
                .asData
                ?.value ??
            [];
        final weekDates = _weekDates;
        final repo = ref.read(plannedLocationsRepositoryProvider);
        for (int i = 0; i < 7; i++) {
          final locTitle = _locationDays[i].titleCtrl.text.trim();
          if (locTitle.isEmpty) continue;
          final date = weekDates[i];
          final address = _locationDays[i].addressCtrl.text.trim();
          final match = existing.where(
            (l) =>
                l.eventDate.year == date.year &&
                l.eventDate.month == date.month &&
                l.eventDate.day == date.day,
          );
          if (match.isNotEmpty) {
            await repo.update(
              id: match.first.id,
              title: locTitle,
              address: address.isEmpty ? null : address,
              latitude: _locationDays[i].lat,
              longitude: _locationDays[i].lng,
              startTime: _locationDays[i].startTime,
              endTime: _locationDays[i].endTime,
            );
          } else {
            await repo.create(
              truckId: widget.truckId,
              eventDate: date,
              title: locTitle,
              address: address.isEmpty ? null : address,
              latitude: _locationDays[i].lat,
              longitude: _locationDays[i].lng,
              startTime: _locationDays[i].startTime,
              endTime: _locationDays[i].endTime,
            );
          }
        }
        ref.invalidate(
          truckPlannedLocationsWeekProvider((widget.truckId, _weekMonday)),
        );
        ref.invalidate(
          truckPlannedLocationsProvider((
            widget.truckId,
            _weekMonday.year,
            _weekMonday.month,
          )),
        );
      }

      // Save/update real weekly_specials rows for any filled-in specials day
      // — same create-or-update-by-date pattern as locations, so these show
      // on the public profile (right above the menu) once their own date
      // arrives, and re-sending the same week never duplicates a row.
      if (_includeSpecials) {
        final existingSpecials =
            ref
                .read(
                  truckWeeklySpecialsWeekProvider((
                    widget.truckId,
                    _weekMonday,
                  )),
                )
                .asData
                ?.value ??
            [];
        final weekDates = _weekDates;
        final specialsRepo = ref.read(weeklySpecialsRepositoryProvider);
        for (int i = 0; i < 7; i++) {
          final specialTitle = _specialsDays[i].text.trim();
          if (specialTitle.isEmpty) continue;
          final date = weekDates[i];
          final price = double.tryParse(_specialsPriceDays[i].text.trim());
          final match = existingSpecials.where(
            (s) =>
                s.eventDate.year == date.year &&
                s.eventDate.month == date.month &&
                s.eventDate.day == date.day,
          );
          if (match.isNotEmpty) {
            await specialsRepo.update(
              id: match.first.id,
              title: specialTitle,
              price: price,
            );
          } else {
            await specialsRepo.create(
              truckId: widget.truckId,
              eventDate: date,
              title: specialTitle,
              price: price,
            );
          }
        }
        ref.invalidate(
          truckWeeklySpecialsWeekProvider((widget.truckId, _weekMonday)),
        );
        ref.invalidate(truckCurrentWeekSpecialsProvider(widget.truckId));
      }

      String? imageUrl;
      if (_photo != null) {
        imageUrl = await storageServiceInstance.uploadImage(
          SupabaseConstants.truckPhotosBucket,
          _photo!,
          ownerId: userId,
        );
      }

      final session = Supabase.instance.client.auth.currentSession;
      final resp = await Supabase.instance.client.functions.invoke(
        'send-truck-announcement',
        body: {
          'truck_id': widget.truckId,
          'title': title,
          'message': message,
          'image_url': ?imageUrl,
        },
        headers: {'Authorization': 'Bearer ${session?.accessToken}'},
      );
      if (resp.status != 200) throw Exception('Server error ${resp.status}');
      final sent = (resp.data?['sent'] as int?) ?? 0;
      if (mounted) {
        Navigator.pop(context, true);
        context.showSuccess(
          sent == 0
              ? 'No followers with notifications enabled.'
              : 'Sent to $sent follower${sent == 1 ? '' : 's'}.',
          backgroundColor: sent > 0 ? AppColors.openGreen : null,
        );
      }
    } catch (e) {
      if (mounted) {
        context.showError('Could not send: ${sanitizeErrorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final weekKey = (widget.truckId, _weekMonday);
    final locsAsync = ref.watch(truckPlannedLocationsWeekProvider(weekKey));
    final specialsAsync = ref.watch(truckWeeklySpecialsWeekProvider(weekKey));
    _prefillLocationsFromExisting(locsAsync.asData?.value ?? []);
    _prefillSpecialsFromExisting(specialsAsync.asData?.value ?? []);
    final weekDates = _weekDates;
    final preview = _buildMessage();

    final weekLabel =
        '${_monthNames[weekDates.first.month - 1]} ${weekDates.first.day} – '
        '${_monthNames[weekDates.last.month - 1]} ${weekDates.last.day}';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      // Material (not a plain Container) so the SwitchListTiles below have a
      // real Material ancestor to paint their background/ink splash on —
      // an opaque DecoratedBox in between makes that painting invisible.
      builder: (context, scrollController) => Material(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Announce to Followers',
                      style: AppTextStyles.heading3,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: 'Previous week',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _shiftWeek(-7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    weekLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: 'Next week',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _shiftWeek(7),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'e.g. New menu item! / This Week\'s Schedule',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    SwitchListTile(
                      value: _includeLocations,
                      onChanged: (val) =>
                          setState(() => _includeLocations = val),
                      title: const Text('This week\'s locations'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_includeLocations)
                      ...List.generate(
                        7,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 40,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                    _dayNames[i],
                                    style: AppTextStyles.bodySmall,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    TextField(
                                      controller: _locationDays[i].titleCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'Location name',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    PlacesAutocompleteField(
                                      controller: _locationDays[i].addressCtrl,
                                      label: 'Address (optional)',
                                      onCoordinatesSelected: (lat, lng) {
                                        _locationDays[i].lat = lat;
                                        _locationDays[i].lng = lng;
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => _pickLocationTime(
                                              i,
                                              isStart: true,
                                            ),
                                            child: Text(
                                              _displayTime(
                                                _locationDays[i].startTime,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: Text('–'),
                                        ),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => _pickLocationTime(
                                              i,
                                              isStart: false,
                                            ),
                                            child: Text(
                                              _displayTime(
                                                _locationDays[i].endTime,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),

                    SwitchListTile(
                      value: _includeSpecials,
                      onChanged: (val) =>
                          setState(() => _includeSpecials = val),
                      title: const Text('This week\'s specials'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_includeSpecials)
                      ...List.generate(
                        7,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  _dayNames[i],
                                  style: AppTextStyles.bodySmall,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _specialsDays[i],
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. Chicken plate',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _specialsPriceDays[i],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    hintText: '\$ (optional)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (i < 6)
                                IconButton(
                                  icon: const Icon(
                                    Icons.repeat_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Copy through…',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _copySpecialThrough(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),

                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Additional note (optional)',
                        hintText: 'e.g. Come say hi! Orders open at 11am.',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    if (_photo != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _photo!,
                              width: double.infinity,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => setState(() => _photo = null),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: const Text('Add a photo (optional)'),
                      ),
                    const SizedBox(height: AppSpacing.md),

                    if (preview.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preview',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(preview, style: AppTextStyles.body),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    AppButton(
                      label: 'Send to Followers',
                      onPressed: preview.isEmpty ? null : _send,
                      isLoading: _sending,
                      backgroundColor: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      child: Text(
                        'Followers who muted your announcements won\'t receive this.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
