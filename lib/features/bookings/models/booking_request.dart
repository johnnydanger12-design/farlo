class BookingRequest {
  const BookingRequest({
    required this.id,
    required this.truckId,
    this.truckName,
    this.requesterId,
    required this.contactName,
    required this.contactEmail,
    this.contactPhone,
    required this.eventDate,
    required this.eventTime,
    this.duration,
    this.guestCount,
    required this.eventLocation,
    required this.eventType,
    this.notes,
    required this.status,
    this.cancellationReason,
    this.cancelledBy,
    required this.createdAt,
  });

  final String id;
  final String truckId;
  final String? truckName;
  final String? requesterId;
  final String contactName;
  final String contactEmail;
  final String? contactPhone;
  final DateTime eventDate;
  final String eventTime;
  final String? duration;
  final int? guestCount;
  final String eventLocation;
  final String eventType;
  final String? notes;
  final String status;
  final String? cancellationReason;
  final String? cancelledBy;
  final DateTime createdAt;

  factory BookingRequest.fromMap(Map<String, dynamic> map) {
    return BookingRequest(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      truckName: (map['food_trucks'] as Map<String, dynamic>?)?['name'] as String?,
      requesterId: map['requester_id'] as String?,
      contactName: map['contact_name'] as String,
      contactEmail: map['contact_email'] as String,
      contactPhone: map['contact_phone'] as String?,
      eventDate: DateTime.parse(map['event_date'] as String),
      eventTime: map['event_time'] as String,
      duration: map['duration'] as String?,
      guestCount: map['guest_count'] as int?,
      eventLocation: map['event_location'] as String,
      eventType: map['event_type'] as String,
      notes: map['notes'] as String?,
      status: map['status'] as String,
      cancellationReason: map['cancellation_reason'] as String?,
      cancelledBy: map['cancelled_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

const eventTypes = [
  'Birthday Party',
  'Corporate Event',
  'Wedding',
  'Community Event',
  'Festival / Fair',
  'Graduation',
  'Other',
];
