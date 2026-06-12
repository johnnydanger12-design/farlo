import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'features/auth/models/app_user.dart';
import 'features/auth/providers/auth_provider.dart';
import 'router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Belt-and-suspenders: navigate to /login whenever the user transitions
    // from authenticated → null (sign-out or expired session).
    ref.listen<AsyncValue<AppUser?>>(authProvider, (prev, next) {
      if (next.isLoading) return;
      final wasAuthed = prev?.asData?.value != null;
      final isAuthed = next.asData?.value != null;
      if (wasAuthed && !isAuthed) router.go('/login');
    });

    return MaterialApp.router(
      title: 'Good Truck Finder',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
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
    );
  }
}
