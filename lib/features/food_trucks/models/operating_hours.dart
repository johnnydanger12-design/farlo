class OperatingHours {
  const OperatingHours({
    required this.id,
    required this.truckId,
    required this.dayOfWeek,
    this.openTime,
    this.closeTime,
    required this.isClosed,
  });

  final String id;
  final String truckId;
  final int dayOfWeek; // 0 = Sunday
  final String? openTime; // "HH:MM"
  final String? closeTime;
  final bool isClosed;

  static const List<String> dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  String get dayName => dayNames[dayOfWeek];

  String get hoursDisplay {
    if (isClosed) return 'Closed';
    if (openTime == null || closeTime == null) return 'Hours not set';
    return '${_formatTime(openTime!)} – ${_formatTime(closeTime!)}';
  }

  static String _formatTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return minute == '00' ? '$displayHour $period' : '$displayHour:$minute $period';
  }

  factory OperatingHours.fromMap(Map<String, dynamic> map) {
    String? parseTime(dynamic val) {
      if (val == null) return null;
      final s = val as String;
      return s.substring(0, 5); // trim seconds from "HH:MM:SS"
    }

    return OperatingHours(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      dayOfWeek: map['day_of_week'] as int,
      openTime: parseTime(map['open_time']),
      closeTime: parseTime(map['close_time']),
      isClosed: map['is_closed'] as bool? ?? false,
    );
  }

  OperatingHours copyWith({
    String? openTime,
    String? closeTime,
    bool? isClosed,
  }) {
    return OperatingHours(
      id: id,
      truckId: truckId,
      dayOfWeek: dayOfWeek,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  Map<String, dynamic> toMap() => {
    'truck_id': truckId,
    'day_of_week': dayOfWeek,
    'open_time': openTime,
    'close_time': closeTime,
    'is_closed': isClosed,
  };
}
