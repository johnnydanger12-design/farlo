import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/providers/food_truck_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Truck'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
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
                onToggle: (val) => _handleToggle(context, ref, val),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Manage', style: AppTextStyles.heading3),
              const SizedBox(height: AppSpacing.md),
              _DashboardTile(
                icon: Icons.edit_outlined,
                label: 'Edit Truck Profile',
                subtitle: 'Name, cuisine, description',
                onTap: () => context.go('/dashboard/edit-truck'),
              ),
              _DashboardTile(
                icon: Icons.schedule_outlined,
                label: 'Operating Hours',
                subtitle: 'Set your weekly schedule',
                onTap: () => context.go('/dashboard/manage-hours'),
              ),
              _DashboardTile(
                icon: Icons.restaurant_menu_outlined,
                label: 'Menu',
                subtitle: 'Add and manage menu items',
                onTap: () => context.go('/dashboard/manage-menu'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleToggle(BuildContext context, WidgetRef ref, bool isOpen) async {
    if (!isOpen) {
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(false);
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
      await ref.read(ownerTruckProvider.notifier).updateLocation(pos.latitude, pos.longitude);
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(true);
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
        color: AppColors.surface,
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
        color: AppColors.surface,
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
