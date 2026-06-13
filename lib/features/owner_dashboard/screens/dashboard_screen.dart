import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/push_notification_service.dart';
import '../../favorites/repositories/favorites_repository.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../account/providers/notification_prefs_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Truck'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncTruck.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) {
            return const Center(child: Text('No truck found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _StatusCard(
                truckName: truck.name,
                isOpen: truck.isOpen,
                locationUpdatedAt: truck.locationUpdatedAt,
                onToggle: (val) => _handleToggle(context, ref, val, truck.name),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader('Today'),
              const SizedBox(height: AppSpacing.sm),
              _DashboardTile(
                icon: Icons.event_note_outlined,
                label: 'Booking Requests',
                subtitle: 'View and respond to private event requests',
                onTap: () => context.go('/dashboard/bookings'),
              ),
              _DashboardTile(
                icon: Icons.campaign_outlined,
                label: 'Send Announcement',
                subtitle: 'Notify your followers with an update',
                onTap: () => _showAnnouncementSheet(context, truck.id, truck.name),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('Manage'),
              const SizedBox(height: AppSpacing.sm),
              _DashboardTile(
                icon: Icons.edit_outlined,
                label: 'Edit Truck Profile',
                subtitle: 'Name, cuisine, description',
                onTap: () => context.go('/dashboard/edit-truck'),
              ),
              _DashboardTile(
                icon: Icons.restaurant_menu_outlined,
                label: 'Menu',
                subtitle: 'Add and manage menu items',
                onTap: () => context.go('/dashboard/manage-menu'),
              ),
              _DashboardTile(
                icon: Icons.people_outline,
                label: 'Employees',
                subtitle: 'Manage who can go live for your truck',
                onTap: () => context.go('/dashboard/employees'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader('Plan'),
              const SizedBox(height: AppSpacing.sm),
              _DashboardTile(
                icon: Icons.star_outline,
                label: 'Subscription',
                subtitle: 'Manage your plan',
                onTap: () => context.go('/dashboard/subscription'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleToggle(BuildContext context, WidgetRef ref, bool isOpen, String truckName) async {
    if (!isOpen) {
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(false);
      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckClosedAlert(truckName);
        }
      }
      return;
    }

    // Turning on — fetch GPS first
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to go live')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting your location…')),
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      String? address;
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final street = [
            if (p.subThoroughfare?.isNotEmpty ?? false) p.subThoroughfare!,
            if (p.thoroughfare?.isNotEmpty ?? false) p.thoroughfare!,
          ].join(' ');
          final city = p.locality ?? '';
          if (street.isNotEmpty && city.isNotEmpty) {
            address = '$street, $city';
          } else if (city.isNotEmpty) {
            address = city;
          } else if (street.isNotEmpty) {
            address = street;
          }
        }
      } catch (e) {
        debugPrint('Geocoding failed: $e');
      }
      await ref.read(ownerTruckProvider.notifier).updateLocation(pos.latitude, pos.longitude, address: address);
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(true);

      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckOpenAlert(truckName);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You\'re live — customers can find you now!'),
            backgroundColor: AppColors.openGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  void _showAnnouncementSheet(BuildContext context, String truckId, String truckName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnouncementSheet(truckId: truckId, truckName: truckName),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.truckName,
    required this.isOpen,
    required this.locationUpdatedAt,
    required this.onToggle,
  });

  final String truckName;
  final bool isOpen;
  final DateTime? locationUpdatedAt;
  final void Function(bool) onToggle;

  String get _locationAge {
    if (!isOpen || locationUpdatedAt == null) return '';
    final diff = DateTime.now().difference(locationUpdatedAt!);
    if (diff.inMinutes < 1) return 'Location updated just now';
    if (diff.inHours < 1) return 'Location updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(truckName, style: AppTextStyles.heading3),
          if (_locationAge.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_locationAge, style: AppTextStyles.caption),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOpen ? 'You\'re Live' : 'You\'re Offline',
                      style: AppTextStyles.label.copyWith(
                        color: isOpen ? AppColors.openGreen : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOpen
                          ? 'Customers can see you on the map'
                          : 'Flip to go live and share your location',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Switch(
                value: isOpen,
                onChanged: onToggle,
                activeThumbColor: AppColors.openGreen,
                activeTrackColor: AppColors.openGreen.withValues(alpha: 0.4),
              ),
            ],
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
      padding: const EdgeInsets.only(left: 4),
      child: Text(title.toUpperCase(), style: AppTextStyles.caption),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        title: Text(label, style: AppTextStyles.label),
        subtitle: Text(subtitle, style: AppTextStyles.caption),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({required this.truckId, required this.truckName});
  final String truckId;
  final String truckName;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _loading = false;

  static const int _maxTitle = 60;
  static const int _maxMessage = 160;

  late final Future<int> _followerCountFuture =
      FavoritesRepository(Supabase.instance.client).fetchFollowerCount(widget.truckId);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sent == 0
              ? 'No followers with notifications enabled.'
              : 'Sent to $sent follower${sent == 1 ? '' : 's'}.'),
          backgroundColor: sent > 0 ? AppColors.openGreen : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
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
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
              hintText: 'e.g. We just added a new spicy brisket sandwich to our menu!',
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
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
