import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_colors.dart';
import 'core/providers/theme_provider.dart';
import 'core/push_notification_service.dart';
import 'features/auth/models/app_user.dart';
import 'features/auth/providers/auth_provider.dart';
import 'router.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<AuthState>? _supabaseAuthSub;

  @override
  void initState() {
    super.initState();
    // Route to the set-new-password screen when a password reset link is tapped.
    _supabaseAuthSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(routerProvider).go('/set-new-password');
      }
    });
  }

  @override
  void dispose() {
    _supabaseAuthSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Belt-and-suspenders: navigate to /map whenever the user transitions
    // from authenticated → null (sign-out or expired session).
    ref.listen<AsyncValue<AppUser?>>(authProvider, (prev, next) {
      if (next.isLoading) return;
      final user = next.asData?.value;
      final wasAuthed = prev?.asData?.value != null;
      final wasOwner = prev?.asData?.value?.isOwner ?? false;
      if (wasAuthed && user == null) router.go(wasOwner ? '/login' : '/map');
      // Keep push notification service in sync with auth state so cold-start
      // deep-links drain with the correct role and owner-routing works.
      PushNotificationService.onAuthResolved(user);
    });

    final themeMode = ref.watch(themeModeProvider).asData?.value ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Farlo',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
