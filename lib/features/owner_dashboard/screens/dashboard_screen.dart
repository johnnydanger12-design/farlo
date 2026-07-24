import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/tab_reselect_provider.dart';
import '../../../core/location_tracking_service.dart';
import '../../../core/push_notification_service.dart';
import '../../../core/widgets/background_location_disclosure.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../account/providers/notification_prefs_provider.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/dashboard_providers.dart';
import '../providers/subscription_provider.dart';
import '../../employees/widgets/announce_sheet.dart';
import '../widgets/dashboard_calendar_section.dart';
import '../widgets/dashboard_getting_started_card.dart';
import '../widgets/dashboard_orders_widget.dart';
import '../widgets/dashboard_quick_actions_row.dart';
import '../widgets/dashboard_status_card.dart';
import '../widgets/dashboard_stripe_status_card.dart';

// ARCH-4 (code-quality.md): this screen was a 1519-line "god screen" — the
// top-level build() method itself was already reasonably short, but every
// section it composed lived as a private class in this same file. Each
// section is now its own file under ../widgets/, sharing the 3 lightweight
// providers this screen and those widgets both need via
// ../providers/dashboard_providers.dart. This file now holds only the
// screen's own routing/orchestration logic (the go-live flow, the
// announcement-sheet/share-profile actions), not the rendering itself.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TabReselectEvent?>(tabReselectProvider, (prev, next) {
      if (next != null && next.index == 0 && (ModalRoute.of(context)?.isCurrent ?? false)) {
        ref.read(ownerTruckProvider.notifier).refresh();
      }
    });
    final asyncTruck = ref.watch(ownerTruckProvider);
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncTruck.when(
        loading: () => Center(
          child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary),
        ),
        error: (e, _) =>
            Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) {
            return const Center(child: Text('No business found.'));
          }
          final stripeConnected = ref.watch(stripeConnectedProvider).asData?.value ?? false;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (!DashboardGettingStartedCard.isComplete(truck, stripeConnected)) ...[
                DashboardGettingStartedCard(
                  truck: truck,
                  onGoLive: () => _handleToggle(context, ref, true, truck.name),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const DashboardStripeStatusCard(),
              const SizedBox(height: AppSpacing.md),
              DashboardQuickActionsRow(
                onAnnouncement: () {
                  final sub = ref.read(subscriptionProvider).asData?.value;
                  if (sub?.hasAccess != true) {
                    context.showError(
                      'Announcements require an active subscription',
                      showCloseIcon: true,
                      action: SnackBarAction(
                        label: 'Upgrade',
                        onPressed: () => context.go('/dashboard/subscription'),
                      ),
                    );
                    return;
                  }
                  _showAnnouncementSheet(context, truck.id, truck.name);
                },
                onShare: () => _shareTruckProfile(context, truck.name, truck.slug),
              ),
              const SizedBox(height: AppSpacing.md),
              DashboardStatusCard(
                truck: truck,
                currentUserId: currentUserId,
                onGoLive: (val) =>
                    _handleToggle(context, ref, val, truck.name),
              ),
              const SizedBox(height: AppSpacing.md),
              // Always shown — an owner needs to look back at past orders
              // (a dispute, just curiosity) regardless of whether the truck
              // is currently open/accepting orders. Only the "live" pending/
              // in-progress rows below the header are naturally empty while
              // closed; the header itself always links to the full order
              // queue (with search) at /dashboard/orders.
              DashboardOrdersWidget(truckId: truck.id),
              const SizedBox(height: AppSpacing.md),
              DashboardCalendarSection(truckId: truck.id, truckName: truck.name),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleToggle(
    BuildContext context,
    WidgetRef ref,
    bool isOpen,
    String truckName,
  ) async {
    if (!isOpen) {
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(false);
      LocationTrackingService.instance.stop();
      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckClosedAlert(truckName);
        }
      }
      return;
    }

    // Require an active subscription to go live.
    final sub = ref.read(subscriptionProvider).asData?.value;
    if (sub?.hasAccess != true) {
      if (context.mounted) {
        context.showError(
          'An active subscription is required to open',
          showCloseIcon: true,
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => context.go('/dashboard/subscription'),
          ),
        );
      }
      return;
    }

    final truck = ref.read(ownerTruckProvider).asData?.value;
    final isFixed = truck?.isFixed ?? false;

    if (isFixed) {
      // Fixed businesses have a permanent address — no GPS needed, just open.
      // But coordinates only ever get set by picking a suggestion in the
      // address autocomplete (edit_truck_screen.dart) — a truck that somehow
      // never got that (e.g. a seeded/test account, or a pre-validator row)
      // would otherwise go "live" and simply not appear anywhere on the map,
      // with no indication to the owner of why.
      if (truck?.latitude == null || truck?.longitude == null) {
        if (context.mounted) {
          context.showError(
            'Set your business address before opening',
            showCloseIcon: true,
            action: SnackBarAction(
              label: 'Set address',
              onPressed: () => context.go('/dashboard/edit-truck'),
            ),
          );
        }
        return;
      }
      try {
        await ref.read(ownerTruckProvider.notifier).setOpenStatus(true);
        final prefs = ref.read(notificationPrefsProvider).asData?.value;
        if (prefs?.pushEnabled ?? true) {
          if (prefs?.openAlert ?? true) {
            PushNotificationService.sendTruckOpenAlert(truckName);
          }
        }
        if (context.mounted) {
          context.showSuccess(
            'You\'re open — customers can find you now!',
            duration: const Duration(seconds: 3),
            backgroundColor: AppColors.openGreen,
          );
        }
      } catch (e) {
        if (context.mounted) {
          context.showError('Could not update status: ${sanitizeErrorMessage(e)}');
        }
      }
      return;
    }

    // Mobile business — request location and start GPS tracking.
    // Shows background-location disclosure on Android (required by Play policy).
    final locationGranted = await requestLocationForGoLive(context);
    if (!locationGranted) return;

    if (context.mounted) {
      context.showInfo('Getting your location…');
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      String? address;
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
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
      } catch (_) {}

      await ref
          .read(ownerTruckProvider.notifier)
          .updateLocation(pos.latitude, pos.longitude, address: address);
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(true);
      LocationTrackingService.instance.start(
        onLocation: ref.read(ownerTruckProvider.notifier).updateLocation,
      );

      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckOpenAlert(truckName);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        context.showSuccess(
          'You\'re open — customers can find you now!',
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.openGreen,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        context.showError('Could not get location: ${sanitizeErrorMessage(e)}');
      }
    }
  }

  void _showAnnouncementSheet(
      BuildContext context, String truckId, String truckName) {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 0,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnnounceSheet(
        truckId: truckId,
        truckName: truckName,
        weekMonday: monday,
      ),
    );
  }

  void _shareTruckProfile(BuildContext context, String truckName, String? slug) {
    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      buildTruckShareMessage(truckName, slug),
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }
}

/// Extracted as a pure, top-level function so it's unit-testable without a
/// widget/BuildContext. Real link to the business's own public page
/// (visit.farlo.app) instead of the generic marketing site -- previously
/// this shared text mentioned the business by name but the only link was
/// always the same plain farlo.app, with zero information about which
/// business was shared. Falls back to the old generic message if slug is
/// somehow unset (see FoodTruck.slug's doc comment for why that's
/// defensive, not expected).
String buildTruckShareMessage(String truckName, String? slug) {
  final link = slug != null ? 'https://visit.farlo.app/$slug' : 'https://farlo.app';
  return 'Check out $truckName on Farlo!\n\n'
      'Find local businesses near you, see their menus, and follow your favorites.\n\n'
      '$link';
}
