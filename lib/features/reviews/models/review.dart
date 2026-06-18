class Review {
  const Review({
    required this.id,
    required this.truckId,
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.ownerResponse,
    this.ownerRespondedAt,
  });

  final String id;
  final String truckId;
  final String userId;
  final String userDisplayName;
  final String? userAvatarUrl;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? ownerResponse;
  final DateTime? ownerRespondedAt;

  factory Review.fromMap(Map<String, dynamic> map) {
    return Review(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      userId: map['user_id'] as String,
      userDisplayName: map['user_display_name'] as String,
      userAvatarUrl: map['user_avatar_url'] as String?,
      rating: (map['rating'] as num).toInt(),
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      ownerResponse: map['owner_response'] as String?,
      ownerRespondedAt: map['owner_responded_at'] != null
          ? DateTime.parse(map['owner_responded_at'] as String)
          : null,
    );
  }
}
