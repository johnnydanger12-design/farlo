import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../models/review.dart';

class ReviewsRepository {
  ReviewsRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Review>> fetchForTruck(String truckId) async {
    final data = await _supabase
        .from(SupabaseConstants.reviewsTable)
        .select()
        .eq('truck_id', truckId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Review.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Returns the existing review for the current user on this truck, or null.
  Future<Review?> fetchMyReview(String truckId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await _supabase
        .from(SupabaseConstants.reviewsTable)
        .select()
        .eq('truck_id', truckId)
        .eq('user_id', userId)
        .maybeSingle();
    return data == null ? null : Review.fromMap(data);
  }

  Future<void> submitReview({
    required String truckId,
    required String userDisplayName,
    String? userAvatarUrl,
    required int rating,
    String? comment,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _supabase.from(SupabaseConstants.reviewsTable).upsert({
      'truck_id': truckId,
      'user_id': userId,
      'user_display_name': userDisplayName,
      'user_avatar_url': userAvatarUrl,
      'rating': rating,
      'comment': comment?.trim().isEmpty ?? true ? null : comment!.trim(),
    }, onConflict: 'truck_id,user_id');
  }

  Future<void> deleteReview(String reviewId) async {
    await _supabase
        .from(SupabaseConstants.reviewsTable)
        .delete()
        .eq('id', reviewId);
  }
}
