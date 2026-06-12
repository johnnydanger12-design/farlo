import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../../../core/constants/supabase_constants.dart';

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
    });

    await _supabase.from(SupabaseConstants.subscriptionsTable).insert({
      'owner_id': uid,
      'status': 'trialing',
    });

    return _fetchProfile(uid);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
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
