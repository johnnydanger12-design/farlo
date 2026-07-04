import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/reviews_repository.dart';
import '../models/review.dart';

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(Supabase.instance.client);
});

// All reviews for a truck, ordered newest-first.
final truckReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>((ref, truckId) {
  return ref.read(reviewsRepositoryProvider).fetchForTruck(truckId);
});

// The current user's review for a truck, if any.
final myReviewProvider = FutureProvider.autoDispose.family<Review?, String>((ref, truckId) {
  return ref.read(reviewsRepositoryProvider).fetchMyReview(truckId);
});
