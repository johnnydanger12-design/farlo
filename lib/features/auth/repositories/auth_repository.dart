import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../../../core/constants/supabase_constants.dart';

const _googleWebClientId = String.fromEnvironment('GOOGLE_SIGN_IN_WEB_CLIENT_ID');

class AuthRepository {
  AuthRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<AppUser> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _fetchProfile(response.user!.id);
  }

  Future<AppUser> signUpConsumer({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    final uid = response.user!.id;

    await _supabase.from(SupabaseConstants.profilesTable).upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'role': 'consumer',
    });

    return _fetchProfile(uid);
  }

  Future<AppUser> signUpOwner({
    required String email,
    required String password,
    required String displayName,
    required String truckName,
    String businessType = 'mobile',
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    final uid = response.user!.id;

    await _supabase.from(SupabaseConstants.profilesTable).upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'role': 'owner',
    });

    await _supabase.from(SupabaseConstants.foodTrucksTable).insert({
      'owner_id': uid,
      'name': truckName,
      'cuisine_type': 'Other',
      'is_open': false,
      'is_active': false,
      'photo_urls': <String>[],
      'business_type': businessType,
      'address': ?address,
      'latitude': ?latitude,
      'longitude': ?longitude,
    });

    await _supabase.from(SupabaseConstants.subscriptionsTable).insert({
      'owner_id': uid,
      'status': 'trialing',
    });

    return _fetchProfile(uid);
  }

  // Called after a successful social sign-in on the owner registration screen.
  // Idempotent: if the user already owns a truck, just returns their profile.
  Future<AppUser> upgradeToOwner({
    required String uid,
    required String truckName,
    String businessType = 'mobile',
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final existing = await _supabase
        .from(SupabaseConstants.foodTrucksTable)
        .select('id')
        .eq('owner_id', uid)
        .maybeSingle();

    if (existing == null) {
      await _supabase
          .from(SupabaseConstants.profilesTable)
          .update({'role': 'owner'})
          .eq('id', uid);

      await _supabase.from(SupabaseConstants.foodTrucksTable).insert({
        'owner_id': uid,
        'name': truckName,
        'cuisine_type': 'Other',
        'is_open': false,
        'is_active': false,
        'photo_urls': <String>[],
        'business_type': businessType,
        'address': ?address,
        'latitude': ?latitude,
        'longitude': ?longitude,
      });

      await _supabase.from(SupabaseConstants.subscriptionsTable).upsert(
        {'owner_id': uid, 'status': 'trialing'},
        onConflict: 'owner_id',
      );
    }

    return _fetchProfile(uid);
  }

  Future<void> resetPasswordForEmail(String email) async {
    await _supabase.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    // Re-authenticate to verify the current password before allowing the change.
    await _supabase.auth.signInWithPassword(email: email, password: currentPassword);
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> updateDisplayName(String userId, String displayName) async {
    await _supabase
        .from(SupabaseConstants.profilesTable)
        .update({'display_name': displayName})
        .eq('id', userId);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> deleteAccount() async {
    await _supabase.functions.invoke('delete-account');
    // Session is invalidated server-side; clear local state only.
    await _supabase.auth.signOut(scope: SignOutScope.local);
  }

  Future<String> updateAvatar(String userId, Uint8List bytes) async {
    await _supabase.storage
        .from('avatars')
        .uploadBinary(userId, bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));

    // Append timestamp so CachedNetworkImage treats each upload as a new URL.
    final url =
        '${_supabase.storage.from('avatars').getPublicUrl(userId)}?v=${DateTime.now().millisecondsSinceEpoch}';

    await _supabase
        .from(SupabaseConstants.profilesTable)
        .update({'avatar_url': url}).eq('id', userId);

    return url;
  }

  Future<AppUser> signInWithApple() async {
    final rawNonce = _supabase.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final response = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: credential.identityToken!,
      nonce: rawNonce,
    );

    final uid = response.user!.id;
    final email = response.user!.email ?? '';
    final fullName = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    return _provisionSocialProfile(uid: uid, email: email, displayName: fullName);
  }

  Future<AppUser> signInWithGoogle() async {
    final rawNonce = _supabase.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    await GoogleSignIn.instance.initialize(
      serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
      nonce: hashedNonce,
    );

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw SocialCancelledException();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in did not return an ID token.');
    }

    final response = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: rawNonce,
    );

    final uid = response.user!.id;
    final email = account.email;
    final displayName = account.displayName ?? email.split('@').first;

    return _provisionSocialProfile(uid: uid, email: email, displayName: displayName);
  }

  // Only inserts on first social sign-in. Never overwrites an existing profile
  // (Apple only provides name/email on the very first authorization).
  Future<AppUser> _provisionSocialProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final existing = await _supabase
        .from(SupabaseConstants.profilesTable)
        .select('id')
        .eq('id', uid)
        .maybeSingle();

    if (existing == null) {
      final name = displayName.isNotEmpty ? displayName : email.split('@').first;
      await _supabase.from(SupabaseConstants.profilesTable).insert({
        'id': uid,
        'email': email,
        'display_name': name,
        'role': 'consumer',
      });
    }

    return _fetchProfile(uid);
  }

  Future<AppUser?> fetchCurrentUser() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null;
    return _fetchProfile(session.user.id);
  }

  Future<AppUser> _fetchProfile(String uid) async {
    final data = await _supabase
        .from(SupabaseConstants.profilesTable)
        .select()
        .eq('id', uid)
        .single();
    return AppUser.fromMap(data);
  }
}

class SocialCancelledException implements Exception {}
