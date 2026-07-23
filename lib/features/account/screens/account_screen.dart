import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/providers/tab_reselect_provider.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/transfer_provider.dart';
import '../widgets/account_dialogs.dart';
import '../widgets/account_shared.dart';
import '../widgets/account_transfer_widgets.dart';
import '../widgets/account_widgets.dart';
import '../widgets/data_export_sheet.dart';
import '../widgets/transfer_truck_sheet.dart';

const _tosUrl = 'https://farlo.app/terms';
const _privacyUrl = 'https://farlo.app/privacy';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TabReselectEvent?>(tabReselectProvider, (prev, next) {
      if (next != null && next.index == 3 && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ref.invalidate(authProvider);
        ref.invalidate(incomingTransferProvider);
      }
    });
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
          final hasEmailIdentity = Supabase.instance.client.auth.currentUser
              ?.identities
              ?.any((i) => i.provider == 'email') ?? true;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ProfileTile(
                name: user.displayName,
                email: user.email,
                role: user.isOwner ? 'Business Owner' : 'Consumer',
                avatarUrl: user.avatarUrl,
                onEditName: () => _showChangeNameDialog(context, ref, user.displayName),
              ),
              if (incomingTransfer != null) ...[
                const SizedBox(height: AppSpacing.lg),
                IncomingTransferCard(
                  transfer: incomingTransfer,
                  onAccept: () async => _acceptTransfer(context, ref, incomingTransfer.id),
                  onDecline: () async => _declineTransfer(context, ref, incomingTransfer.id),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (user.isOwner) ...[
                const SectionHeader('My Business'),
                SettingsTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit Business Profile',
                  onTap: () => context.push('/owner-account/edit-truck'),
                ),
                SettingsTile(
                  icon: Icons.schedule_outlined,
                  label: 'Business Hours',
                  onTap: () => context.push('/owner-account/manage-hours'),
                ),
                SettingsTile(
                  icon: Icons.restaurant_menu_outlined,
                  label: 'Menu',
                  onTap: () => context.push('/owner-account/manage-menu'),
                ),
                SettingsTile(
                  icon: Icons.payments_outlined,
                  label: 'Orders & Payments',
                  onTap: () => context.push('/owner-account/orders-payments'),
                ),
                SettingsTile(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Point of Sale',
                  onTap: () => context.push('/owner-account/pos-integration'),
                ),
                SettingsTile(
                  icon: Icons.event_outlined,
                  label: 'Private Events & Catering',
                  onTap: () => context.push('/owner-account/private-events'),
                ),
                SettingsTile(
                  icon: Icons.people_outline,
                  label: 'Employees',
                  onTap: () => context.push('/owner-account/employees'),
                ),
                SettingsTile(
                  icon: Icons.star_outline,
                  label: 'Subscription',
                  onTap: () => context.push('/owner-account/subscription'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (!user.isOwner) ...[
                const SectionHeader('Bookings'),
                SettingsTile(
                  icon: Icons.event_outlined,
                  label: 'My Event Requests',
                  onTap: () => context.push('/account/my-requests'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              const SectionHeader('Preferences'),
              const AppearanceTile(),
              SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () => _showNotificationsDialog(context, user.isOwner),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Support'),
              SettingsTile(
                icon: Icons.help_outline,
                label: 'Help & FAQ',
                onTap: () => context.push(user.isOwner ? '/owner-account/faq' : '/account/faq'),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => launchUrl(Uri.parse(_tosUrl), mode: LaunchMode.externalApplication),
              ),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
              ),
              SettingsTile(
                icon: Icons.support_agent_outlined,
                label: 'Contact Support',
                onTap: () async {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: 'support@farlo.app',
                    query: 'subject=Farlo%20Support%20Request',
                  );
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Account'),
              if (hasEmailIdentity)
                SettingsTile(
                  icon: Icons.lock_outline,
                  label: 'Change Password',
                  onTap: () => _showChangePasswordDialog(context, ref),
                ),
              SettingsTile(
                icon: Icons.logout,
                label: 'Sign Out',
                textColor: AppColors.error,
                onTap: () => _signOut(context, ref),
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsTile(
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
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          NotificationsDialog(systemGranted: systemGranted, isOwner: isOwner),
    );
  }

  Future<void> _showChangeNameDialog(BuildContext context, WidgetRef ref, String currentName) async {
    await showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNameDialog(
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

    await showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangePasswordDialog(
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
          'You will become the owner of this business and inherit its active subscription. Your account role will change to Owner.',
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
        context.showError('Failed to accept transfer. Please try again.');
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
        context.showError('Failed to decline. Please try again.');
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isLight = Theme.of(ctx).brightness == Brightness.light;
        return Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHandle(),
                const SizedBox(height: 8),
                Text('Sign out?', style: AppTextStyles.heading3),
                const SizedBox(height: 8),
                Text('You will need to sign back in to access your account.',
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Sign Out'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            const SectionHeader('Business Ownership'),
            SettingsTile(
              icon: Icons.swap_horiz,
              label: 'Transfer Business Ownership',
              onTap: () => _showTransferSheet(context),
            ),
            if (outgoingTransfer != null) ...[
              const SizedBox(height: 2),
              OutgoingTransferBanner(
                transfer: outgoingTransfer,
                onCancel: () => _cancelTransfer(context, ref, outgoingTransfer.id),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
          if (!(user?.isOwner ?? false)) ...[
            const SectionHeader('Business'),
            SettingsTile(
              icon: Icons.storefront_outlined,
              label: 'Start a Business',
              onTap: () => showTabAwareModalBottomSheet<void>(
                context: context,
                tabIndex: 3,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => UpgradeToOwnerSheet(ref: ref),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SectionHeader('Privacy'),
          SettingsTile(
            icon: Icons.download_outlined,
            label: 'Download My Data',
            onTap: () => showTabAwareModalBottomSheet<void>(
              context: context,
              tabIndex: 3,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const DataExportSheet(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Danger Zone'),
          SettingsTile(
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
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
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
        context.showError('Failed to cancel. Please try again.');
      }
    }
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DeleteAccountDialog(
        onConfirm: () async {
          await ref.read(authProvider.notifier).deleteAccount();
          if (context.mounted) context.go('/login');
        },
      ),
    );
  }
}
