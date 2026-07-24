import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/notification_prefs_provider.dart';
import 'account_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1452-line account_screen.dart.

class NotificationsDialog extends ConsumerWidget {
  const NotificationsDialog({super.key, required this.systemGranted, required this.isOwner});
  final bool systemGranted;
  final bool isOwner;

  void _confirmDisablePush(BuildContext context, WidgetRef ref) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? Colors.white : null,
        title: const Text('Turn off notifications?'),
        content: const Text(
          'You won\'t receive alerts for new booking requests. You could miss a customer inquiry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(notificationPrefsProvider.notifier).setPushEnabled(false);
            },
            child: const Text('Turn off', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final pushEnabled = prefs.asData?.value.pushEnabled ?? true;
    final openAlert = prefs.asData?.value.openAlert ?? true;
    final announcementAlert = prefs.asData?.value.announcementAlert ?? true;
    final bookingAlert = prefs.asData?.value.bookingAlert ?? true;
    final lunchNudgeAlert = prefs.asData?.value.lunchNudgeAlert ?? true;
    final notifier = ref.read(notificationPrefsProvider.notifier);

    return buildSheetContainer(
      context: context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Notifications', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!systemGranted)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Notifications are off in System Settings.', style: AppTextStyles.caption.copyWith(color: AppColors.error))),
                  ],
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Push Notifications', style: AppTextStyles.label),
              subtitle: Text(isOwner ? 'Booking updates and alerts' : 'All notifications', style: AppTextStyles.caption),
              value: pushEnabled,
              onChanged: systemGranted ? (v) { if (!v && isOwner) { _confirmDisablePush(context, ref); } else { notifier.setPushEnabled(v); } } : null,
            ),
            if (isOwner)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Open/Closed Alerts', style: AppTextStyles.label),
                subtitle: Text('Notify me when my business opens or closes', style: AppTextStyles.caption),
                value: openAlert && pushEnabled,
                onChanged: pushEnabled ? (v) => notifier.setOpenAlert(v) : null,
              ),
            if (!isOwner) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Announcements', style: AppTextStyles.label),
                subtitle: Text('Weekly schedules and announcements from businesses you follow. Mute individual businesses on their profile page.', style: AppTextStyles.caption),
                value: announcementAlert && pushEnabled,
                onChanged: pushEnabled ? (v) => notifier.setAnnouncementAlert(v) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Booking Updates', style: AppTextStyles.label),
                subtitle: Text('Status updates on your private event requests', style: AppTextStyles.caption),
                value: bookingAlert && pushEnabled,
                onChanged: pushEnabled ? (v) => notifier.setBookingAlert(v) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Lunchtime Nudges', style: AppTextStyles.label),
                subtitle: Text('Occasional reminder when businesses you follow are open', style: AppTextStyles.caption),
                value: lunchNudgeAlert && pushEnabled,
                onChanged: pushEnabled ? (v) => notifier.setLunchNudgeAlert(v) : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (!systemGranted)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async { Navigator.pop(context); await openAppSettings(); },
                  child: const Text('Open System Settings'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChangeNameDialog extends StatefulWidget {
  const ChangeNameDialog({super.key, required this.currentName, required this.onSubmit});
  final String currentName;
  final Future<String?> Function(String name) onSubmit;

  @override
  State<ChangeNameDialog> createState() => _ChangeNameDialogState();
}

class _ChangeNameDialogState extends State<ChangeNameDialog> {
  late final TextEditingController _ctrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final error = await widget.onSubmit(name);
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildSheetContainer(
      context: context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Change Name', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: _loading ? null : () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Save', onPressed: _loading ? null : _submit, isLoading: _loading),
          ],
        ),
      ),
    );
  }
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.currentCtrl,
    required this.newCtrl,
    required this.confirmCtrl,
    required this.onSubmit,
  });

  final TextEditingController currentCtrl;
  final TextEditingController newCtrl;
  final TextEditingController confirmCtrl;
  // Returns an error string on validation/auth failure, null on success.
  final Future<String?> Function() onSubmit;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  bool _loading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final error = await widget.onSubmit();
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
      } else {
        Navigator.pop(context);
        context.showSuccess('Password updated successfully');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Incorrect current password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildSheetContainer(
      context: context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Change Password', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: _loading ? null : () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: widget.currentCtrl,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Current password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  tooltip: _obscureCurrent ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: widget.newCtrl,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  tooltip: _obscureNew ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: widget.confirmCtrl,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Update Password', onPressed: _loading ? null : _submit, isLoading: _loading),
          ],
        ),
      ),
    );
  }
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.onConfirm});
  final Future<void> Function() onConfirm;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.onConfirm();
      // onConfirm navigates to /login — no need to pop.
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Something went wrong. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _ctrl.text.trim() == 'DELETE';
    return buildSheetContainer(
      context: context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Delete Account', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: _loading ? null : () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text('This is permanent. Your account, business data, reviews, bookings, and favorites will be deleted and cannot be recovered.', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Type DELETE to confirm', style: AppTextStyles.label),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _ctrl,
              autofocus: true,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'DELETE', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (!confirmed || _loading) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  disabledBackgroundColor: AppColors.error.withValues(alpha: 0.4),
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Delete Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
