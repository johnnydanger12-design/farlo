class FoodTruck {
  const FoodTruck({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.cuisineType,
    this.description,
    this.logoUrl,
    required this.latitude,
    required this.longitude,
    required this.averageRating,
    required this.reviewCount,
    required this.isOpen,
    required this.isActive,
  });

  final String id;
  final String ownerId;
  final String name;
  final String cuisineType;
  final String? description;
  final String? logoUrl;
  final double latitude;
  final double longitude;
  final double averageRating;
  final int reviewCount;
  final bool isOpen;
  final bool isActive;

  factory FoodTruck.fromMap(Map<String, dynamic> map) {
    return FoodTruck(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      cuisineType: map['cuisine_type'] as String,
      description: map['description'] as String?,
      logoUrl: map['logo_url'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      averageRating: (map['average_rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      isOpen: map['is_open'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? false,
    );
  }
}
