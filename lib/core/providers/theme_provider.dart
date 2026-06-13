import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/providers/auth_provider.dart';

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  static String _key(String? userId) =>
      userId != null ? 'theme_mode_$userId' : 'theme_mode_guest';

  @override
  Future<ThemeMode> build() async {
    final user = await ref.watch(authProvider.future);
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key(user?.id)));
  }

  Future<void> set(ThemeMode mode) async {
    final user = ref.read(authProvider).asData?.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(user?.id), switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      _ => 'system',
    });
    state = AsyncData(mode);
  }

  static ThemeMode _parse(String? s) => switch (s) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
}
