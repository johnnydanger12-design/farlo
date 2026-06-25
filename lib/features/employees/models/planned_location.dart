class PlannedLocation {
  const PlannedLocation({
    required this.id,
    required this.truckId,
    required this.eventDate,
    required this.title,
    this.address,
    this.latitude,
    this.longitude,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String truckId;
  final DateTime eventDate;
  final String title;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final DateTime createdAt;

  factory PlannedLocation.fromMap(Map<String, dynamic> m) => PlannedLocation(
        id: m['id'] as String,
        truckId: m['truck_id'] as String,
        eventDate: DateTime.parse(m['event_date'] as String),
        title: m['title'] as String,
        address: m['address'] as String?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
