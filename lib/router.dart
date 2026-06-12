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

// Router is created ONCE. The _AuthListenable triggers redirect re-evaluation
// when auth state changes. The redirect uses ref.read (not watch) so the router
// itself is never recreated — only its redirect logic re-runs.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/map',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authAsync = ref.read(authProvider);

      // Still loading the initial session — don't redirect yet.
      if (authAsync.isLoading) return null;

      final user = authAsync.asData?.value;
      final isAuthenticated = user != null;
      final loc = state.matchedLocation;
      final isOnAuthRoute = loc == '/login' || loc == '/register' || loc == '/register-owner';

      if (!isAuthenticated && !isOnAuthRoute) return '/login';
      if (isAuthenticated && isOnAuthRoute) {
        return user.isOwner ? '/dashboard' : '/map';
      }
      if (isAuthenticated && user.isOwner && loc.startsWith('/favorites')) {
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

// Notifies go_router to re-run redirect when auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (prev, next) => notifyListeners());
  }
}
