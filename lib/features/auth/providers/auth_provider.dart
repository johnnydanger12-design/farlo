import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/rc_config.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

// Holds the signed-in AppUser. Null = unauthenticated.
// State is managed ONLY by explicit method calls — no internal listeners
// that could fire mid-signup and race with profile insertion.
class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final user = await ref.read(authRepositoryProvider).fetchCurrentUser();
    if (user != null) {
      await _rcLogIn(user.id);
      _subscribeToProfileChanges(user.id);
    }
    return user;
  }

  void _subscribeToProfileChanges(String userId) {
    final channel = Supabase.instance.client
        .channel('profile-role-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) => refreshUser(),
        )
        .subscribe();
    ref.onDispose(() => Supabase.instance.client.removeChannel(channel));
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      await _rcLogIn(user.id);
      await _claimInvites(user.id, user.email);
      return user;
    });
  }

  Future<void> signUpConsumer({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signUpConsumer(
            email: email,
            password: password,
            displayName: displayName,
          );
      await _rcLogIn(user.id);
      await _claimInvites(user.id, user.email);
      return user;
    });
  }

  Future<void> signUpOwner({
    required String email,
    required String password,
    required String displayName,
    required String truckName,
    String businessType = 'mobile',
    String? address,
    double? lat,
    double? lng,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signUpOwner(
            email: email,
            password: password,
            displayName: displayName,
            truckName: truckName,
            businessType: businessType,
            address: address,
            latitude: lat,
            longitude: lng,
          );
      await _rcLogIn(user.id);
      await _claimInvites(user.id, user.email);
      return user;
    });
  }

  Future<void> signInWithApple() async {
    final prev = state;
    state = const AsyncLoading();
    try {
      final user = await ref.read(authRepositoryProvider).signInWithApple();
      await _rcLogIn(user.id);
      await _claimInvites(user.id, user.email);
      state = AsyncData(user);
    } on SignInWithAppleAuthorizationException catch (e) {
      state = e.code == AuthorizationErrorCode.canceled
          ? prev
          : AsyncError(e, StackTrace.current);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signInWithGoogle() async {
    final prev = state;
    state = const AsyncLoading();
    try {
      final user = await ref.read(authRepositoryProvider).signInWithGoogle();
      await _rcLogIn(user.id);
      await _claimInvites(user.id, user.email);
      state = AsyncData(user);
    } on SocialCancelledException {
      state = prev;
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signUpOwnerWithApple(String truckName, {
    String businessType = 'mobile',
    String? address,
    double? lat,
    double? lng,
  }) async {
    final prev = state;
    state = const AsyncLoading();
    try {
      final socialUser = await ref.read(authRepositoryProvider).signInWithApple();
      final ownerUser = await ref.read(authRepositoryProvider).upgradeToOwner(
        uid: socialUser.id,
        truckName: truckName,
        businessType: businessType,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      await _rcLogIn(ownerUser.id);
      await _claimInvites(ownerUser.id, ownerUser.email);
      state = AsyncData(ownerUser);
    } on SignInWithAppleAuthorizationException catch (e) {
      state = e.code == AuthorizationErrorCode.canceled
          ? prev
          : AsyncError(e, StackTrace.current);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signUpOwnerWithGoogle(String truckName, {
    String businessType = 'mobile',
    String? address,
    double? lat,
    double? lng,
  }) async {
    final prev = state;
    state = const AsyncLoading();
    try {
      final socialUser = await ref.read(authRepositoryProvider).signInWithGoogle();
      final ownerUser = await ref.read(authRepositoryProvider).upgradeToOwner(
        uid: socialUser.id,
        truckName: truckName,
        businessType: businessType,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      await _rcLogIn(ownerUser.id);
      await _claimInvites(ownerUser.id, ownerUser.email);
      state = AsyncData(ownerUser);
    } on SocialCancelledException {
      state = prev;
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> upgradeToOwner(String truckName, {
    String businessType = 'mobile',
    String? address,
    double? lat,
    double? lng,
  }) async {
    final user = state.asData?.value;
    if (user == null) throw Exception('Not signed in');
    final ownerUser = await ref.read(authRepositoryProvider).upgradeToOwner(
      uid: user.id,
      truckName: truckName,
      businessType: businessType,
      address: address,
      latitude: lat,
      longitude: lng,
    );
    await _rcLogIn(ownerUser.id);
    state = AsyncData(ownerUser);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = state.asData?.value;
    if (user == null) throw Exception('Not signed in');
    await ref.read(authRepositoryProvider).changePassword(
      email: user.email,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (rcConfigured) try { await Purchases.logOut(); } catch (_) {}
    state = const AsyncData(null);
  }

  Future<void> refreshUser() async {
    final user = await ref.read(authRepositoryProvider).fetchCurrentUser();
    state = AsyncData(user);
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = state.asData?.value;
    if (user == null) return;
    await ref.read(authRepositoryProvider).updateDisplayName(user.id, displayName);
    state = AsyncData(AppUser(
      id: user.id,
      email: user.email,
      displayName: displayName,
      role: user.role,
      avatarUrl: user.avatarUrl,
      createdAt: user.createdAt,
    ));
  }

  Future<void> updateAvatar(Uint8List bytes) async {
    final user = state.asData?.value;
    if (user == null) return;
    final url = await ref.read(authRepositoryProvider).updateAvatar(user.id, bytes);
    state = AsyncData(AppUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      role: user.role,
      avatarUrl: url,
      createdAt: user.createdAt,
    ));
  }

  Future<void> deleteAccount() async {
    await ref.read(authRepositoryProvider).deleteAccount();
    if (rcConfigured) try { await Purchases.logOut(); } catch (_) {}
    state = const AsyncData(null);
  }

  Future<void> _rcLogIn(String userId) async {
    if (!rcConfigured) return;
    try { await Purchases.logIn(userId); } catch (_) {}
  }

  Future<void> _claimInvites(String userId, String email) async {
    try {
      await Supabase.instance.client
          .from('truck_employees')
          .update({
            'user_id': userId,
            'status': 'active',
            'linked_at': DateTime.now().toIso8601String(),
          })
          .eq('invited_email', email.trim().toLowerCase())
          .eq('status', 'pending');
    } catch (_) {}
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
