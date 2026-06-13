class TruckEmployee {
  const TruckEmployee({
    required this.id,
    required this.truckId,
    required this.invitedEmail,
    this.userId,
    required this.status,
    required this.invitedAt,
    this.linkedAt,
    this.displayName,
  });

  final String id;
  final String truckId;
  final String invitedEmail;
  final String? userId;
  final String status; // 'pending' | 'active' | 'removed'
  final DateTime invitedAt;
  final DateTime? linkedAt;
  final String? displayName; // joined from profiles when available

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  factory TruckEmployee.fromMap(Map<String, dynamic> map) {
    return TruckEmployee(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      invitedEmail: map['invited_email'] as String,
      userId: map['user_id'] as String?,
      status: map['status'] as String,
      invitedAt: DateTime.parse(map['invited_at'] as String),
      linkedAt: map['linked_at'] != null
          ? DateTime.parse(map['linked_at'] as String)
          : null,
      displayName: (map['profiles'] as Map<String, dynamic>?)?['display_name'] as String?,
    );
  }
}
