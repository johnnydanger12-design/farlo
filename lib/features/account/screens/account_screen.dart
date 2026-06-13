import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/providers/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';

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
                onTap: () {},
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
