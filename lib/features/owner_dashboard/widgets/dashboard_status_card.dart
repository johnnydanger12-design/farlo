import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/truck_map_pin.dart';
import '../../../services/storage_service.dart';
import '../../employees/providers/planned_locations_provider.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../food_trucks/screens/truck_profile_screen.dart';
import '../../map/models/food_truck.dart';
import '../providers/dashboard_providers.dart';
import 'adjust_location_pin_screen.dart';

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

  // Fixed businesses: their lat/lng is their one permanent position, so the
  // correction just goes straight onto food_trucks. Mobile businesses only
  // get this while auto_hours_enabled, because that's the one case where a
  // planned_locations row (not live GPS) is what's actually driving the pin
  // — sync-truck-hours copies that row's lat/lng onto food_trucks every
  // minute, so a raw device-GPS truck would just have any correction
  // overwritten by the next tracking tick. Finds the active row by matching
  // today's rows against the truck's current position (what the cron just
  // copied over), since there's no other link from "current pin" back to
  // "which row put it there" client-side.
  bool _canAdjustPin(FoodTruck truck) =>
      truck.isOpen &&
      truck.latitude != null &&
      truck.longitude != null &&
      (truck.isFixed || truck.autoHoursEnabled);

  Future<void> _adjustPin(BuildContext context, WidgetRef ref, FoodTruck truck) async {
    String? plannedLocationId;
    String? plannedTitle;
    String? plannedAddress;
    String? plannedNotes;
    String? plannedStart;
    String? plannedEnd;

    if (!truck.isFixed) {
      final todaysRows = await ref
          .read(plannedLocationsRepositoryProvider)
          .fetchForDate(truck.id, DateTime.now());
      final activeRow = todaysRows.where((r) {
        if (r.latitude == null || r.longitude == null) return false;
        return (r.latitude! - truck.latitude!).abs() < 0.0001 &&
            (r.longitude! - truck.longitude!).abs() < 0.0001;
      }).firstOrNull;
      if (activeRow == null) {
        if (context.mounted) {
          context.showInfo(
            "Couldn't find today's scheduled location to adjust — edit it from the Calendar instead.",
          );
        }
        return;
      }
      plannedLocationId = activeRow.id;
      plannedTitle = activeRow.title;
      plannedAddress = activeRow.address;
      plannedNotes = activeRow.notes;
      plannedStart = activeRow.startTime;
      plannedEnd = activeRow.endTime;
    }

    if (!context.mounted) return;
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => AdjustLocationPinScreen(
          initialLat: truck.latitude!,
          initialLng: truck.longitude!,
          subtitle: truck.address ?? 'Fine-tune your pin',
        ),
      ),
    );
    if (result == null) return;

    if (plannedLocationId != null) {
      await ref.read(plannedLocationsRepositoryProvider).update(
            id: plannedLocationId,
            title: plannedTitle!,
            address: plannedAddress,
            latitude: result.latitude,
            longitude: result.longitude,
            notes: plannedNotes,
            startTime: plannedStart,
            endTime: plannedEnd,
          );
    }
    await ref.read(ownerTruckProvider.notifier).updateProfile({
      'latitude': result.latitude,
      'longitude': result.longitude,
    });
    if (context.mounted) context.showSuccess('Pin location updated');
  }

  Future<void> _confirmStopAutomation(BuildContext context) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isLight ? Colors.white : null,
        title: const Text('Go Offline Now?', textAlign: TextAlign.center),
        content: const Text(
          'This closes your business and stops sharing your location immediately. It also turns off "Open/close automatically" — turn it back on from Hours & Automation whenever you\'re ready.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Go Offline',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) onGoLive(false);
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
                      ? Stack(
                          children: [
                            FlutterMap(
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
                            ),
                            if (_canAdjustPin(truck))
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Material(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => _adjustPin(context, ref, truck),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit_location_alt_outlined, size: 16),
                                          SizedBox(width: 4),
                                          Text('Adjust pin', style: AppTextStyles.caption),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
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
                      // While auto_hours_enabled, sync-truck-hours (cron) is
                      // normally the only thing that flips is_open — a manual
                      // tap to open early would just get overwritten within a
                      // few minutes. But manually going OFFLINE must always
                      // work (e.g. a real emergency, needing to immediately
                      // stop broadcasting location) — the switch only
                      // disables the "turn on early" direction, never "turn
                      // off now".
                      onChanged: (!truck.autoHoursEnabled || truck.isOpen)
                          ? (val) => (!val && truck.autoHoursEnabled)
                              ? _confirmStopAutomation(context)
                              : onGoLive(val)
                          : null,
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
