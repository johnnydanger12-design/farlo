import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/providers/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/notification_prefs_provider.dart';
import '../providers/transfer_provider.dart';
import '../widgets/transfer_truck_sheet.dart';

const _tosUrl = 'https://farlo.app/terms';
const _privacyUrl = 'https://farlo.app/privacy';

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
          final incomingTransfer = ref.watch(incomingTransferProvider).asData?.value;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _ProfileTile(
                name: user.displayName,
                email: user.email,
                role: user.isOwner ? 'Food Truck Owner' : 'Consumer',
                avatarUrl: user.avatarUrl,
              ),
              if (incomingTransfer != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _IncomingTransferCard(
                  transfer: incomingTransfer,
                  onAccept: () async => _acceptTransfer(context, ref, incomingTransfer.id),
                  onDecline: () async => _declineTransfer(context, ref, incomingTransfer.id),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (!user.isOwner) ...[
                const _SectionHeader('Bookings'),
                _SettingsTile(
                  icon: Icons.event_outlined,
                  label: 'My Event Requests',
                  onTap: () => context.push('/account/my-requests'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              const _SectionHeader('Preferences'),
              const _AppearanceTile(),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () => _showNotificationsDialog(context, user.isOwner),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('Support'),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => launchUrl(Uri.parse(_tosUrl), mode: LaunchMode.externalApplication),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('Account'),
              _SettingsTile(
                icon: Icons.edit_outlined,
                label: 'Change Name',
                onTap: () => _showChangeNameDialog(context, ref, user.displayName),
              ),
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
              const SizedBox(height: AppSpacing.xl),
              _SettingsTile(
                icon: Icons.manage_accounts_outlined,
                label: 'Manage Account',
                onTap: () => context.push(
                  user.isOwner ? '/owner-account/settings' : '/account/settings',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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

  Future<void> _showChangeNameDialog(BuildContext context, WidgetRef ref, String currentName) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ChangeNameDialog(
        currentName: currentName,
        onSubmit: (name) async {
          if (name == currentName) return null;
          await ref.read(authProvider.notifier).updateDisplayName(name);
          return null;
        },
      ),
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

  Future<void> _acceptTransfer(BuildContext context, WidgetRef ref, String transferId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Accept Transfer?', textAlign: TextAlign.center),
        content: const Text(
          'You will become the owner of this truck. Your account role will change to Owner.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'accept-truck-transfer',
        body: {'transfer_id': transferId},
      );
      if (!context.mounted) return;
      ref.invalidate(incomingTransferProvider);
      await ref.read(authProvider.notifier).refreshUser();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to accept transfer. Please try again.')),
        );
      }
    }
  }

  Future<void> _declineTransfer(BuildContext context, WidgetRef ref, String transferId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
        title: const Text('Decline Transfer?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Decline', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await Supabase.instance.client
          .from('truck_transfers')
          .update({'status': 'cancelled'})
          .eq('id', transferId);
      ref.invalidate(incomingTransferProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to decline. Please try again.')),
        );
      }
    }
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

// ─── Manage Account sub-screen ────────────────────────────────────────────────

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).asData?.value;
    final outgoingTransfer = (user?.isOwner ?? false)
        ? ref.watch(outgoingTransferProvider).asData?.value
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Account', style: AppTextStyles.heading3),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (user?.isOwner ?? false) ...[
            const _SectionHeader('Truck Ownership'),
            _SettingsTile(
              icon: Icons.swap_horiz,
              label: 'Transfer Truck Ownership',
              onTap: () => _showTransferSheet(context),
            ),
            if (outgoingTransfer != null) ...[
              const SizedBox(height: 2),
              _OutgoingTransferBanner(
                transfer: outgoingTransfer,
                onCancel: () => _cancelTransfer(context, ref, outgoingTransfer.id),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
          const _SectionHeader('Danger Zone'),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            label: 'Delete Account',
            textColor: AppColors.error,
            onTap: () => _showDeleteAccountDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showTransferSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TransferTruckSheet(),
    );
  }

  Future<void> _cancelTransfer(BuildContext context, WidgetRef ref, String transferId) async {
    try {
      await Supabase.instance.client
          .from('truck_transfers')
          .update({'status': 'cancelled'})
          .eq('id', transferId);
      ref.invalidate(outgoingTransferProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel. Please try again.')),
        );
      }
    }
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _DeleteAccountDialog(
        onConfirm: () async {
          await ref.read(authProvider.notifier).deleteAccount();
          if (context.mounted) context.go('/login');
        },
      ),
    );
  }
}

