import '../../map/models/food_truck.dart';

class FavoriteEntry {
  const FavoriteEntry({
    required this.id,
    required this.userId,
    required this.truckId,
    required this.createdAt,
    this.truck,
  });

  final String id;
  final String userId;
  final String truckId;
  final DateTime createdAt;
  final FoodTruck? truck;

  factory FavoriteEntry.fromMap(Map<String, dynamic> map) {
    return FavoriteEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      truckId: map['truck_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      truck: map['food_trucks'] != null
          ? FoodTruck.fromMap(map['food_trucks'] as Map<String, dynamic>)
          : null,
    );
  }
}
