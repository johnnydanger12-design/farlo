import 'package:shared_preferences/shared_preferences.dart';

// Device-level (not per-user — there's no signed-in user yet when this is
// read) hint for which sign-in method was used last on this device, so the
// login screen can point back at it instead of making a returning user hunt
// for "was it Google or Apple last time?" across three options.
const _key = 'last_login_method';

enum LastLoginMethod { email, apple, google }

Future<LastLoginMethod?> getLastLoginMethod() async {
  final prefs = await SharedPreferences.getInstance();
  return switch (prefs.getString(_key)) {
    'email' => LastLoginMethod.email,
    'apple' => LastLoginMethod.apple,
    'google' => LastLoginMethod.google,
    _ => null,
  };
}

Future<void> setLastLoginMethod(LastLoginMethod method) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key, method.name);
}
