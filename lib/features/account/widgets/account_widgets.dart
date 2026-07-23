import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import 'account_shared.dart';

// ARCH-4 (code-quality.md): extracted out of the 1452-line account_screen.dart.

class ProfileTile extends ConsumerStatefulWidget {
  const ProfileTile({
    super.key,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
    required this.onEditName,
  });
  final String name;
  final String email;
  final String role;
  final String? avatarUrl;
  final VoidCallback onEditName;

  @override
  ConsumerState<ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends ConsumerState<ProfileTile> {
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
        context.showError('Failed to update photo. Please try again.');
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
                Row(
                  children: [
                    Expanded(child: Text(widget.name, style: AppTextStyles.heading3)),
                    IconButton(
                      onPressed: widget.onEditName,
                      tooltip: 'Edit name',
                      icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textHint),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
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

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(title.toUpperCase(), style: AppTextStyles.caption),
    );
  }
}

class AppearanceTile extends ConsumerWidget {
  const AppearanceTile({super.key});

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
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
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, ThemeMode current) {
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 3,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => buildSheetContainer(
        context: ctx,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              Row(
                children: [
                  Text('Appearance', style: AppTextStyles.heading3),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ModeOption(label: 'System', icon: Icons.brightness_auto_outlined, selected: current == ThemeMode.system,
                  onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.system); Navigator.pop(ctx); }),
              ModeOption(label: 'Light', icon: Icons.light_mode_outlined, selected: current == ThemeMode.light,
                  onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.light); Navigator.pop(ctx); }),
              ModeOption(label: 'Dark', icon: Icons.dark_mode_outlined, selected: current == ThemeMode.dark,
                  onTap: () { ref.read(themeModeProvider.notifier).set(ThemeMode.dark); Navigator.pop(ctx); }),
            ],
          ),
        ),
      ),
    );
  }
}

class ModeOption extends StatelessWidget {
  const ModeOption({
    super.key,
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

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: textColor ?? AppColors.textSecondary),
          title: Text(label, style: AppTextStyles.label.copyWith(color: textColor)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
          onTap: onTap,
        ),
      ),
    );
  }
}
