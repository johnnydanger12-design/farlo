import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/push_notification_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/register_owner_screen.dart';
import 'features/account/screens/account_screen.dart';
import 'features/map/screens/map_screen.dart';
import 'features/favorites/screens/favorites_screen.dart';
import 'features/owner_dashboard/screens/dashboard_screen.dart';
import 'features/owner_dashboard/screens/edit_truck_screen.dart';
import 'features/owner_dashboard/screens/manage_hours_screen.dart';
import 'features/owner_dashboard/screens/manage_menu_screen.dart';
import 'features/owner_dashboard/screens/subscription_screen.dart';
import 'features/employees/screens/employees_screen.dart';
import 'features/bookings/screens/booking_requests_screen.dart';
import 'features/bookings/screens/my_requests_screen.dart';
import 'features/food_trucks/screens/truck_profile_screen.dart';
import 'features/notifications/screens/notifications_screen.dart';
import 'features/orders/screens/my_orders_screen.dart';
import 'features/orders/screens/order_queue_screen.dart';
import 'features/orders/screens/stripe_connect_screen.dart';
import 'shells/consumer_shell.dart';
import 'shells/owner_shell.dart';

GoRouter? _sharedRouter;

// Accessible from push_notification_service for tap routing.
GoRouter? get sharedRouter => _sharedRouter;

// Router is created ONCE. The _AuthListenable triggers redirect re-evaluation
// when auth state changes. The redirect uses ref.read (not watch) so the router
// itself is never recreated — only its redirect logic re-runs.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/map',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authAsync = ref.read(authProvider);
      final onboardingAsync = ref.read(onboardingProvider);

      if (authAsync.isLoading || onboardingAsync.isLoading) return null;

      final onboardingComplete = onboardingAsync.asData?.value ?? true;
      final loc = state.matchedLocation;

      if (!onboardingComplete) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      final user = authAsync.asData?.value;
      final isAuthenticated = user != null;
      final isOnAuthRoute = loc == '/login' || loc == '/register' || loc == '/register-owner';

      if (!isAuthenticated && !isOnAuthRoute) return '/login';
      if (isAuthenticated && isOnAuthRoute) {
        return user.isOwner ? '/dashboard' : '/map';
      }
      if (isAuthenticated && user.isOwner) {
        const ownerRoutes = ['/dashboard', '/owner-bookings', '/owner-account', '/owner-notifications'];
        final onOwnerRoute = ownerRoutes.any((r) => loc.startsWith(r));
        if (!onOwnerRoute) return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/register-owner', builder: (c, s) => const RegisterOwnerScreen()),

      // Consumer shell
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => ConsumerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/map',
              builder: (c, s) => const MapScreen(),
              routes: [
                GoRoute(
                  path: 'truck/:id',
                  builder: (c, s) => TruckProfileScreen(
                    truckId: s.pathParameters['id']!,
                    scrollToReviews: s.extra == true,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/favorites', builder: (c, s) => const FavoritesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              builder: (c, s) => const NotificationsScreen(),
              routes: [
                GoRoute(path: 'my-requests', builder: (c, s) => const MyRequestsScreen()),
                GoRoute(path: 'my-orders', builder: (c, s) => const MyOrdersScreen()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/account',
              builder: (c, s) => const AccountScreen(),
              routes: [
                GoRoute(path: 'my-requests', builder: (c, s) => const MyRequestsScreen()),
                GoRoute(path: 'my-orders', builder: (c, s) => const MyOrdersScreen()),
                GoRoute(path: 'settings', builder: (c, s) => const AccountSettingsScreen()),
              ],
            ),
          ]),
        ],
      ),

      // Owner shell
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => OwnerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/dashboard',
              builder: (c, s) => const DashboardScreen(),
              routes: [
                GoRoute(
                  path: 'truck/:id',
                  builder: (c, s) => TruckProfileScreen(
                    truckId: s.pathParameters['id']!,
                    scrollToReviews: s.extra == true,
                  ),
                ),
                GoRoute(
                  path: 'edit-truck',
                  builder: (c, s) => const EditTruckScreen(),
                ),
                GoRoute(
                  path: 'manage-hours',
                  builder: (c, s) => const ManageHoursScreen(),
                ),
                GoRoute(
                  path: 'manage-menu',
                  builder: (c, s) => const ManageMenuScreen(),
                ),
                GoRoute(
                  path: 'subscription',
                  builder: (c, s) => const SubscriptionScreen(),
                ),
                GoRoute(
                  path: 'employees',
                  builder: (c, s) => const EmployeesScreen(),
                ),
                GoRoute(
                  path: 'bookings',
                  builder: (c, s) => const BookingRequestsScreen(),
                ),
                GoRoute(
                  path: 'orders',
                  builder: (c, s) => const OrderQueueScreen(),
                ),
                GoRoute(
                  path: 'stripe-connect',
                  builder: (c, s) => const StripeConnectScreen(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/owner-bookings',
              builder: (c, s) => const BookingRequestsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/owner-notifications', builder: (c, s) => const NotificationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/owner-account',
              builder: (c, s) => const AccountScreen(),
              routes: [
                GoRoute(path: 'settings', builder: (c, s) => const AccountSettingsScreen()),
                GoRoute(path: 'edit-truck', builder: (c, s) => const EditTruckScreen()),
                GoRoute(path: 'manage-hours', builder: (c, s) => const ManageHoursScreen()),
                GoRoute(path: 'manage-menu', builder: (c, s) => const ManageMenuScreen()),
                GoRoute(path: 'subscription', builder: (c, s) => const SubscriptionScreen()),
                GoRoute(path: 'employees', builder: (c, s) => const EmployeesScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
  _sharedRouter = router;
  PushNotificationService.onRouterReady();
  return router;
});

// Notifies go_router to re-run redirect when auth or onboarding state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (prev, next) => notifyListeners());
    ref.listen(onboardingProvider, (prev, next) => notifyListeners());
  }
}
