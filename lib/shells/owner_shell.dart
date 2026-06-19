import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_theme.dart';
import '../features/bookings/providers/bookings_provider.dart';
import '../features/food_trucks/providers/food_truck_provider.dart';
import '../features/notifications/providers/notifications_provider.dart';


class OwnerShell extends ConsumerWidget {
  const OwnerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final truckId = ref.watch(ownerTruckProvider).asData?.value?.id;
    final pendingBookings = truckId != null
        ? ref.watch(pendingBookingCountProvider(truckId)).asData?.value ?? 0
        : 0;

    return Theme(
      data: AppTheme.forOwner(context),
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: pendingBookings > 0,
                label: Text('$pendingBookings'),
                child: const Icon(Icons.event_note_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: pendingBookings > 0,
                label: Text('$pendingBookings'),
                child: const Icon(Icons.event_note),
              ),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                child: const Icon(Icons.notifications),
              ),
              label: 'Notifications',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