class _ProfileTile extends ConsumerStatefulWidget {
  const _ProfileTile({required this.name, required this.email, required this.role, this.avatarUrl});
  final String name;
  final String email;
  final String role;
  final String? avatarUrl;

  @override
  ConsumerState<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends ConsumerState<_ProfileTile> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(authProvider.notifier).updateAvatar(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update photo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _uploading ? null : _pickAndUpload,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: primary.withValues(alpha: 0.12),
                      child: _uploading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                            )
                          : widget.avatarUrl != null
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: widget.avatarUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => Text(
                                      widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: primary),
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: primary),
                                ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                        ),
                        child: const Icon(Icons.camera_alt, size: 11, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Account photo',
                style: TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name, style: AppTextStyles.heading3),
                const SizedBox(height: 2),
                Text(widget.email, style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(widget.role, style: AppTextStyles.caption.copyWith(color: primary)),
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
    final announcementAlert = prefs.asData?.value.announcementAlert ?? true;
    final bookingAlert = prefs.asData?.value.bookingAlert ?? true;
    final notifier = ref.read(notificationPrefsProvider.notifier);

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
            subtitle: Text(
              isOwner ? 'Booking updates and alerts' : 'All notifications',
              style: AppTextStyles.caption,
            ),
            value: pushEnabled,
            onChanged: systemGranted
                ? (v) {
                    if (!v && isOwner) {
                      _confirmDisablePush(context, ref);
                    } else {
                      notifier.setPushEnabled(v);
                    }
                  }
                : null,
          ),
          if (isOwner)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Live Status Alerts', style: AppTextStyles.label),
              subtitle: Text('Notify me when my truck goes live or offline', style: AppTextStyles.caption),
              value: openAlert && pushEnabled,
              onChanged: pushEnabled ? (v) => notifier.setOpenAlert(v) : null,
            ),
          if (!isOwner) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Announcements', style: AppTextStyles.label),
              subtitle: Text('Specials and updates from trucks you follow', style: AppTextStyles.caption),
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
          ],
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

class _ChangeNameDialog extends StatefulWidget {
  const _ChangeNameDialog({required this.currentName, required this.onSubmit});
  final String currentName;
  final Future<String?> Function(String name) onSubmit;

  @override
  State<_ChangeNameDialog> createState() => _ChangeNameDialogState();
}

class _ChangeNameDialogState extends State<_ChangeNameDialog> {
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AlertDialog(
      backgroundColor: isLight ? Colors.white : null,
      title: const Text('Change Name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name'),
            onSubmitted: (_) => _submit(),
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
              : const Text('Save'),
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

// ---------------------------------------------------------------------------

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.onConfirm});
  final Future<void> Function() onConfirm;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final confirmed = _ctrl.text.trim() == 'DELETE';

    return AlertDialog(
      backgroundColor: isLight ? Colors.white : null,
      title: const Text('Delete Account', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'This is permanent. Your account, truck data, reviews, bookings, and favorites will be deleted and cannot be recovered.',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Type DELETE to confirm', style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'DELETE'),
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
          onPressed: (!confirmed || _loading) ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
              : Text('Delete Account', style: TextStyle(color: confirmed ? AppColors.error : null)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _IncomingTransferCard extends StatelessWidget {
  const _IncomingTransferCard({
    required this.transfer,
    required this.onAccept,
    required this.onDecline,
  });

  final TransferInfo transfer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final daysLeft = transfer.expiresAt.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'Ownership Transfer Offer',
                style: AppTextStyles.label.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(transfer.truckName, style: AppTextStyles.heading3),
          const SizedBox(height: 2),
          Text(
            'From ${transfer.otherUserName} · Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _OutgoingTransferBanner extends StatelessWidget {
  const _OutgoingTransferBanner({required this.transfer, required this.onCancel});

  final TransferInfo transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final daysLeft = transfer.expiresAt.difference(DateTime.now()).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending transfer to ${transfer.otherUserName}',
                  style: AppTextStyles.label,
                ),
                Text(
                  'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.error, padding: EdgeInsets.zero),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
