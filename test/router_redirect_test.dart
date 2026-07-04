import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/router_redirect.dart';
import 'package:farlo/features/auth/models/app_user.dart';

AppUser _user({required UserRole role}) => AppUser(
      id: 'u1',
      email: 'test@example.com',
      displayName: 'Test User',
      role: role,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('computeRedirect', () {
    test('returns null while auth or onboarding is loading, regardless of location', () {
      expect(
        computeRedirect(
          authLoading: true,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/dashboard',
        ),
        isNull,
      );
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: true,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/dashboard',
        ),
        isNull,
      );
    });

    test('sends to /onboarding when onboarding is incomplete and not already there', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: false,
          user: null,
          matchedLocation: '/map',
        ),
        '/onboarding',
      );
    });

    test('allows staying on /onboarding when onboarding is incomplete', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: false,
          user: null,
          matchedLocation: '/onboarding',
        ),
        isNull,
      );
    });

    test('unauthenticated user on a guest route (/map) is allowed through', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/map',
        ),
        isNull,
      );
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/map/truck/abc',
        ),
        isNull,
      );
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/set-new-password',
        ),
        isNull,
      );
    });

    test('unauthenticated user on a protected route is sent to /login', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/dashboard',
        ),
        '/login',
      );
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: null,
          matchedLocation: '/favorites',
        ),
        '/login',
      );
    });

    test('unauthenticated user on an auth route (login/register) is allowed through', () {
      for (final loc in ['/login', '/register', '/register-owner']) {
        expect(
          computeRedirect(
            authLoading: false,
            onboardingLoading: false,
            onboardingComplete: true,
            user: null,
            matchedLocation: loc,
          ),
          isNull,
          reason: '$loc should be reachable while unauthenticated',
        );
      }
    });

    test('authenticated consumer on an auth route is redirected to /map', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: _user(role: UserRole.consumer),
          matchedLocation: '/login',
        ),
        '/map',
      );
    });

    test('authenticated owner on an auth route is redirected to /dashboard', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: _user(role: UserRole.owner),
          matchedLocation: '/register',
        ),
        '/dashboard',
      );
    });

    test('authenticated owner outside owner routes is redirected to /dashboard', () {
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: _user(role: UserRole.owner),
          matchedLocation: '/map',
        ),
        '/dashboard',
      );
      expect(
        computeRedirect(
          authLoading: false,
          onboardingLoading: false,
          onboardingComplete: true,
          user: _user(role: UserRole.owner),
          matchedLocation: '/favorites',
        ),
        '/dashboard',
      );
    });

    test('authenticated owner on an owner route is allowed through', () {
      for (final loc in [
        '/dashboard',
        '/dashboard/edit-truck',
        '/owner-bookings',
        '/owner-account/settings',
        '/owner-notifications',
        '/set-new-password',
      ]) {
        expect(
          computeRedirect(
            authLoading: false,
            onboardingLoading: false,
            onboardingComplete: true,
            user: _user(role: UserRole.owner),
            matchedLocation: loc,
          ),
          isNull,
          reason: '$loc should be reachable by an authenticated owner',
        );
      }
    });

    test('authenticated consumer can reach any non-auth route (no consumer-only gate)', () {
      for (final loc in ['/map', '/favorites', '/notifications', '/account']) {
        expect(
          computeRedirect(
            authLoading: false,
            onboardingLoading: false,
            onboardingComplete: true,
            user: _user(role: UserRole.consumer),
            matchedLocation: loc,
          ),
          isNull,
          reason: '$loc should be reachable by an authenticated consumer',
        );
      }
    });
  });
}
