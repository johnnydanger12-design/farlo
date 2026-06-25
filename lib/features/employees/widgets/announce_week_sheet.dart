import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../models/planned_location.dart';
import '../providers/planned_locations_provider.dart';

class AnnounceWeekSheet extends ConsumerStatefulWidget {
  const AnnounceWeekSheet({
    super.key,
    required this.truckId,
    required this.truckName,
    required this.weekMonday,
  });

  final String truckId;
  final String truckName;
  final DateTime weekMonday;

  @override
  ConsumerState<AnnounceWeekSheet> createState() => _AnnounceWeekSheetState();
}

class _AnnounceWeekSheetState extends ConsumerState<AnnounceWeekSheet> {
  final _notesCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  List<DateTime> get _weekDates =>
      List.generate(7, (i) => widget.weekMonday.add(Duration(days: i)));

  String _buildMessage(List<PlannedLocation> locations) {
    final weekDates = _weekDates;
    const dayNames = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months   = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    final lines = <String>[];
    for (int i = 0; i < 7; i++) {
      final date    = weekDates[i];
      final dayLocs = locations.where((l) {
        final d = l.eventDate;
        return d.year == date.year && d.month == date.month && d.day == date.day;
      }).toList();

      if (dayLocs.isEmpty) continue;
      final locStr = dayLocs.map((l) {
        if (l.address != null && l.address!.isNotEmpty) {
          return '${l.title} (${l.address})';
        }
        return l.title;
      }).join(', ');
      lines.add('${dayNames[i]} ${months[date.month - 1]} ${date.day} — $locStr');
    }

    if (lines.isEmpty) return '';

    final notes = _notesCtrl.text.trim();
    return [
      ...lines,
      if (notes.isNotEmpty) '\n$notes',
    ].join('\n');
  }

  Future<void> _send(List<PlannedLocation> locations) async {
    final message = _buildMessage(locations);
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one planned location first.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final resp = await Supabase.instance.client.functions.invoke(
        'send-truck-announcement',
        body: {
          'truck_id': widget.truckId,
          'title'   : 'Schedule this week',
          'message' : message,
        },
        headers: {'Authorization': 'Bearer ${session?.accessToken}'},
      );
      if (resp.status != 200) throw Exception('Server error ${resp.status}');
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weekly schedule announced!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight  = Theme.of(context).brightness == Brightness.light;
    final weekKey  = (widget.truckId, widget.weekMonday);
    final locsAsync = ref.watch(truckPlannedLocationsWeekProvider(weekKey));
    final locations = locsAsync.asData?.value ?? [];
    final preview   = _buildMessage(locations);
    final weekDates = _weekDates;

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final weekLabel =
        '${months[weekDates.first.month - 1]} ${weekDates.first.day} – '
        '${months[weekDates.last.month - 1]} ${weekDates.last.day}';

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
          Text('Announce This Week', style: AppTextStyles.heading3),
          const SizedBox(height: 4),
          Text(
            weekLabel,
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: preview.isEmpty
                ? Text(
                    'No planned locations this week. Add some using Plan a Location first.',
                    style: AppTextStyles.body.copyWith(color: AppColors.textHint),
                  )
                : Column(
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

          // Optional extra note
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Add a note (optional)',
              hintText: 'e.g. Come say hi! Orders open at 11am.',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),

          AppButton(
            label: 'Send to Followers',
            onPressed: preview.isEmpty ? null : () => _send(locations),
            isLoading: _sending,
            backgroundColor: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'Followers who muted your announcements won\'t receive this.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
