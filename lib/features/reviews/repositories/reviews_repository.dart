import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/review.dart';

class ReviewsRepository {
  ReviewsRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Review>> fetchForTruck(String truckId) async {
    final data = await _supabase
        .from(SupabaseConstants.reviewsTable)
        .select()
        .eq('truck_id', truckId)
        .order('created_at', ascending: false)
        .withNetworkTimeout;
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
        .maybeSingle()
        .withNetworkTimeout;
    return data == null ? null : Review.fromMap(data);
  }

  Future<void> submitReview({
    required String truckId,
    required String truckOwnerId,
    required String userDisplayName,
    String? userAvatarUrl,
    required int rating,
    String? comment,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    if (userId == truckOwnerId) throw Exception('Owners cannot review their own truck');

    await _supabase.from(SupabaseConstants.reviewsTable).upsert({
      'truck_id': truckId,
      'user_id': userId,
      'user_display_name': userDisplayName,
      'user_avatar_url': userAvatarUrl,
      'rating': rating,
      'comment': comment?.trim().isEmpty ?? true ? null : comment!.trim(),
    }, onConflict: 'truck_id,user_id').withNetworkTimeout;
    // Notifications are inserted by DB triggers (bypass RLS): on_review_inserted, on_review_response_added
  }

  Future<void> deleteReview(String reviewId) async {
    await _supabase
        .from(SupabaseConstants.reviewsTable)
        .delete()
        .eq('id', reviewId)
        .withNetworkTimeout;
  }

  Future<void> respondToReview(String reviewId, String response) async {
    await _supabase.rpc('set_owner_review_response', params: {
      'p_review_id': reviewId,
      'p_response': response,
    }).withNetworkTimeout;
    // Notification inserted by DB trigger on_review_response_added
  }

  Future<void> deleteOwnerResponse(String reviewId) async {
    await _supabase.rpc('delete_owner_review_response', params: {
      'p_review_id': reviewId,
    }).withNetworkTimeout;
  }
}
