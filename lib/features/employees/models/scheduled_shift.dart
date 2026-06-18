class ScheduledShift {
  const ScheduledShift({
    required this.id,
    required this.truckId,
    required this.employeeId,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.notes,
    this.employeeName,
  });

  final String id;
  final String truckId;
  final String employeeId;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final String status; // 'pending' | 'accepted' | 'declined'
  final String createdBy;
  final DateTime createdAt;
  final String? notes;
  final String? employeeName; // joined from profiles — owner view only

  Duration get duration => scheduledEnd.difference(scheduledStart);

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';

  ScheduledShift copyWith({String? status}) {
    return ScheduledShift(
      id: id,
      truckId: truckId,
      employeeId: employeeId,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      status: status ?? this.status,
      createdBy: createdBy,
      createdAt: createdAt,
      notes: notes,
      employeeName: employeeName,
    );
  }

  factory ScheduledShift.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profiles'] as Map<String, dynamic>?;
    return ScheduledShift(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      employeeId: map['employee_id'] as String,
      scheduledStart:
          DateTime.parse(map['scheduled_start'] as String).toLocal(),
      scheduledEnd: DateTime.parse(map['scheduled_end'] as String).toLocal(),
      status: map['status'] as String,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      notes: map['notes'] as String?,
      employeeName: profileMap?['display_name'] as String?,
    );
  }
}
