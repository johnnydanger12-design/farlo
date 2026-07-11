import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/core/secure_local_storage.dart';

void main() {
  // Regression test for the iOS sign-out bug (2026-07-08): SecureLocalStorage
  // never set an iOS Keychain accessibility level, so it silently defaulted
  // to KeychainAccessibility.unlocked -- the stored Supabase session became
  // unreadable the instant the screen locked, causing users to appear
  // signed out within minutes of backgrounding, well before the access
  // token itself expired. This pins the fix (first_unlock) so a future edit
  // can't silently drop it back to the unlocked default.
  test('iOS Keychain accessibility is first_unlock, not the unlocked default', () {
    expect(
      SecureLocalStorage.iOptionsForTesting['accessibility'],
      'first_unlock',
    );
  });
}
