import 'features/auth/models/app_user.dart';

/// The router's redirect decision, extracted as a pure function of plain
/// inputs — no Riverpod, no go_router, no Supabase — so it's unit-testable
/// without a live provider container (code-quality.md §2.14's #2 highest-
/// value test target: "pure function of auth/onboarding state, easily
/// unit-testable without Supabase, currently governs every navigation in
/// the app with zero tests").
///
/// Returns the path to redirect to, or null to allow the current navigation.
String? computeRedirect({
  required bool authLoading,
  required bool onboardingLoading,
  required bool onboardingComplete,
  required AppUser? user,
  required String matchedLocation,
}) {
  if (authLoading || onboardingLoading) return null;

  if (!onboardingComplete) {
    return matchedLocation == '/onboarding' ? null : '/onboarding';
  }

  final isAuthenticated = user != null;
  const authRoutes = ['/login', '/register', '/register-owner'];
  final isOnAuthRoute = authRoutes.contains(matchedLocation);
  final isGuestRoute = matchedLocation == '/map' ||
      matchedLocation.startsWith('/map/') ||
      matchedLocation == '/set-new-password';

  if (!isAuthenticated && !isOnAuthRoute && !isGuestRoute) return '/login';
  if (isAuthenticated && isOnAuthRoute) {
    return user.isOwner ? '/dashboard' : '/map';
  }
  if (isAuthenticated && user.isOwner) {
    const ownerRoutes = [
      '/dashboard',
      '/owner-bookings',
      '/owner-account',
      '/owner-notifications',
      '/set-new-password',
    ];
    final onOwnerRoute = ownerRoutes.any((r) => matchedLocation.startsWith(r));
    if (!onOwnerRoute) return '/dashboard';
  }
  return null;
}
