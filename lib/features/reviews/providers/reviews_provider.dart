import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/reviews_repository.dart';
import '../models/review.dart';

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(Supabase.instance.client);
});

class TruckReviewsBundle {
  const TruckReviewsBundle({required this.reviews, required this.myReview});
  final List<Review> reviews;
  final Review? myReview;
}

// All reviews for a truck + the current user's own review, fetched together.
// These were 2 independent providers (truck_profile_screen.dart's build()
// watched both back-to-back and every mutation site invalidated both in
// lockstep — proof they're really one conceptual unit, not two) — combined
// into 1 round trip via 2 futures started together and awaited in sequence
// (both requests are already in flight before the first `await`, so this is
// genuinely concurrent, not sequential).
final truckReviewsBundleProvider =
    FutureProvider.autoDispose.family<TruckReviewsBundle, String>((ref, truckId) async {
  final repo = ref.read(reviewsRepositoryProvider);
  final reviewsFuture = repo.fetchForTruck(truckId);
  final myReviewFuture = repo.fetchMyReview(truckId);
  return TruckReviewsBundle(reviews: await reviewsFuture, myReview: await myReviewFuture);
});
