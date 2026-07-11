import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session (access + refresh token) in Keychain
/// (iOS/macOS) / Keystore-backed EncryptedSharedPreferences (Android)
/// instead of the default SharedPreferences-backed storage, which on
/// Android is a plaintext app-private XML file and on iOS is an
/// app-sandboxed plist — neither Keychain/Keystore-encrypted
/// (security.md §1.1).
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  // iOS defaults to KeychainAccessibility.unlocked, which makes the item
  // unreadable the instant the device screen locks — not after any fixed
  // duration. Since Supabase's own background-resume auto-refresh reads the
  // stored refresh token to restore the session, a locked phone (often within
  // seconds of backgrounding, per the user's own auto-lock setting) made that
  // read return null and the session appeared lost, well before the access
  // token itself would have actually expired. first_unlock keeps the item
  // readable while locked (it only re-locks on a device restart), matching
  // what background token refresh actually needs.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Exposed only so a test can assert the configured accessibility level
  /// without a real Keychain round-trip (not achievable in a pure Dart unit
  /// test) -- a regression trip-wire for this exact bug class: silently
  /// reverting to the (default) `unlocked` accessibility.
  @visibleForTesting
  static Map<String, String> get iOptionsForTesting => _storage.iOptions.toMap();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    return (await _storage.read(key: persistSessionKey)) != null;
  }

  @override
  Future<String?> accessToken() {
    return _storage.read(key: persistSessionKey);
  }

  @override
  Future<void> removePersistedSession() {
    return _storage.delete(key: persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: persistSessionKey, value: persistSessionString);
  }
}
