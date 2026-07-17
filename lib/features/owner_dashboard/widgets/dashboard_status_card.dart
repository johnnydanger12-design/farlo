import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/truck_map_pin.dart';
import '../../../services/storage_service.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../food_trucks/screens/truck_profile_screen.dart';
import '../../map/models/food_truck.dart';
import '../providers/dashboard_providers.dart';

class DashboardStatusCard extends ConsumerWidget {
  const DashboardStatusCard({
    super.key,
    required this.truck,
    required this.currentUserId,
    required this.onGoLive,
  });

  final FoodTruck truck;
  final String currentUserId;
  final void Function(bool) onGoLive;

  bool get _isEmployeeLive =>
      truck.isOpen &&
      truck.openedByUserId != null &&
      truck.openedByUserId != currentUserId;

  String get _locationAge {
    if (!truck.isOpen || truck.locationUpdatedAt == null) return '';
    final diff = DateTime.now().difference(truck.locationUpdatedAt!);
    if (diff.inMinutes < 1) return 'Location updated just now';
    if (diff.inHours < 1) return 'Location updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  Future<void> _toggleOrdersAccepting(
    BuildContext context,
    WidgetRef ref,
    bool val,
    bool stripeConnected,
  ) async {
    if (val && !stripeConnected) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : Theme.of(context).colorScheme.surface,
          title: const Text('Connect Stripe First'),
          content: const Text(
            'Online orders require a connected Stripe account to receive payments.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.go('/dashboard/stripe-connect');
              },
              child: const Text('Connect Stripe →'),
            ),
          ],
        ),
      );
      return;
    }
    await ref.read(ownerTruckProvider.notifier).updateOrdersAccepting(val);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stripeConnected = ref.watch(stripeConnectedProvider).asData?.value ?? false;
    final employeeName = _isEmployeeLive
        ? ref
            .watch(profileDisplayNameProvider(truck.openedByUserId!))
            .asData
            ?.value
        : null;
    final firstName = employeeName?.split(' ').first ?? 'Employee';
    final locationAge = _locationAge;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
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
          // Truck name + logo — tap to view profile
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TruckProfileScreen(truckId: truck.id),
              ),
            ),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: truck.logoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: transformedImageUrl(truck.logoUrl!, width: 88, height: 88),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Icon(
                                Icons.storefront_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.storefront_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(truck.name, style: AppTextStyles.heading3),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 18, color: AppColors.textHint),
                          ],
                        ),
                        if (locationAge.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(locationAge, style: AppTextStyles.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Mini-map animates in when live
          AnimatedCrossFade(
            firstChild:
                const SizedBox(height: AppSpacing.lg, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 160,
                  child: truck.latitude != null && truck.longitude != null
                      ? FlutterMap(
                          options: MapOptions(
                            initialCenter:
                                LatLng(truck.latitude!, truck.longitude!),
                            initialZoom: 16,
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  Theme.of(context).brightness == Brightness.dark
                                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.farlo.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(truck.latitude!, truck.longitude!),
                                  width: 44,
                                  height: 44,
                                  child: TruckMapPin(
                                    isOpen: truck.isOpen,
                                    logoUrl: truck.logoUrl,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const ColoredBox(
                          color: Color(0xFF1A1A1A),
                          child: Center(
                            child: Text('Location not set',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        ),
                ),
              ),
            ),
            crossFadeState: truck.isOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 350),
          ),

          // Status row: text + toggle or end session
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truck.isOpen
                            ? (_isEmployeeLive
                                ? '$firstName is Open'
                                : 'You\'re Open')
                            : 'You\'re Closed',
                        style: AppTextStyles.label.copyWith(
                          color: truck.isOpen
                              ? AppColors.openGreen
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        truck.autoHoursEnabled
                            ? 'Following your set hours'
                            : truck.isOpen
                                ? (_isEmployeeLive
                                    ? 'You\'re open on the map'
                                    : 'Customers can see you on the map')
                                : (truck.isFixed
                                    ? 'Flip to show you\'re open'
                                    : 'Flip to open and share your location'),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (_isEmployeeLive)
                  OutlinedButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: isLight ? Colors.white : null,
                          title: const Text('End Session?',
                              textAlign: TextAlign.center),
                          content: Text(
                            'This will close the business and end their active session.',
                            textAlign: TextAlign.center,
                          ),
                          actionsAlignment: MainAxisAlignment.center,
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('End Session',
                                  style:
                                      TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) onGoLive(false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('End Session'),
                  )
                else
                  Semantics(
                    label: 'Go live — start accepting customers',
                    toggled: truck.isOpen,
                    child: Switch(
                      value: truck.isOpen,
                      // null onChanged disables the switch — auto_hours_enabled
                      // means sync-truck-hours (cron) is the only thing that
                      // should flip is_open, not a manual tap that it would
                      // just overwrite again within a few minutes anyway.
                      onChanged: truck.autoHoursEnabled ? null : onGoLive,
                      activeThumbColor: AppColors.openGreen,
                      activeTrackColor:
                          AppColors.openGreen.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ),

          // Cascading orders-accepting toggle — only when live with orders enabled
          if (truck.isOpen && truck.ordersEnabled) ...[
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          truck.ordersAccepting
                              ? 'Accepting online orders'
                              : 'Online orders paused',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: truck.ordersAccepting
                                ? AppColors.openGreen
                                : AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          truck.autoHoursEnabled
                              ? 'Turns off 15 min before you close'
                              : truck.ordersAccepting
                                  ? 'Customers can place orders now'
                                  : 'Tap to start accepting orders',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: 'Accept online orders',
                    toggled: truck.ordersAccepting,
                    child: Switch(
                      value: truck.ordersAccepting,
                      onChanged: truck.autoHoursEnabled
                          ? null
                          : (v) => _toggleOrdersAccepting(context, ref, v, stripeConnected),
                      activeThumbColor: AppColors.openGreen,
                      activeTrackColor:
                          AppColors.openGreen.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
