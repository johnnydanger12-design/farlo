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
    this.startTime,
    this.endTime,
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
  final String? startTime; // "HH:MM", same convention as OperatingHours
  final String? endTime;
  final DateTime createdAt;

  factory PlannedLocation.fromMap(Map<String, dynamic> m) {
    // Postgres `time` columns come back as "HH:MM:SS" — trim to "HH:MM" to
    // match this project's existing OperatingHours convention.
    String? parseTime(dynamic v) =>
        v == null ? null : (v as String).substring(0, 5);
    return PlannedLocation(
      id: m['id'] as String,
      truckId: m['truck_id'] as String,
      eventDate: DateTime.parse(m['event_date'] as String),
      title: m['title'] as String,
      address: m['address'] as String?,
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      notes: m['notes'] as String?,
      startTime: parseTime(m['start_time']),
      endTime: parseTime(m['end_time']),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}
