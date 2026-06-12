import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    if (user != null) await _rcLogIn(user.id);
    return user;
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      await _rcLogIn(user.id);
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
      return user;
    });
  }

  Future<void> signUpOwner({
    required String email,
    required String password,
    required String displayName,
    required String truckName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signUpOwner(
            email: email,
            password: password,
            displayName: displayName,
            truckName: truckName,
          );
      await _rcLogIn(user.id);
      return user;
    });
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    try { await Purchases.logOut(); } catch (_) {}
    state = const AsyncData(null);
  }

  Future<void> _rcLogIn(String userId) async {
    try { await Purchases.logIn(userId); } catch (_) {}
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
