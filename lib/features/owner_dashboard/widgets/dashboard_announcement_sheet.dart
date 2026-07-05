import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/push_notification_service.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../favorites/repositories/favorites_repository.dart';

class DashboardAnnouncementSheet extends StatefulWidget {
  const DashboardAnnouncementSheet({super.key, required this.truckId, required this.truckName});
  final String truckId;
  final String truckName;

  @override
  State<DashboardAnnouncementSheet> createState() => _DashboardAnnouncementSheetState();
}

class _DashboardAnnouncementSheetState extends State<DashboardAnnouncementSheet> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _loading = false;

  static const int _maxTitle = 60;
  static const int _maxMessage = 160;

  late final Future<int> _followerCountFuture =
      FavoritesRepository(Supabase.instance.client)
          .fetchFollowerCount(widget.truckId);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) return;

    setState(() => _loading = true);
    try {
      final sent = await PushNotificationService.sendTruckAnnouncement(
        truckId: widget.truckId,
        title: title,
        message: message,
      );
      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccess(
        sent == 0
            ? 'No followers with notifications enabled.'
            : 'Sent to $sent follower${sent == 1 ? '' : 's'}.',
        backgroundColor: sent > 0 ? AppColors.openGreen : null,
      );
    } catch (e) {
      if (mounted) {
        context.showError('Failed to send: ${sanitizeErrorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final titleLen = _titleCtrl.text.length;
    final messageLen = _messageCtrl.text.length;
    final canSend = titleLen > 0 && messageLen > 0 && !_loading;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg + bottomPadding,
      ),
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
          Row(
            children: [
              Expanded(
                child: Text('Send Announcement', style: AppTextStyles.heading3),
              ),
              FutureBuilder<int>(
                future: _followerCountFuture,
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '$count follower${count == 1 ? '' : 's'}',
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Followers with notifications on will receive this.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _titleCtrl,
            maxLength: _maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. New Menu Item!',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageCtrl,
            maxLength: _maxMessage,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Message',
              hintText:
                  'e.g. We just added a new spicy brisket sandwich to our menu!',
              alignLabelWithHint: true,
              counterText: '$messageLen / $_maxMessage',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSend ? _send : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor:
                    Colors.white.withValues(alpha: 0.7),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
