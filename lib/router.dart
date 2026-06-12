import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/register_owner_screen.dart';
import 'features/account/screens/account_screen.dart';
import 'features/map/screens/map_screen.dart';
import 'features/favorites/screens/favorites_screen.dart';
import 'features/owner_dashboard/screens/dashboard_screen.dart';
import 'shells/consumer_shell.dart';
import 'shells/owner_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/map',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      if (authAsync.isLoading) return null;

      final user = authAsync.value;
      final isAuthenticated = user != null;
      final isOnAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/register-owner';

      if (!isAuthenticated && !isOnAuthRoute) return '/login';
      if (isAuthenticated && isOnAuthRoute) {
        return user.isOwner ? '/dashboard' : '/map';
      }
      if (isAuthenticated && user.isOwner && _isConsumerOnlyRoute(state.matchedLocation)) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/register-owner', builder: (c, s) => const RegisterOwnerScreen()),

      // Consumer shell
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => ConsumerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/map', builder: (c, s) => const MapScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/favorites', builder: (c, s) => const FavoritesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: (c, s) => const AccountScreen()),
          ]),
        ],
      ),

      // Owner shell
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => OwnerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/owner-map', builder: (c, s) => const MapScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/owner-account', builder: (c, s) => const AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});

bool _isConsumerOnlyRoute(String location) {
  return location.startsWith('/favorites');
}

// Bridges Riverpod auth state into a Listenable so GoRouter can refresh.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (prev, next) => notifyListeners());
  }
}
