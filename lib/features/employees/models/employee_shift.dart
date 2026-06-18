class EmployeeShift {
  const EmployeeShift({
    required this.id,
    required this.employeeId,
    required this.truckId,
    required this.clockedInAt,
    this.clockedOutAt,
    this.locationAddress,
    this.employeeName,
  });

  final String id;
  final String employeeId;
  final String truckId;
  final DateTime clockedInAt;
  final DateTime? clockedOutAt;
  final String? locationAddress;
  final String? employeeName; // joined from profiles — owner view only

  bool get isActive => clockedOutAt == null;

  Duration get elapsed {
    final end = clockedOutAt ?? DateTime.now().toUtc();
    return end.difference(clockedInAt);
  }

  EmployeeShift copyWith({DateTime? clockedOutAt}) {
    return EmployeeShift(
      id: id,
      employeeId: employeeId,
      truckId: truckId,
      clockedInAt: clockedInAt,
      clockedOutAt: clockedOutAt ?? this.clockedOutAt,
      locationAddress: locationAddress,
      employeeName: employeeName,
    );
  }

  factory EmployeeShift.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profiles'] as Map<String, dynamic>?;
    return EmployeeShift(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      truckId: map['truck_id'] as String,
      clockedInAt: DateTime.parse(map['clocked_in_at'] as String).toLocal(),
      clockedOutAt: map['clocked_out_at'] != null
          ? DateTime.parse(map['clocked_out_at'] as String).toLocal()
          : null,
      locationAddress: map['location_address'] as String?,
      employeeName: profileMap?['display_name'] as String?,
    );
  }
}
