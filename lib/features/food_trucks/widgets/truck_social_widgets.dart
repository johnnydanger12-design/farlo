import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../map/models/food_truck.dart';
import '../providers/announcement_prefs_provider.dart';

// ARCH-4 (code-quality.md): extracted out of the 1425-line truck_profile_screen.dart.

class SocialSection extends StatelessWidget {
  const SocialSection({super.key, required this.truck});
  final FoodTruck truck;

  static const _platforms = [
    (field: 'instagram', icon: FontAwesomeIcons.instagram,  color: Color(0xFFE1306C)),
    (field: 'tiktok',    icon: FontAwesomeIcons.tiktok,     color: Color(0xFF010101)),
    (field: 'facebook',  icon: FontAwesomeIcons.facebook,   color: Color(0xFF1877F2)),
    (field: 'twitter',   icon: FontAwesomeIcons.xTwitter,   color: Color(0xFF000000)),
    (field: 'youtube',   icon: FontAwesomeIcons.youtube,    color: Color(0xFFFF0000)),
  ];

  String? _handleFor(String field) => switch (field) {
    'instagram' => truck.socialInstagram,
    'tiktok'    => truck.socialTiktok,
    'facebook'  => truck.socialFacebook,
    'twitter'   => truck.socialTwitter,
    'youtube'   => truck.socialYoutube,
    _           => null,
  };

  String _urlFor(String field, String handle) => switch (field) {
    'instagram' => 'https://instagram.com/$handle',
    'tiktok'    => 'https://tiktok.com/@$handle',
    'facebook'  => 'https://facebook.com/$handle',
    'twitter'   => 'https://x.com/$handle',
    'youtube'   => 'https://youtube.com/@$handle',
    _           => handle,
  };

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final platformButtons = _platforms
        .map((p) {
          final handle = _handleFor(p.field);
          if (handle == null) return null;
          final iconColor = (p.field == 'twitter' || p.field == 'tiktok') && isDark
              ? Colors.white
              : p.color;
          return SocialButton(
            icon: p.icon,
            color: iconColor,
            onTap: () => _launch(_urlFor(p.field, handle)),
          );
        })
        .whereType<Widget>()
        .toList();

    if (truck.websiteUrl != null) {
      platformButtons.add(SocialButton(
        icon: FontAwesomeIcons.globe,
        color: Theme.of(context).colorScheme.primary,
        onTap: () => _launch(truck.websiteUrl!),
      ));
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow Us', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: platformButtons),
        ],
      ),
    );
  }
}

class SocialButton extends StatelessWidget {
  const SocialButton({super.key, required this.icon, required this.color, required this.onTap});
  final FaIconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: FaIcon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// ── Announcement bell toggle ───────────────────────────────────────────────────

class AnnouncementBellButton extends ConsumerWidget {
  const AnnouncementBellButton({super.key, required this.truckId});
  final String truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(announcementPrefProvider(truckId)).asData?.value ?? true;
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          enabled ? Icons.notifications_rounded : Icons.notifications_off_outlined,
          key: ValueKey(enabled),
          color: Colors.white,
        ),
      ),
      tooltip: enabled ? 'Mute announcements' : 'Unmute announcements',
      onPressed: () async {
        await ref.read(announcementPrefProvider(truckId).notifier).toggle();
        if (!context.mounted) return;
        final nowEnabled = ref.read(announcementPrefProvider(truckId)).asData?.value ?? true;
        context.showInfo(
          nowEnabled ? 'Announcements turned on' : 'Announcements muted for this business',
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        );
      },
    );
  }
}
