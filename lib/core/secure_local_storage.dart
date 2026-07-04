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

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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
