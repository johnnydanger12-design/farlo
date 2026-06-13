import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/providers/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/notification_prefs_provider.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account', style: AppTextStyles.heading3),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: userAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) {
          if (user == null) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _ProfileTile(
                name: user.displayName,
                email: user.email,
                role: user.isOwner ? 'Food Truck Owner' : 'Consumer',
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('App'),
              const _AppearanceTile(),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () => _showNotificationsDialog(context, user.isOwner),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () {},
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('Account'),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: 'Change Password',
                onTap: () => _showChangePasswordDialog(context, ref),
              ),
              _SettingsTile(
                icon: Icons.logout,
                label: 'Sign Out',
                textColor: AppColors.error,
                onTap: () => _signOut(context, ref),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showNotificationsDialog(BuildContext context, bool isOwner) async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final systemGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _NotificationsDialog(systemGranted: systemGranted, isOwner: isOwner),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context, WidgetRef ref) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ChangePasswordDialog(
        currentCtrl: currentCtrl,
        newCtrl: newCtrl,
        confirmCtrl: confirmCtrl,
        onSubmit: () async {
          final current = currentCtrl.text.trim();
          final newPass = newCtrl.text.trim();
          final confirm = confirmCtrl.text.trim();

          if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) return 'All fields are required.';
          if (newPass.length < 6) return 'New password must be at least 6 characters.';
          if (newPass != confirm) return 'Passwords do not match.';

          await ref.read(authProvider.notifier).changePassword(
            currentPassword: current,
            newPassword: newPass,
          );
          return null;
        },
      ),
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Sign out?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).signOut();
      if (context.mounted) context.go('/login');
    }
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.name, required this.email, required this.role});
  final String name;
  final String email;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.heading3),
                const SizedBox(height: 2),
                Text(email, style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(role, style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(title.toUpperCase(), style: AppTextStyles.caption),
    );
  }
}

class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).asData?.value ?? ThemeMode.system;
    final modeLabel = switch (mode) {
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
      _ => 'System',
    };
    final modeIcon = switch (mode) {
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      _ => Icons.brightness_auto_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(modeIcon, color: AppColors.textSecondary),
        title: Text('Appearance', style: AppTextStyles.label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(modeLabel, style: AppTextStyles.bodySmall),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
        onTap: () => _showPicker(context, ref, mode),
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, ThemeMode current) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Appearance', textAlign: TextAlign.center),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeOption(
              label: 'System',
              icon: Icons.brightness_auto_outlined,
              selected: current == ThemeMode.system,
              onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.system); Navigator.pop(dialogContext); },
            ),
            _ModeOption(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              selected: current == ThemeMode.light,
              onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.light); Navigator.pop(dialogContext); },
            ),
            _ModeOption(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              selected: current == ThemeMode.dark,
              onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.dark); Navigator.pop(dialogContext); },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : AppColors.textSecondary;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: AppTextStyles.label.copyWith(color: selected ? Theme.of(context).colorScheme.primary : null)),
      trailing: selected ? Icon(Icons.check, size: 18, color: color) : const SizedBox(width: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onTap: onTap,
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor ?? AppColors.textSecondary),
        title: Text(label, style: AppTextStyles.label.copyWith(color: textColor)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: onTap,
      ),
    );
  }
}

class _NotificationsDialog extends ConsumerWidget {
  const _NotificationsDialog({required this.systemGranted, required this.isOwner});
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final prefs = ref.watch(notificationPrefsProvider);
    final pushEnabled = prefs.asData?.value.pushEnabled ?? true;
    final openAlert = prefs.asData?.value.openAlert ?? true;

    return AlertDialog(
      backgroundColor: isLight ? Colors.white : null,
      title: const Text('Notifications', textAlign: TextAlign.center),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!systemGranted)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Notifications are off in System Settings.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Push Notifications', style: AppTextStyles.label),
            subtitle: Text('Booking updates and alerts', style: AppTextStyles.caption),
            value: pushEnabled,
            onChanged: systemGranted
                ? (v) {
                    if (!v && isOwner) {
                      _confirmDisablePush(context, ref);
                    } else {
                      ref.read(notificationPrefsProvider.notifier).setPushEnabled(v);
                    }
                  }
                : null,
          ),
          if (isOwner)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Going Live Alert', style: AppTextStyles.label),
              subtitle: Text('Notify me when my truck goes live', style: AppTextStyles.caption),
              value: openAlert && pushEnabled,
              onChanged: pushEnabled
                  ? (v) => ref.read(notificationPrefsProvider.notifier).setOpenAlert(v)
                  : null,
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (!systemGranted)
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
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
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Incorrect current password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AlertDialog(
      backgroundColor: isLight ? Colors.white : null,
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.currentCtrl,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
              suffixIcon: IconButton(
                icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Update'),
        ),
      ],
    );
  }
}
